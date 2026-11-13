import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spacetime/app/modules/data/services/android_backup_downloads.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/spacetime_backup_zip.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/services/path_migration_helper.dart';

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
          // Exact DB value + portable aliases so iOS↔Android remap still hits.
          _addManifestKeys(mediaManifest, pair.storedPath, rel);
          index++;
          if (index % 6 == 0) await Future<void>.delayed(Duration.zero);
        }

        final meta = <String, dynamic>{
          'format_version': 2,
          'created_at': now.toIso8601String(),
          'media_manifest': mediaManifest,
          'shared_preferences': await _exportSharedPreferences(),
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

      // iOS: FilePicker.saveFile often hangs; keep app-folder + share sheet only.
      // Android: also write into public Downloads (MediaStore) so the zip is
      // visible in Files / Download.
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

      // Android only: also place a copy in the public Downloads folder.
      // iOS keeps the existing documents + share flow unchanged.
      var messageKey = 'backup_ok_export_documents';
      if (Platform.isAndroid) {
        final savedToDownloads = await AndroidBackupDownloads.saveZipToDownloads(
          sourcePath: fallbackPath,
          fileName: backupName,
        );
        if (savedToDownloads) {
          messageKey = 'backup_ok_export_downloads';
        }
      }

      return FullBackupResult(
        ok: true,
        messageKey: messageKey,
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
      final basenameToNew = <String, String>{};
      for (final e in manifest.entries) {
        final key = e.key.toString();
        final rel = _normalizeZipInternalPath(e.value.toString());
        final abs = relToAbs[rel];
        if (abs != null) {
          final importedRel = _relativeImportedMediaPath(rel);
          oldToNewPath[key] = importedRel;
          if (key.startsWith('__basename__:')) {
            basenameToNew[key.substring('__basename__:'.length)] = importedRel;
          } else {
            final base = p.basename(key.replaceAll(r'\', '/'));
            if (base.isNotEmpty) basenameToNew.putIfAbsent(base, () => importedRel);
          }
        } else {
          debugPrint('[FullBackupService] manifest zip path missing in archive: $rel');
        }
      }
      // Also index extracted files by basename for orphan absolute paths.
      for (final e in relToAbs.entries) {
        final base = p.basename(e.key);
        if (base.isNotEmpty) {
          basenameToNew.putIfAbsent(base, () => _relativeImportedMediaPath(e.key));
        }
      }

      await _remapMediaPaths(dbPath, oldToNewPath);
      await _healOrphanMediaPaths(dbPath, basenameToNew);
      await DatabaseHelper.instance.resetDatabaseConnection();
      dbClosedForReplace = false;

      // Convert any leftover absolute Documents/… paths to relative.
      try {
        await PathMigrationHelper.instance.migrateAllPathsToRelative();
      } catch (e) {
        debugPrint('[FullBackupService] path migration after import: $e');
      }

      final prefsRaw = meta['shared_preferences'];
      if (prefsRaw is Map) {
        await _importSharedPreferences(
          prefsRaw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }

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

  /// App-relative path under Documents for restored backup media.
  static String _relativeImportedMediaPath(String zipRelativePath) {
    final normalized = _normalizeZipInternalPath(zipRelativePath);
    return p.posix.join('imported_media', normalized);
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
    if (stored.length > 600 && !_looksLikeAbsolutePath(stored)) return null;

    if (_looksLikeAbsolutePath(stored)) {
      if (File(stored).existsSync()) return stored;
      // Absolute but missing on this device — try Documents-relative suffix.
      final rel = _relativeKeyFromStored(stored);
      if (rel != null) {
        final candidate = _resolveUnderRoot(documentsDir, rel);
        if (File(candidate).existsSync()) return candidate;
      }
      return null;
    }

    final normalized = stored.replaceAll(r'\', '/').trim();
    if (normalized.isEmpty) return null;
    final candidate = _resolveUnderRoot(documentsDir, normalized);
    return File(candidate).existsSync() ? candidate : null;
  }

  /// Register exact DB key + portable aliases (relative + basename).
  static void _addManifestKeys(
    Map<String, String> manifest,
    String storedPath,
    String zipRel,
  ) {
    if (storedPath.isEmpty) return;
    manifest[storedPath] = zipRel;
    final rel = _relativeKeyFromStored(storedPath);
    if (rel != null && rel.isNotEmpty && rel != storedPath) {
      manifest[rel] = zipRel;
    }
    final base = p.basename(storedPath.replaceAll(r'\', '/'));
    if (base.isNotEmpty && base.contains('.')) {
      manifest['__basename__:$base'] = zipRel;
    }
  }

  /// `/…/Documents/memory_images/x.jpg` → `memory_images/x.jpg`
  static String? _relativeKeyFromStored(String stored) {
    final n = stored.replaceAll(r'\', '/');
    const markers = <String>[
      '/Documents/',
      '/documents/',
      '/app_flutter/',
    ];
    for (final m in markers) {
      final i = n.indexOf(m);
      if (i >= 0 && i + m.length < n.length) {
        return n.substring(i + m.length);
      }
    }
    if (!_looksLikeAbsolutePath(n) && n.isNotEmpty) return n;
    return null;
  }

  /// Remap leftover absolute / stale paths by filename when exact key missed.
  static Future<void> _healOrphanMediaPaths(
    String dbPath,
    Map<String, String> basenameToNew,
  ) async {
    if (basenameToNew.isEmpty) return;
    final appDir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(dbPath);
    try {
      Future<void> healColumn(String table, String column) async {
        final rows = await db.query(table, columns: ['rowid', column]);
        for (final r in rows) {
          final raw = (r[column] ?? '').toString();
          if (raw.isEmpty || raw.length > 600) continue;
          if (raw.startsWith('imported_media/')) continue;
          if (raw.startsWith('data:') || raw.startsWith('http')) continue;

          final exists = _looksLikeAbsolutePath(raw)
              ? File(raw).existsSync()
              : File(_resolveUnderRoot(appDir.path, raw)).existsSync();
          if (exists) continue;

          final base = p.basename(raw.replaceAll(r'\', '/'));
          final neu = basenameToNew[base];
          if (neu == null || neu == raw) continue;
          await db.update(
            table,
            {column: neu},
            where: 'rowid = ?',
            whereArgs: [r['rowid']],
          );
        }
      }

      await healColumn(
        DatabaseHelper.tableAudios,
        DatabaseHelper.columnAudioFilePath,
      );
      await healColumn(
        DatabaseHelper.tableVideos,
        DatabaseHelper.columnVideoFilePath,
      );
      await healColumn(
        DatabaseHelper.tableVideos,
        DatabaseHelper.columnVideoThumbnailPath,
      );
      await healColumn(
        DatabaseHelper.tableImages,
        DatabaseHelper.columnImageData,
      );
    } finally {
      await db.close();
    }
  }

  static const _prefsSkipKeys = <String>{
    'mbtiles_path',
  };

  static bool _skipPrefKey(String key) {
    final k = key.toLowerCase();
    if (_prefsSkipKeys.contains(k)) return true;
    if (k.endsWith('_path') && k.contains('mbtiles')) return true;
    if (k.contains('flutter.')) return true;
    return false;
  }

  static Future<Map<String, dynamic>> _exportSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_skipPrefKey(key)) continue;
      final v = prefs.get(key);
      if (v is String) {
        if (_looksLikeAbsolutePath(v)) continue;
        out[key] = {'t': 'string', 'v': v};
      } else if (v is bool) {
        out[key] = {'t': 'bool', 'v': v};
      } else if (v is int) {
        out[key] = {'t': 'int', 'v': v};
      } else if (v is double) {
        out[key] = {'t': 'double', 'v': v};
      } else if (v is List) {
        out[key] = {
          't': 'stringList',
          'v': v.map((e) => e.toString()).toList(),
        };
      }
    }
    return out;
  }

  static Future<void> _importSharedPreferences(
    Map<String, dynamic> raw,
  ) async {
    if (raw.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final e in raw.entries) {
      if (_skipPrefKey(e.key)) continue;
      final entry = e.value;
      if (entry is! Map) continue;
      final t = entry['t']?.toString();
      final v = entry['v'];
      try {
        switch (t) {
          case 'bool':
            if (v is bool) await prefs.setBool(e.key, v);
            break;
          case 'int':
            if (v is int) {
              await prefs.setInt(e.key, v);
            } else if (v is num) {
              await prefs.setInt(e.key, v.toInt());
            }
            break;
          case 'double':
            if (v is double) {
              await prefs.setDouble(e.key, v);
            } else if (v is num) {
              await prefs.setDouble(e.key, v.toDouble());
            }
            break;
          case 'string':
            if (v is String && !_looksLikeAbsolutePath(v)) {
              await prefs.setString(e.key, v);
            }
            break;
          case 'stringList':
            if (v is List) {
              await prefs.setStringList(
                e.key,
                v.map((x) => x.toString()).toList(),
              );
            }
            break;
        }
      } catch (err) {
        debugPrint('[FullBackupService] prefs restore ${e.key}: $err');
      }
    }
    if (Get.isRegistered<UiController>()) {
      try {
        await Get.find<UiController>().reloadPreferences();
      } catch (e) {
        debugPrint('[FullBackupService] reload UI prefs: $e');
      }
    }
  }
}
