import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_file_metadata_service.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/utils/concurrency.dart';

class MediaGpsFileImportResult {
  MediaGpsFileImportResult({
    required this.withGps,
    required this.withoutGps,
    required this.unsupported,
  });

  final List<MediaGpsPickedAsset> withGps;
  final int withoutGps;
  final int unsupported;
}

/// Per-file result of parsing a picked file (one of: a GPS-bearing asset, a
/// file without GPS, an unsupported file, or a skipped/no-path entry).
class _PickedFileOutcome {
  const _PickedFileOutcome.withGps(this.asset)
      : withoutGps = false,
        unsupported = false;
  const _PickedFileOutcome.withoutGps()
      : asset = null,
        withoutGps = true,
        unsupported = false;
  const _PickedFileOutcome.unsupported()
      : asset = null,
        withoutGps = false,
        unsupported = true;
  const _PickedFileOutcome.skip()
      : asset = null,
        withoutGps = false,
        unsupported = false;

  final MediaGpsPickedAsset? asset;
  final bool withoutGps;
  final bool unsupported;
}

/// Picks images, videos, and audio from the system file browser.
class MediaGpsFileImportService {
  /// Concurrency for parsing picked files. Kept modest because video parsing
  /// reads up to ~48 MB of the container and spins up a VideoPlayerController,
  /// so too many in flight at once would spike memory.
  static const int _parseConcurrency = 4;

  static Future<MediaGpsFileImportResult?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: MediaGpsFileMetadataService.pickableFileExtensions,
      allowMultiple: true,
      withReadStream: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final stagingDir = await _ensureStagingDir();

    // Parse files in parallel (bounded). Each file is independent and the
    // metadata readers are stateless, so this safely cuts the post-pick wait
    // for multi-file selections (the slowest part for videos).
    final parseSw = Stopwatch()..start();
    final outcomes = await mapWithConcurrency<PlatformFile, _PickedFileOutcome>(
      result.files,
      _parseConcurrency,
      (f, _) => _processPickedFile(f, stagingDir),
    );
    parseSw.stop();

    final withGps = <MediaGpsPickedAsset>[];
    var withoutGps = 0;
    var unsupported = 0;
    for (final o in outcomes) {
      if (o.asset != null) {
        withGps.add(o.asset!);
      } else if (o.withoutGps) {
        withoutGps++;
      } else if (o.unsupported) {
        unsupported++;
      }
    }

    debugPrint(
      '[MediaGpsFileImport] ⏱️ parsed ${result.files.length} files in '
      '${parseSw.elapsedMilliseconds}ms (concurrency=$_parseConcurrency) → '
      'gps=${withGps.length}, noGps=$withoutGps, unsupported=$unsupported',
    );

    return MediaGpsFileImportResult(
      withGps: withGps,
      withoutGps: withoutGps,
      unsupported: unsupported,
    );
  }

  static Future<_PickedFileOutcome> _processPickedFile(
    PlatformFile f,
    Directory stagingDir,
  ) async {
    final rawPath = f.path;
    if (rawPath == null || rawPath.isEmpty) return const _PickedFileOutcome.skip();
    final sourcePath = MemoryController.normalizeLocalFilePath(rawPath);

    if (!MediaGpsFileMetadataService.isAllowedPickerExtension(
      f.extension,
      sourcePath,
    )) {
      return const _PickedFileOutcome.unsupported();
    }
    if (!MediaGpsFileMetadataService.isPickableMediaPath(sourcePath)) {
      return const _PickedFileOutcome.unsupported();
    }

    try {
      // Read metadata from the picker's already-downloaded copy first; only
      // copy into staging if the file actually has GPS, so files that get
      // discarded (no GPS / unsupported) don't pay the copy cost.
      final meta = await MediaGpsFileMetadataService.readMetadata(sourcePath);
      final kind = MediaGpsFileMetadataService.kindForPath(sourcePath);
      // Audio is not importable in this flow — only photos and videos.
      if (kind != MediaGpsFileKind.image &&
          kind != MediaGpsFileKind.video) {
        return const _PickedFileOutcome.unsupported();
      }

      if (meta.latitude == null ||
          meta.longitude == null ||
          (meta.latitude!.abs() < 1e-6 && meta.longitude!.abs() < 1e-6)) {
        debugPrint(
          '[MediaGpsFileImport] ⚠️ no GPS: ${f.name}'
          '  lat=${meta.latitude}  lng=${meta.longitude}',
        );
        return const _PickedFileOutcome.withoutGps();
      }

      final stagedPath = await _copyIntoStaging(
        sourcePath: sourcePath,
        stagingDir: stagingDir,
        displayName: f.name,
      );
      final stat = await File(stagedPath).stat();
      final createTime = meta.createTime ?? stat.modified;
      final id = _stableFileId(
        stagedPath,
        stat.size,
        stat.modified.millisecondsSinceEpoch,
      );

      debugPrint(
        '[MediaGpsFileImport] ✅ ${f.name}'
        '  lat=${meta.latitude?.toStringAsFixed(6)}'
        '  lng=${meta.longitude?.toStringAsFixed(6)}'
        '  kind=$kind',
      );
      return _PickedFileOutcome.withGps(
        MediaGpsPickedAsset.fromFile(
          id: id,
          localPath: stagedPath,
          fileKind: kind,
          createTime: createTime,
          latitude: meta.latitude,
          longitude: meta.longitude,
          modifiedTime: stat.modified,
          fileTitle: p.basenameWithoutExtension(f.name),
          videoDuration: meta.videoDuration,
        ),
      );
    } catch (e, st) {
      debugPrint('[MediaGpsFileImport] skip $rawPath: $e\n$st');
      return const _PickedFileOutcome.unsupported();
    }
  }

  static Future<Directory> _ensureStagingDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'media_gps_file_staging'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> _copyIntoStaging({
    required String sourcePath,
    required Directory stagingDir,
    required String displayName,
  }) async {
    final src = File(sourcePath);
    final safeName = p.basename(displayName).replaceAll(RegExp(r'[^\w.\-]'), '_');
    final dest = File(
      p.join(
        stagingDir.path,
        '${DateTime.now().microsecondsSinceEpoch}_$safeName',
      ),
    );
    await src.copy(dest.path);
    return dest.path;
  }

  static String _stableFileId(String path, int size, int modifiedMs) {
    final digest = sha256.convert(
      utf8.encode('$path|$size|$modifiedMs'),
    );
    return 'file:${digest.toString()}';
  }
}
