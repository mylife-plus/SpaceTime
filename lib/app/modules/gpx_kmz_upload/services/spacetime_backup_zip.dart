import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Detects SpaceTime full-backup zips (`spacetime_backup_*.zip`) so GPX/KMZ
/// upload can reject them before opening a track preview.
class SpaceTimeBackupZip {
  SpaceTimeBackupZip._();

  static String normalizeZipInternalPath(String name) {
    var n = name.replaceAll(r'\', '/').trim();
    while (n.startsWith('./')) {
      n = n.substring(2);
    }
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    return n;
  }

  static bool isBackupFileName(String name) {
    final base = name.replaceAll(r'\', '/').split('/').last.toLowerCase();
    return base.startsWith('spacetime_backup_') && base.endsWith('.zip');
  }

  static bool archiveIsBackup(Archive archive) {
    var hasMeta = false;
    var hasDb = false;
    ArchiveFile? metaFile;
    for (final f in archive) {
      if (!f.isFile) continue;
      final n = normalizeZipInternalPath(f.name);
      if (n == 'meta.json') {
        hasMeta = true;
        metaFile = f;
      }
      if (n == 'db/memories.db' || n == 'memories.db') {
        hasDb = true;
      }
    }
    if (!hasMeta || !hasDb) return false;
    if (metaFile != null) {
      try {
        final raw = utf8.decode(metaFile.content as List<int>, allowMalformed: true);
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.containsKey('format_version')) {
          return true;
        }
      } catch (_) {}
    }
    return hasMeta && hasDb;
  }

  static Future<bool> isBackupZipFile(String filePath) async {
    if (isBackupFileName(filePath)) return true;
    if (!filePath.toLowerCase().endsWith('.zip')) return false;
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      return archiveIsBackup(archive);
    } catch (_) {
      return false;
    }
  }
}
