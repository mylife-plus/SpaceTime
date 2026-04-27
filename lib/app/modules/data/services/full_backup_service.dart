import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spacetime/app/services/memory_db.dart';

class FullBackupResult {
  const FullBackupResult({
    required this.ok,
    required this.message,
    this.filePath,
  });

  final bool ok;
  final String message;
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
          message: 'Database file not found',
        );
      }

      // Flush sqlite data before taking file snapshot.
      await DatabaseHelper.instance.resetDatabaseConnection();

      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final backupName = 'spacetime_backup_$stamp.zip';
      final tmpDir = await getTemporaryDirectory();
      final outZipPath = p.join(tmpDir.path, backupName);

      final archive = Archive();
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('db/$_dbFileName', dbBytes.length, dbBytes));

      final mediaPaths = await _collectMediaPathsFromDb(dbPath);
      final mediaManifest = <String, String>{};
      var index = 0;
      for (final src in mediaPaths) {
        final f = File(src);
        if (!await f.exists()) continue;
        final ext = p.extension(src);
        final rel = 'media/$index$ext';
        index++;
        final bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
        mediaManifest[src] = rel;
      }

      final meta = <String, dynamic>{
        'format_version': 1,
        'created_at': now.toIso8601String(),
        'media_manifest': mediaManifest,
      };
      final metaBytes = utf8.encode(jsonEncode(meta));
      archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        return const FullBackupResult(ok: false, message: 'Failed to encode zip');
      }
      await File(outZipPath).writeAsBytes(zipData, flush: true);

      String? pickedPath;
      try {
        pickedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Backup',
          fileName: backupName,
          type: FileType.custom,
          allowedExtensions: const ['zip'],
          bytes: Uint8List.fromList(zipData),
        );
      } catch (_) {
        pickedPath = null;
      }

      if (pickedPath != null && pickedPath.isNotEmpty) {
        if (p.normalize(pickedPath) != p.normalize(outZipPath)) {
          await File(outZipPath).copy(pickedPath);
        }
        return FullBackupResult(
          ok: true,
          message: 'Backup exported successfully',
          filePath: pickedPath,
        );
      }

      final fallbackDir = Directory(p.join(appDir.path, 'backups'));
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      final fallbackPath = p.join(fallbackDir.path, backupName);
      await File(outZipPath).copy(fallbackPath);
      return FullBackupResult(
        ok: true,
        message: 'Backup exported to app documents',
        filePath: fallbackPath,
      );
    } catch (e, st) {
      debugPrint('[FullBackupService] export failed: $e\n$st');
      return FullBackupResult(ok: false, message: 'Export failed: $e');
    }
  }

  static Future<FullBackupResult> importFullBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) {
        return const FullBackupResult(ok: false, message: 'No backup file selected');
      }
      final zipPath = picked.files.first.path;
      if (zipPath == null || zipPath.isEmpty) {
        return const FullBackupResult(ok: false, message: 'Selected file path missing');
      }

      final zipBytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);

      ArchiveFile? dbEntry;
      ArchiveFile? metaEntry;
      final mediaEntries = <ArchiveFile>[];
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final n = entry.name;
        if (n == 'db/$_dbFileName') dbEntry = entry;
        if (n == 'meta.json') metaEntry = entry;
        if (n.startsWith('media/')) mediaEntries.add(entry);
      }

      if (dbEntry == null) {
        return const FullBackupResult(ok: false, message: 'Invalid backup: DB missing');
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

      final relToAbs = <String, String>{};
      for (final m in mediaEntries) {
        final rel = m.name;
        final outPath = p.join(importMediaRoot.path, rel);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(m.content as List<int>, flush: true);
        relToAbs[rel] = outPath;
      }

      await DatabaseHelper.instance.resetDatabaseConnection();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await dbFile.writeAsBytes(dbEntry.content as List<int>, flush: true);

      final oldToNewPath = <String, String>{};
      for (final e in manifest.entries) {
        final rel = e.value;
        final abs = relToAbs[rel];
        if (abs != null) oldToNewPath[e.key] = abs;
      }

      await _remapMediaPaths(dbPath, oldToNewPath);
      await DatabaseHelper.instance.resetDatabaseConnection();
      await DatabaseHelper.instance.database;

      return FullBackupResult(
        ok: true,
        message: 'Backup imported successfully',
        filePath: zipPath,
      );
    } catch (e, st) {
      debugPrint('[FullBackupService] import failed: $e\n$st');
      return FullBackupResult(ok: false, message: 'Import failed: $e');
    }
  }

  static Future<Set<String>> _collectMediaPathsFromDb(String dbPath) async {
    final db = await openDatabase(dbPath, readOnly: true);
    try {
      final out = <String>{};
      final audios = await db.query(
        DatabaseHelper.tableAudios,
        columns: [DatabaseHelper.columnAudioFilePath],
      );
      for (final r in audios) {
        final pth = (r[DatabaseHelper.columnAudioFilePath] ?? '').toString();
        if (_looksLikeAbsolutePath(pth)) out.add(pth);
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
        if (_looksLikeAbsolutePath(v)) out.add(v);
        if (_looksLikeAbsolutePath(t)) out.add(t);
      }
      final images = await db.query(
        DatabaseHelper.tableImages,
        columns: [DatabaseHelper.columnImageData],
      );
      for (final r in images) {
        final img = (r[DatabaseHelper.columnImageData] ?? '').toString();
        if (_looksLikeAbsolutePath(img)) out.add(img);
      }
      return out;
    } finally {
      await db.close();
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

  static bool _looksLikeAbsolutePath(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('/')) return true;
    if (value.contains(r':\')) return true;
    return false;
  }
}
