import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_file_metadata_service.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';

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

class _RawPick {
  const _RawPick({
    required this.displayName,
    this.path,
    this.extension,
    this.bytes,
  });

  final String? path;
  final String displayName;
  final String? extension;
  final List<int>? bytes;
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

/// Picks images and videos from the system picker and parses GPS metadata.
class MediaGpsFileImportService {
  static Future<MediaGpsFileImportResult?> pickAndParse() async {
    final picks = Platform.isIOS
        ? await _pickViaImagePicker()
        : await _pickViaFilePicker();
    if (picks == null || picks.isEmpty) return null;

    // End native picker work first; parse one-by-one so the UI can breathe.
    final stagingDir = await _ensureStagingDir();
    final parseSw = Stopwatch()..start();
    final withGps = <MediaGpsPickedAsset>[];
    final seenAssetIds = <String>{};
    var withoutGps = 0;
    var unsupported = 0;
    var skippedDupInBatch = 0;

    for (var i = 0; i < picks.length; i++) {
      // Yield between files so the spinner can paint and the app stays responsive.
      await Future<void>.delayed(Duration.zero);
      final outcome = await _processRawPick(picks[i], stagingDir).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint(
            '[MediaGpsFileImport] ⏱️ timeout parsing ${picks[i].displayName}',
          );
          return const _PickedFileOutcome.unsupported();
        },
      );
      if (outcome.asset != null) {
        if (!seenAssetIds.add(outcome.asset!.id)) {
          skippedDupInBatch++;
        } else {
          withGps.add(outcome.asset!);
        }
      } else if (outcome.withoutGps) {
        withoutGps++;
      } else if (outcome.unsupported) {
        unsupported++;
      }
    }
    parseSw.stop();

    if (skippedDupInBatch > 0) {
      debugPrint(
        '[MediaGpsFileImport] skipped $skippedDupInBatch duplicate(s) in batch',
      );
    }

    debugPrint(
      '[MediaGpsFileImport] ⏱️ parsed ${picks.length} files in '
      '${parseSw.elapsedMilliseconds}ms → '
      'gps=${withGps.length}, noGps=$withoutGps, unsupported=$unsupported',
    );

    return MediaGpsFileImportResult(
      withGps: withGps,
      withoutGps: withoutGps,
      unsupported: unsupported,
    );
  }

  /// iOS: PHPicker shows photos + videos reliably.
  static Future<List<_RawPick>?> _pickViaImagePicker() async {
    final selected = await ImagePicker().pickMultipleMedia(
      requestFullMetadata: false,
    );
    if (selected.isEmpty) return null;

    final picks = <_RawPick>[];
    final seen = <String>{};
    for (final x in selected) {
      final path = x.path;
      if (path.isEmpty || !seen.add(path)) continue;
      final name = x.name.isNotEmpty ? x.name : p.basename(path);
      final mime = x.mimeType?.toLowerCase() ?? '';
      var ext = p.extension(name).replaceFirst('.', '');
      if (ext.isEmpty && mime.startsWith('video/')) {
        ext = mime.contains('quicktime') ? 'mov' : 'mp4';
      } else if (ext.isEmpty && mime.startsWith('image/')) {
        ext = mime.contains('png') ? 'png' : 'jpg';
      }
      picks.add(_RawPick(path: path, displayName: name, extension: ext));
    }
    return picks;
  }

  /// Android: FileType.custom with MIME-safe image+video extensions only.
  /// (Unknown MIME extensions made file_picker fall back to */* → .xml selectable.)
  static Future<List<_RawPick>?> _pickViaFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: MediaGpsFileMetadataService.androidPickerExtensions,
      allowMultiple: true,
      withReadStream: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final picks = <_RawPick>[];
    final seen = <String>{};
    var blocked = 0;
    for (final f in result.files) {
      final key = '${f.path ?? ''}|${f.name}|${f.size}';
      if (!seen.add(key)) continue;
      final pathHint = f.path ?? f.name;
      final kind = MediaGpsFileMetadataService.kindForPickerFile(
        extension: f.extension,
        path: pathHint,
        displayName: f.name,
      );
      if (kind != MediaGpsFileKind.image && kind != MediaGpsFileKind.video) {
        blocked++;
        debugPrint(
          '[MediaGpsFileImport] blocked non-media: ${f.name} (.${f.extension})',
        );
        continue;
      }
      picks.add(
        _RawPick(
          path: f.path,
          displayName: f.name,
          extension: f.extension,
          bytes: f.bytes,
        ),
      );
    }
    if (blocked > 0) {
      debugPrint('[MediaGpsFileImport] blocked $blocked non-media file(s)');
    }
    return picks.isEmpty ? null : picks;
  }

  static Future<_PickedFileOutcome> _processRawPick(
    _RawPick f,
    Directory stagingDir,
  ) async {
    final sourcePath = await _resolveReadablePathFromRaw(f, stagingDir);
    if (sourcePath == null || sourcePath.isEmpty) {
      debugPrint('[MediaGpsFileImport] skip (no path): ${f.displayName}');
      return const _PickedFileOutcome.skip();
    }

    final kind = MediaGpsFileMetadataService.kindForPickerFile(
      extension: f.extension,
      path: sourcePath,
      displayName: f.displayName,
    );
    if (kind != MediaGpsFileKind.image && kind != MediaGpsFileKind.video) {
      return const _PickedFileOutcome.unsupported();
    }

    try {
      final meta = await MediaGpsFileMetadataService.readMetadata(
        sourcePath,
        kindHint: kind,
        includeDuration: false,
      );

      if (meta.latitude == null ||
          meta.longitude == null ||
          (meta.latitude!.abs() < 1e-6 && meta.longitude!.abs() < 1e-6)) {
        debugPrint(
          '[MediaGpsFileImport] ⚠️ no GPS: ${f.displayName}'
          '  lat=${meta.latitude}  lng=${meta.longitude}',
        );
        return const _PickedFileOutcome.withoutGps();
      }

      final sourceStat = await File(sourcePath).stat();
      final createTime = meta.createTime ?? sourceStat.modified;
      final id = _stableContentId(
        displayName: f.displayName,
        size: sourceStat.size,
        createTime: createTime,
        kind: kind,
        lat: meta.latitude,
        lng: meta.longitude,
      );

      debugPrint(
        '[MediaGpsFileImport] ✅ ${f.displayName}'
        '  lat=${meta.latitude?.toStringAsFixed(6)}'
        '  lng=${meta.longitude?.toStringAsFixed(6)}'
        '  kind=$kind',
      );
      return _PickedFileOutcome.withGps(
        MediaGpsPickedAsset.fromFile(
          id: id,
          localPath: sourcePath,
          fileKind: kind,
          createTime: createTime,
          latitude: meta.latitude,
          longitude: meta.longitude,
          modifiedTime: sourceStat.modified,
          fileTitle: p.basenameWithoutExtension(f.displayName),
          videoDuration: meta.videoDuration,
        ),
      );
    } catch (e, st) {
      debugPrint('[MediaGpsFileImport] skip $sourcePath: $e\n$st');
      return const _PickedFileOutcome.unsupported();
    }
  }

  static Future<String?> _resolveReadablePathFromRaw(
    _RawPick f,
    Directory stagingDir,
  ) async {
    final rawPath = f.path;
    if (rawPath != null && rawPath.isNotEmpty) {
      final normalized = MemoryController.normalizeLocalFilePath(rawPath);
      if (await File(normalized).exists()) return normalized;
      if (await File(rawPath).exists()) return rawPath;
    }
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final safeName =
        p.basename(f.displayName).replaceAll(RegExp(r'[^\w.\-]'), '_');
    final dest = File(
      p.join(
        stagingDir.path,
        'pick_${DateTime.now().microsecondsSinceEpoch}_$safeName',
      ),
    );
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  static Future<Directory> _ensureStagingDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'media_gps_file_staging'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Identity that survives re-staging the same underlying file.
  /// Deliberately omits filesystem mtime — Android re-copies often change it
  /// and would otherwise mint a new id for the same photo.
  static String _stableContentId({
    required String displayName,
    required int size,
    required DateTime createTime,
    required MediaGpsFileKind kind,
    double? lat,
    double? lng,
  }) {
    final name = p.basename(displayName).toLowerCase();
    final tMs = createTime.toUtc().millisecondsSinceEpoch;
    final latS = (lat ?? 0).toStringAsFixed(5);
    final lngS = (lng ?? 0).toStringAsFixed(5);
    final digest = sha256.convert(
      utf8.encode('v2|$name|$size|$tMs|${kind.name}|$latS|$lngS'),
    );
    return 'file:${digest.toString()}';
  }
}
