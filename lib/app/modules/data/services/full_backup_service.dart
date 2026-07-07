import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/spacetime_backup_zip.dart';
import 'package:spacetime/app/services/memory_db.dart';

class FullBackupResult {
  const FullBackupResult({
    required this.ok,
    required this.messageKey,
    this.messageArgs = const [],
    this.filePath,
  });

  final bool ok;
  /// [L10nLoader] key; resolved with [messageArgs] via [trKey].
  final String messageKey;
  final List<Object?> messageArgs;
  final String? filePath;
}

class FullBackupService {
  static const String _dbFileName = 'memories.db';

  static Future<FullBackupResult> exportFullBackup() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(appDir.path, _dbFileName);
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return const FullBackupResult(
          ok: false,
          messageKey: 'backup_err_database_not_found',
        );
      }

      // Ensure the on-disk DB file is self-contained before copy (WAL → main file).
      await DatabaseHelper.instance.flushWalForBackupSnapshot();

      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final backupName = 'spacetime_backup_$stamp.zip';
      final tmpDir = await getTemporaryDirectory();
      final outZipPath = p.join(tmpDir.path, backupName);
      final outZipFile = File(outZipPath);
      if (await outZipFile.exists()) {
        await outZipFile.delete();
      }

      // Stage under app support, zip under system temp — different roots so
      // [ZipFileEncoder] never hits `path.isWithin(staging, zip)` (FormatException).
      final supportDir = await getApplicationSupportDirectory();
      final stagingRoot = Directory(
        p.join(supportDir.path, 'spacetime_backup_staging_$stamp'),
      );
      if (await stagingRoot.exists()) {
        await stagingRoot.delete(recursive: true);
      }
      await stagingRoot.create(recursive: true);
      try {
        final dbDest = File(p.join(stagingRoot.path, 'db', _dbFileName));
        await dbDest.parent.create(recursive: true);
        await dbFile.copy(dbDest.path);

        final mediaDir = Directory(p.join(stagingRoot.path, 'media'));
        await mediaDir.create(recursive: true);
        final mediaPairs = await _collectStoredAndAbsoluteMediaPaths();
        final mediaManifest = <String, String>{};
        var index = 0;
        for (final pair in mediaPairs) {
          final f = File(pair.absolutePath);
          if (!await f.exists()) continue;
          var ext = p.extension(pair.absolutePath);
          if (ext.isEmpty) ext = p.extension(p.basename(pair.absolutePath));
          if (ext.isEmpty) ext = '.bin';
          final rel = 'media/$index$ext';
          final dest = File(p.join(stagingRoot.path, rel));
          await dest.parent.create(recursive: true);
          await f.copy(dest.path);
          // Keys must match DB column values (often relative paths); absolute paths break cross-platform remap.
          mediaManifest[pair.storedPath] = rel;
          index++;
          if (index % 6 == 0) await Future<void>.delayed(Duration.zero);
        }

        final meta = <String, dynamic>{
          'format_version': 1,
          'created_at': now.toIso8601String(),
          'media_manifest': mediaManifest,
        };
        await File(p.join(stagingRoot.path, 'meta.json'))
            .writeAsString(jsonEncode(meta), flush: true);

        final encoder = ZipFileEncoder();
        await encoder.zipDirectoryAsync(
          stagingRoot,
          filename: outZipPath,
          level: ZipFileEncoder.STORE,
        );
      } finally {
        try {
          if (await stagingRoot.exists()) {
            await stagingRoot.delete(recursive: true);
          }
        } catch (e) {
          debugPrint('[FullBackupService] staging cleanup: $e');
        }
      }

      if (!await outZipFile.exists() || await outZipFile.length() == 0) {
        return const FullBackupResult(
          ok: false,
          messageKey: 'backup_err_zip_create_failed',
        );
      }

      // iOS/Android: FilePicker.saveFile often hangs indefinitely; write to app folder only.
      String? pickedPath;
      if (kIsWeb) {
        final zipBytes = await outZipFile.readAsBytes();
        try {
          pickedPath = await FilePicker.platform.saveFile(
            dialogTitle: 'backup_export_dialog_title'.tr,
            fileName: backupName,
            type: FileType.custom,
            allowedExtensions: const ['zip'],
            bytes: Uint8List.fromList(zipBytes),
          );
        } catch (_) {
          pickedPath = null;
        }
      } else if (Platform.isIOS || Platform.isAndroid) {
        pickedPath = null;
      } else {
        final zipBytes = await outZipFile.readAsBytes();
        try {
          pickedPath = await FilePicker.platform.saveFile(
            dialogTitle: 'backup_export_dialog_title'.tr,
            fileName: backupName,
            type: FileType.custom,
            allowedExtensions: const ['zip'],
            bytes: Uint8List.fromList(zipBytes),
          );
        } catch (_) {
          pickedPath = null;
        }
      }

      if (pickedPath != null && pickedPath.isNotEmpty) {
        if (p.normalize(pickedPath) != p.normalize(outZipPath)) {
          await outZipFile.copy(pickedPath);
        }
        return FullBackupResult(
          ok: true,
          messageKey: 'backup_ok_export_success',
          filePath: pickedPath,
        );
      }

      final fallbackDir = Directory(p.join(appDir.path, 'backups'));
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      final fallbackPath = p.join(fallbackDir.path, backupName);
      await outZipFile.copy(fallbackPath);
      return FullBackupResult(
        ok: true,
        messageKey: 'backup_ok_export_documents',
        filePath: fallbackPath,
      );
    } catch (e, st) {
      debugPrint('[FullBackupService] export failed: $e\n$st');
      return FullBackupResult(
        ok: false,
        messageKey: 'backup_err_export_failed',
        messageArgs: [e],
      );
    }
  }

  static Future<FullBackupResult> importFullBackup() async {
    final zipPath = await pickBackupZipPath();
    if (zipPath == null) {
      return const FullBackupResult(
        ok: false,
        messageKey: 'backup_err_no_file_selected',
      );
    }
    return importFullBackupFromPath(zipPath);
  }

  /// Opens the system file picker and returns a stable temp path to the zip.
  static Future<String?> pickBackupZipPath() async {
    try {
      final picked = await _pickBackupZipFile();
      if (picked == null || picked.files.isEmpty) return null;
      final file = picked.files.first;
      if (!_isZipFileName(file.name)) return null;
      return await _materializePickedZipToTemp(file);
    } catch (e, st) {
      debugPrint('[FullBackupService] pick backup zip: $e\n$st');
      rethrow;
    }
  }

  static Future<FullBackupResult> importFullBackupFromPath(String zipPath) async {
    var dbClosedForReplace = false;
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return const FullBackupResult(
          ok: false,
          messageKey: 'backup_err_path_missing',
        );
      }

      // readAsBytes worked reliably before; stream decode can fail on iOS picker paths.
      final zipBytes = await zipFile.readAsBytes();
      if (zipBytes.isEmpty) {
        return const FullBackupResult(
          ok: false,
          messageKey: 'backup_err_invalid_db',
        );
      }
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: false);

      ArchiveFile? dbEntryInFolder;
      ArchiveFile? dbEntryAtRoot;
      ArchiveFile? metaEntry;
      final mediaEntries = <ArchiveFile>[];
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final n = _normalizeZipInternalPath(entry.name);
        if (n == 'db/$_dbFileName') dbEntryInFolder = entry;
        if (n == _dbFileName) dbEntryAtRoot = entry;
        if (n == 'meta.json') metaEntry = entry;
        if (n.startsWith('media/')) mediaEntries.add(entry);
      }
      final dbEntry = dbEntryInFolder ?? dbEntryAtRoot;

      if (dbEntry == null) {
        return const FullBackupResult(
          ok: false,
          messageKey: 'backup_err_invalid_db',
        );
      }

      if (!SpaceTimeBackupZip.archiveIsBackup(archive)) {
        return const FullBackupResult(
          ok: false,
          messageKey: 'backup_err_invalid_db',
        );
      }

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(appDir.path, _dbFileName);

      Map<String, dynamic> meta = <String, dynamic>{};
      if (metaEntry != null) {
        final m = utf8.decode(metaEntry.content as List<int>, allowMalformed: true);
        try {
          final d = jsonDecode(m);
          if (d is Map<String, dynamic>) meta = d;
        } catch (_) {}
      }
      final manifestRaw = meta['media_manifest'];
      final manifest = <String, String>{};
      if (manifestRaw is Map) {
        for (final e in manifestRaw.entries) {
          manifest[e.key.toString()] = e.value.toString();
        }
      }

      final importMediaRoot = Directory(p.join(appDir.path, 'imported_media'));
      if (!await importMediaRoot.exists()) {
        await importMediaRoot.create(recursive: true);
      }
      final priorMedia = Directory(p.join(importMediaRoot.path, 'media'));
      if (await priorMedia.exists()) {
        try {
          await priorMedia.delete(recursive: true);
        } catch (e) {
          debugPrint('[FullBackupService] clear prior imported media: $e');
        }
      }

      final relToAbs = <String, String>{};
      for (final m in mediaEntries) {
        final rel = _normalizeZipInternalPath(m.name);
        final outPath = _resolveUnderRoot(importMediaRoot.path, rel);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(m.content as List<int>, flush: true);
        relToAbs[rel] = outPath;
      }

      // Must release the singleton handle before delete/replace, or SQLite sees
      // two connections / stale inode and BEGIN can throw disk I/O errors.
      await DatabaseHelper.instance.closeDatabaseOnly();
      dbClosedForReplace = true;

      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      for (final suffix in <String>['-wal', '-shm', '-journal']) {
        final sidecar = File(dbPath + suffix);
        if (await sidecar.exists()) {
          try {
            await sidecar.delete();
          } catch (_) {}
        }
      }
      await dbFile.writeAsBytes(dbEntry.content as List<int>, flush: true);

      final oldToNewPath = <String, String>{};
      for (final e in manifest.entries) {
        final rel = _normalizeZipInternalPath(e.value.toString());
        final abs = relToAbs[rel];
        if (abs != null) {
          oldToNewPath[e.key.toString()] = abs;
        } else {
          debugPrint('[FullBackupService] manifest zip path missing in archive: $rel');
        }
      }

      await _remapMediaPaths(dbPath, oldToNewPath);
      await DatabaseHelper.instance.resetDatabaseConnection();
      dbClosedForReplace = false;

      return FullBackupResult(
        ok: true,
        messageKey: 'backup_ok_import_success',
        filePath: zipPath,
      );
    } catch (e, st) {
      debugPrint('[FullBackupService] import failed: $e\n$st');
      if (dbClosedForReplace) {
        try {
          await DatabaseHelper.instance.resetDatabaseConnection();
        } catch (recoveryError) {
          debugPrint(
            '[FullBackupService] DB reopen after failed import: $recoveryError',
          );
        }
      }
      return FullBackupResult(
        ok: false,
        messageKey: 'backup_err_import_failed',
        messageArgs: [e],
      );
    }
  }

  /// iOS: [FileType.any] so zips appear in Recents; Android keeps zip filter.
  static Future<FilePickerResult?> _pickBackupZipFile() {
    if (!kIsWeb && Platform.isIOS) {
      return FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: false,
      );
    }
    return FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
      withReadStream: false,
    );
  }

  static bool _isZipFileName(String name) {
    final base = name.replaceAll(r'\', '/').split('/').last.toLowerCase();
    return base.endsWith('.zip');
  }

  /// Copy picker output into app temp — iOS security-scoped paths expire after pick.
  static Future<String> _materializePickedZipToTemp(PlatformFile file) async {
    final tmpDir = await getTemporaryDirectory();
    final safeName = _isZipFileName(file.name)
        ? file.name.replaceAll(r'\', '/').split('/').last
        : 'spacetime_import.zip';
    final destPath = p.join(
      tmpDir.path,
      'import_${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );

    if (file.path != null && file.path!.isNotEmpty) {
      final src = File(file.path!);
      if (await src.exists()) {
        await src.copy(destPath);
        return destPath;
      }
    }

    if (file.bytes != null && file.bytes!.isNotEmpty) {
      await File(destPath).writeAsBytes(file.bytes!, flush: true);
      return destPath;
    }

    throw StateError('Unable to read selected backup file');
  }

  /// One row may contribute two pairs (video path + thumbnail); same stored path deduped.
  ///
  /// Uses [DatabaseHelper.instance] only — never opens a second [SQLite] handle on the same
  /// file (that can cause `database is locked` during export while the app is running).
  static Future<List<({String storedPath, String absolutePath})>>
      _collectStoredAndAbsoluteMediaPaths() async {
    final db = await DatabaseHelper.instance.database;
    final byStored = <String, String>{};
    final appDir = await getApplicationDocumentsDirectory();
    final documentsDir = appDir.path;
    try {
      final audios = await db.query(
        DatabaseHelper.tableAudios,
        columns: [DatabaseHelper.columnAudioFilePath],
      );
      for (final r in audios) {
        final pth = (r[DatabaseHelper.columnAudioFilePath] ?? '').toString();
        final resolved = _resolveMediaFilePath(documentsDir, pth);
        if (resolved != null) byStored[pth] = resolved;
      }
      final videos = await db.query(
        DatabaseHelper.tableVideos,
        columns: [
          DatabaseHelper.columnVideoFilePath,
          DatabaseHelper.columnVideoThumbnailPath,
        ],
      );
      for (final r in videos) {
        final v = (r[DatabaseHelper.columnVideoFilePath] ?? '').toString();
        final t = (r[DatabaseHelper.columnVideoThumbnailPath] ?? '').toString();
        final rv = _resolveMediaFilePath(documentsDir, v);
        if (rv != null) byStored[v] = rv;
        final rt = _resolveMediaFilePath(documentsDir, t);
        if (rt != null) byStored[t] = rt;
      }
      final images = await db.query(
        DatabaseHelper.tableImages,
        columns: [DatabaseHelper.columnImageData],
      );
      for (final r in images) {
        final img = (r[DatabaseHelper.columnImageData] ?? '').toString();
        final resolved = _resolveMediaFilePath(documentsDir, img);
        if (resolved != null) byStored[img] = resolved;
      }
      return byStored.entries
          .map((e) => (storedPath: e.key, absolutePath: e.value))
          .toList();
    } catch (e, st) {
      debugPrint('[FullBackupService] collect media paths: $e\n$st');
      rethrow;
    }
  }

  static Future<void> _remapMediaPaths(
    String dbPath,
    Map<String, String> oldToNew,
  ) async {
    if (oldToNew.isEmpty) return;
    final db = await openDatabase(dbPath);
    try {
      await db.transaction((txn) async {
        for (final e in oldToNew.entries) {
          final oldPath = e.key;
          final newPath = e.value;
          await txn.update(
            DatabaseHelper.tableAudios,
            {DatabaseHelper.columnAudioFilePath: newPath},
            where: '${DatabaseHelper.columnAudioFilePath} = ?',
            whereArgs: [oldPath],
          );
          await txn.update(
            DatabaseHelper.tableVideos,
            {DatabaseHelper.columnVideoFilePath: newPath},
            where: '${DatabaseHelper.columnVideoFilePath} = ?',
            whereArgs: [oldPath],
          );
          await txn.update(
            DatabaseHelper.tableVideos,
            {DatabaseHelper.columnVideoThumbnailPath: newPath},
            where: '${DatabaseHelper.columnVideoThumbnailPath} = ?',
            whereArgs: [oldPath],
          );
          await txn.update(
            DatabaseHelper.tableImages,
            {DatabaseHelper.columnImageData: newPath},
            where: '${DatabaseHelper.columnImageData} = ?',
            whereArgs: [oldPath],
          );
        }
      });
    } finally {
      await db.close();
    }
  }

  /// Zip entries vary by tool/OS (`\`, leading `./`, optional `/`).
  static String _normalizeZipInternalPath(String name) {
    var n = name.replaceAll(r'\', '/').trim();
    while (n.startsWith('./')) {
      n = n.substring(2);
    }
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    return n;
  }

  /// Avoid passing strings with embedded `/` into a single [p.join] segment (Windows-safe).
  static String _resolveUnderRoot(String root, String posixLikeRelative) {
    final parts =
        posixLikeRelative.split('/').where((s) => s.isNotEmpty).toList();
    var out = root;
    for (final part in parts) {
      out = p.join(out, part);
    }
    return out;
  }

  static bool _looksLikeAbsolutePath(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('/')) return true;
    if (value.contains(r':\')) return true;
    return false;
  }

  /// DB may store app-relative paths (e.g. `memory_images/...`); only include if file exists.
  static String? _resolveMediaFilePath(String documentsDir, String stored) {
    if (stored.isEmpty) return null;
    if (_looksLikeAbsolutePath(stored)) {
      return File(stored).existsSync() ? stored : null;
    }
    if (stored.length > 600) return null;
    final normalized = stored.replaceAll(r'\', '/').trim();
    if (normalized.isEmpty) return null;
    final candidate = _resolveUnderRoot(documentsDir, normalized);
    return File(candidate).existsSync() ? candidate : null;
  }
}
