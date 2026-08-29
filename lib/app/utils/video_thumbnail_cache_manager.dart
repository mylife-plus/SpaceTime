import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Disk + in-memory cache manager for generated video thumbnails using [CacheManager].
/// Handles LRU cache eviction, max objects count, and serialized native frame extraction
/// to prevent hardware video codec ANR on Android.
class VideoThumbnailCacheManager {
  static const String key = 'spacetime_video_thumbnails';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 300,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );

  /// Serializes native thumbnail generation (VideoThumbnail) to prevent
  /// concurrent hardware video codec contention and ANRs on Android devices.
  static Future<void> _generationQueue = Future<void>.value();

  static Future<T> _runSerialized<T>(Future<T> Function() task) {
    final result = _generationQueue.then((_) => task());
    _generationQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Retrieves cached thumbnail or generates a new one and stores it in the cache.
  static Future<String?> getOrGenerateThumbnail({
    required String videoPath,
    String? existingDbThumbnail,
    bool isLowQuality = true,
  }) async {
    // 1. If DB already provided a stored thumbnail path that exists, use it directly
    if (existingDbThumbnail != null && existingDbThumbnail.isNotEmpty) {
      final dbFile = File(existingDbThumbnail);
      if (await dbFile.exists()) {
        return existingDbThumbnail;
      }
    }

    // 2. Check if already present in flutter_cache_manager
    try {
      final fileInfo = await instance.getFileFromCache(videoPath);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file.path;
      }
    } catch (e) {
      debugPrint('[VideoThumbnailCacheManager] Cache lookup error: $e');
    }

    // 3. Generate thumbnail via VideoThumbnail on a serialized worker queue
    try {
      final isAndroid = !kIsWeb && Platform.isAndroid;
      final quality = isAndroid
          ? (isLowQuality ? 10 : 25)
          : 50;
      final maxHeight = isAndroid
          ? (isLowQuality ? 120 : 200)
          : 300;

      final bytes = await _runSerialized(
        () => VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxHeight: maxHeight,
          quality: quality,
        ),
      );

      if (bytes != null && bytes.isNotEmpty) {
        final cachedFile = await instance.putFile(
          videoPath,
          bytes,
          fileExtension: 'jpg',
        );
        return cachedFile.path;
      }
    } catch (e) {
      debugPrint('[VideoThumbnailCacheManager] Thumbnail generation error: $e');
      // Fallback: try generating to temporary file if memory buffer fails
      try {
        final tempDir = await getTemporaryDirectory();
        final thumbFile = await _runSerialized(
          () => VideoThumbnail.thumbnailFile(
            video: videoPath,
            thumbnailPath: tempDir.path,
            imageFormat: ImageFormat.JPEG,
            maxHeight: 120,
            quality: 10,
          ),
        );
        if (thumbFile != null && thumbFile.isNotEmpty && File(thumbFile).existsSync()) {
          final bytes = await File(thumbFile).readAsBytes();
          final cached = await instance.putFile(
            videoPath,
            bytes,
            fileExtension: 'jpg',
          );
          return cached.path;
        }
      } catch (fallbackError) {
        debugPrint('[VideoThumbnailCacheManager] Fallback generation error: $fallbackError');
      }
    }

    return null;
  }

  /// Clears all video thumbnails from cache.
  static Future<void> clearCache() async {
    try {
      await instance.emptyCache();
    } catch (e) {
      debugPrint('[VideoThumbnailCacheManager] clearCache error: $e');
    }
  }
}
