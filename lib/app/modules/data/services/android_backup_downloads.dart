import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only: write a zip into the public Downloads collection so it appears
/// in Files / Download. iOS must not call this (share sheet handles save there).
class AndroidBackupDownloads {
  AndroidBackupDownloads._();

  static const MethodChannel _channel =
      MethodChannel('com.spacetime/backup_downloads');

  /// Returns true when the file is visible under Downloads.
  static Future<bool> saveZipToDownloads({
    required String sourcePath,
    required String fileName,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'saveToDownloads',
        <String, dynamic>{
          'sourcePath': sourcePath,
          'fileName': fileName,
        },
      );
      final result = raw is Map ? Map<Object?, Object?>.from(raw) : null;
      final ok = result != null && (result['ok'] == true);
      debugPrint(
        '[AndroidBackupDownloads] saveToDownloads ok=$ok '
        'path=${result?['relativePath']}',
      );
      return ok;
    } on MissingPluginException catch (e, st) {
      debugPrint(
        '[AndroidBackupDownloads] MissingPluginException — full rebuild '
        'required for MainActivity channel: $e\n$st',
      );
      return false;
    } catch (e, st) {
      debugPrint('[AndroidBackupDownloads] saveToDownloads failed: $e\n$st');
      return false;
    }
  }
}
