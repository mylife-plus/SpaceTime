import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Disk + in-memory cache manager for generated video thumbnails using [CacheManager].
/// Handles LRU cache eviction, max objects count, and serialized native frame extraction
/// to prevent hardware video codec ANR on Android.
class VideoThumbnailCacheManager {
  /// v3: aspect-preserving generation (v2 forced square maxW=maxH on Android API 27+).
  static const String key = 'spacetime_video_thumbnails_v3';

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

  /// Default max edge (px) for list / card / editor previews.
  static const int defaultMaxEdge = 1080;

  /// JPEG quality for previews (plugin uses this in Bitmap.compress).
  static const int defaultQuality = 90;

  /// Skip the first black/empty keyframe common on Android camera recordings.
  static const int defaultTimeMs = 500;

  /// Retrieves cached thumbnail or generates a new one and stores it in the cache.
  ///
  /// On Android we only pass [maxHeight] (width=0) so MediaMetadataRetriever
  /// preserves aspect ratio instead of squashing into a square via
  /// getScaledFrameAtTime(dstW, dstH) when both dimensions are set equal.
  static Future<String?> getOrGenerateThumbnail({
    required String videoPath,
    String? existingDbThumbnail,
    int maxEdge = defaultMaxEdge,
    int quality = defaultQuality,
    int timeMs = defaultTimeMs,
  }) async {
    final edge = maxEdge.clamp(320, 1920);
    final q = quality.clamp(60, 95);
    final t = timeMs < 0 ? 0 : timeMs;
    final cacheKey = '$videoPath|e$edge|q$q|t$t|aspect';

    if (existingDbThumbnail != null && existingDbThumbnail.isNotEmpty) {
      final dbFile = File(existingDbThumbnail);
      if (await dbFile.exists()) {
        final len = await dbFile.length();
        // Tiny files are usually old micro-thumbs — regenerate.
        if (len >= 12 * 1024) {
          return existingDbThumbnail;
        }
        debugPrint(
          '[VideoThumbnailCacheManager] Ignoring tiny DB thumb '
          '($len bytes): $existingDbThumbnail',
        );
      }
    }

    try {
      final fileInfo = await instance.getFileFromCache(cacheKey);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file.path;
      }
    } catch (e) {
      debugPrint('[VideoThumbnailCacheManager] Cache lookup error: $e');
    }

    Future<Uint8List?> generateAt(int frameMs) {
      return VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxHeight: edge,
        maxWidth: 0, // preserve aspect on Android API 27+
        timeMs: frameMs,
        quality: q,
      );
    }

    try {
      var bytes = await _runSerialized(() => generateAt(t));

      if ((bytes == null || bytes.length < 8 * 1024) && t < 1500) {
        bytes = await _runSerialized(() => generateAt(1500));
      }

      if (bytes != null && bytes.isNotEmpty) {
        final cachedFile = await instance.putFile(
          cacheKey,
          bytes,
          fileExtension: 'jpg',
        );
        return cachedFile.path;
      }
    } catch (e) {
      debugPrint('[VideoThumbnailCacheManager] Thumbnail generation error: $e');
      try {
        final tempDir = await getTemporaryDirectory();
        final thumbFile = await _runSerialized(
          () => VideoThumbnail.thumbnailFile(
            video: videoPath,
            thumbnailPath: tempDir.path,
            imageFormat: ImageFormat.JPEG,
            maxHeight: edge,
            maxWidth: 0,
            timeMs: t,
            quality: q,
          ),
        );
        if (thumbFile != null &&
            thumbFile.isNotEmpty &&
            File(thumbFile).existsSync()) {
          final bytes = await File(thumbFile).readAsBytes();
          final cached = await instance.putFile(
            cacheKey,
            bytes,
            fileExtension: 'jpg',
          );
          return cached.path;
        }
      } catch (fallbackError) {
        debugPrint(
          '[VideoThumbnailCacheManager] Fallback generation error: $fallbackError',
        );
      }
    }

    return null;
  }

  /// Generate a durable thumbnail file next to a staged/saved video (for DB path).
  static Future<String?> generatePersistentThumbnail({
    required String videoAbsolutePath,
    int maxEdge = defaultMaxEdge,
    int quality = defaultQuality,
  }) async {
    final cached = await getOrGenerateThumbnail(
      videoPath: videoAbsolutePath,
      maxEdge: maxEdge,
      quality: quality,
    );
    if (cached == null || cached.isEmpty) return null;

    try {
      final videoFile = File(videoAbsolutePath);
      final dir = videoFile.parent;
      final base = videoFile.uri.pathSegments.isNotEmpty
          ? videoFile.uri.pathSegments.last
          : 'video';
      final nameNoExt = base.contains('.')
          ? base.substring(0, base.lastIndexOf('.'))
          : base;
      final dest = File('${dir.path}/${nameNoExt}_thumb.jpg');
      await File(cached).copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint(
        '[VideoThumbnailCacheManager] persistent thumb copy failed: $e',
      );
      return cached;
    }
  }

  /// Clears all video thumbnails from cache.
  static Future<void> clearCache() async {
    try {
      await instance.emptyCache();
      for (final oldKey in const [
        'spacetime_video_thumbnails',
        'spacetime_video_thumbnails_v2',
      ]) {
        try {
          await CacheManager(
            Config(
              oldKey,
              stalePeriod: const Duration(days: 1),
              maxNrOfCacheObjects: 1,
            ),
          ).emptyCache();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[VideoThumbnailCacheManager] clearCache error: $e');
    }
  }
}
