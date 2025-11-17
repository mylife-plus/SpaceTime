import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'memory_db.dart';

/// Helper class to migrate absolute paths to relative paths in the database
class PathMigrationHelper {
  static final PathMigrationHelper instance = PathMigrationHelper._init();
  PathMigrationHelper._init();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Migrate all absolute paths to relative paths in the database
  Future<void> migrateAllPathsToRelative() async {
    try {
      debugPrint('🔄 Starting path migration to relative paths...');
      
      final appDir = await getApplicationDocumentsDirectory();
      final appDirPath = appDir.path;
      
      debugPrint('🔄 Current app directory: $appDirPath');

      // Migrate images
      await _migrateImagePaths(appDirPath);
      
      // Migrate videos
      await _migrateVideoPaths(appDirPath);
      
      // Migrate audios
      await _migrateAudioPaths(appDirPath);
      
      debugPrint('✅ Path migration completed successfully');
    } catch (e) {
      debugPrint('❌ Error during path migration: $e');
    }
  }

  /// Migrate image paths from absolute to relative
  Future<void> _migrateImagePaths(String currentAppDir) async {
    try {
      final db = await _db.database;
      
      // Get all images
      final images = await db.query(DatabaseHelper.tableImages);
      debugPrint('🔄 Migrating ${images.length} image paths...');
      
      int migratedCount = 0;
      for (final image in images) {
        final imageId = image[DatabaseHelper.columnImageId] as int;
        final imageData = image[DatabaseHelper.columnImageData] as String;
        
        // Check if it's an absolute path (not base64)
        if (imageData.startsWith('/')) {
          // Extract relative path
          String relativePath = _extractRelativePath(imageData, currentAppDir);
          
          if (relativePath != imageData) {
            // Update the database
            await db.update(
              DatabaseHelper.tableImages,
              {DatabaseHelper.columnImageData: relativePath},
              where: '${DatabaseHelper.columnImageId} = ?',
              whereArgs: [imageId],
            );
            migratedCount++;
            debugPrint('🔄 Migrated image $imageId: $imageData -> $relativePath');
          }
        }
      }
      
      debugPrint('✅ Migrated $migratedCount image paths');
    } catch (e) {
      debugPrint('❌ Error migrating image paths: $e');
    }
  }

  /// Migrate video paths from absolute to relative
  Future<void> _migrateVideoPaths(String currentAppDir) async {
    try {
      final db = await _db.database;
      
      // Get all videos
      final videos = await db.query(DatabaseHelper.tableVideos);
      debugPrint('🔄 Migrating ${videos.length} video paths...');
      
      int migratedCount = 0;
      for (final video in videos) {
        final videoId = video[DatabaseHelper.columnVideoId] as int;
        final videoPath = video[DatabaseHelper.columnVideoFilePath] as String;
        
        // Check if it's an absolute path
        if (videoPath.startsWith('/')) {
          // Extract relative path
          String relativePath = _extractRelativePath(videoPath, currentAppDir);
          
          if (relativePath != videoPath) {
            // Update the database
            await db.update(
              DatabaseHelper.tableVideos,
              {DatabaseHelper.columnVideoFilePath: relativePath},
              where: '${DatabaseHelper.columnVideoId} = ?',
              whereArgs: [videoId],
            );
            migratedCount++;
            debugPrint('🔄 Migrated video $videoId: $videoPath -> $relativePath');
          }
        }
      }
      
      debugPrint('✅ Migrated $migratedCount video paths');
    } catch (e) {
      debugPrint('❌ Error migrating video paths: $e');
    }
  }

  /// Migrate audio paths from absolute to relative
  Future<void> _migrateAudioPaths(String currentAppDir) async {
    try {
      final db = await _db.database;
      
      // Get all audios
      final audios = await db.query(DatabaseHelper.tableAudios);
      debugPrint('🔄 Migrating ${audios.length} audio paths...');
      
      int migratedCount = 0;
      for (final audio in audios) {
        final audioId = audio[DatabaseHelper.columnAudioId] as int;
        final audioPath = audio[DatabaseHelper.columnAudioFilePath] as String;
        
        // Check if it's an absolute path
        if (audioPath.startsWith('/')) {
          // Extract relative path
          String relativePath = _extractRelativePath(audioPath, currentAppDir);
          
          if (relativePath != audioPath) {
            // Update the database
            await db.update(
              DatabaseHelper.tableAudios,
              {DatabaseHelper.columnAudioFilePath: relativePath},
              where: '${DatabaseHelper.columnAudioId} = ?',
              whereArgs: [audioId],
            );
            migratedCount++;
            debugPrint('🔄 Migrated audio $audioId: $audioPath -> $relativePath');
          }
        }
      }
      
      debugPrint('✅ Migrated $migratedCount audio paths');
    } catch (e) {
      debugPrint('❌ Error migrating audio paths: $e');
    }
  }

  /// Extract relative path from absolute path
  String _extractRelativePath(String absolutePath, String currentAppDir) {
    // Try to extract the relative part from any app directory path
    // Pattern: /var/mobile/.../Documents/memory_images/file.jpg -> memory_images/file.jpg
    
    if (absolutePath.contains('/Documents/')) {
      final parts = absolutePath.split('/Documents/');
      if (parts.length > 1) {
        return parts[1]; // Return everything after /Documents/
      }
    }
    
    // If already relative, return as is
    return absolutePath;
  }
}

