import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

/// Display-optimized JPEG for app storage (GPS import). Gallery originals untouched.
class MemoryImageDisplayOptimize {
  MemoryImageDisplayOptimize._();

  /// Longest edge; phone fullscreen does not need multi‑MP masters.
  static const int maxEdgePx = 2048;
  static const int jpegQuality = 85;

  /// Writes a resized JPEG to [destPath]. Returns false on failure (caller may copy).
  static Future<bool> writeOptimizedJpeg({
    required String sourcePath,
    required String destPath,
  }) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return false;

      final destDir = Directory(p.dirname(destPath));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      if (await File(destPath).exists()) {
        await File(destPath).delete();
      }

      final out = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        destPath,
        minWidth: maxEdgePx,
        minHeight: maxEdgePx,
        quality: jpegQuality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (out == null) return false;
      final f = File(out.path);
      if (!await f.exists() || await f.length() == 0) return false;
      // Ensure final path if plugin wrote a sibling name.
      if (p.normalize(out.path) != p.normalize(destPath)) {
        await f.copy(destPath);
        if (p.normalize(out.path) != p.normalize(destPath)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      return await File(destPath).exists();
    } catch (e, st) {
      debugPrint('[MemoryImageDisplayOptimize] failed: $e\n$st');
      return false;
    }
  }
}
