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
  final out = <String>[];
  final base = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < sources.length; i++) {
    final imagePath = sources[i];
    try {
      final sourceFile = File(imagePath);
      if (!sourceFile.existsSync()) continue;
      var ext = p.extension(imagePath).replaceFirst('.', '').toLowerCase();
      if (ext.isEmpty) ext = 'jpg';
      final fileName = 'memory_${base}_$i.$ext';
      final targetPath = p.join(destDirAbsolute, fileName);
      sourceFile.copySync(targetPath);
      out.add('memory_images/$fileName');
    } catch (_) {
      // Skip unreadable paths; mirrors main-isolate save behavior.
    }
  }
  return out;
}
