import 'dart:io';

import 'package:path/path.dart' as p;

/// Heavy file I/O for gallery imports — run via [compute] off the UI isolate.
@pragma('vm:entry-point')
List<String> memoryImagesCopyIsolateWork(Map<String, dynamic> message) {
  final destDirAbsolute = message['dest'] as String;
  final sources = (message['sources'] as List<dynamic>).cast<String>();
  final dir = Directory(destDirAbsolute);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  // Keep 1:1 with [sources] so bulk import can slice by cluster index.
  // Failed/missing files become '' (filtered by callers).
  final out = List<String>.filled(sources.length, '');
  final base = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < sources.length; i++) {
    var imagePath = sources[i];
    if (imagePath.contains('%')) {
      try {
        imagePath = Uri.decodeFull(imagePath);
      } catch (_) {}
    }
    try {
      final sourceFile = File(imagePath);
      if (!sourceFile.existsSync()) continue;
      var ext = p.extension(imagePath).replaceFirst('.', '').toLowerCase();
      if (ext.isEmpty) ext = 'jpg';
      final fileName = 'memory_${base}_$i.$ext';
      final targetPath = p.join(destDirAbsolute, fileName);
      sourceFile.copySync(targetPath);
      out[i] = 'memory_images/$fileName';
    } catch (_) {
      // Leave '' — mirrors main-isolate skip behavior.
    }
  }
  return out;
}
