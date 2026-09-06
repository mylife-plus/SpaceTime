import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spacetime/app/utils/video_thumbnail_cache_manager.dart';

class VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPlayTap;

  /// Prefer a stored DB thumbnail when present (avoids re-decoding video).
  final String? existingThumbnailPath;

  const VideoThumbnailWidget({
    super.key,
    required this.videoPath,
    this.width = 120,
    this.height = 170,
    this.onTap,
    this.onDelete,
    this.onPlayTap,
    this.existingThumbnailPath,
  });

  /// Deletes generated video thumbnails from cache and temp storage.
  static Future<void> clearCachedThumbnails() async {
    await VideoThumbnailCacheManager.clearCache();
    await _VideoThumbnailWidgetState.clearLegacyCachedThumbnails();
  }

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  /// Legacy path cache for quick lookup (keyed by video + target edge).
  static final Map<String, String> _legacyPathCache = <String, String>{};

  /// Clears any legacy cached files
  static Future<void> clearLegacyCachedThumbnails() async {
    final paths = List<String>.from(_legacyPathCache.values);
    _legacyPathCache.clear();
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;

  int get _targetEdge {
    // Always generate a high-res source thumb; UI scales it down. Small
    // widget sizes must not drive a tiny decode (looks soft on retina).
    return VideoThumbnailCacheManager.defaultMaxEdge;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generateThumbnail();
    });
  }

  @override
  void didUpdateWidget(covariant VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath ||
        oldWidget.existingThumbnailPath != widget.existingThumbnailPath ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _generateThumbnail();
    }
  }

  Future<void> _generateThumbnail() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }

      final edge = _targetEdge;
      final legacyKey = '${widget.videoPath}|$edge';
      final legacy = _legacyPathCache[legacyKey];
      if (legacy != null && await File(legacy).exists()) {
        if (!mounted) return;
        setState(() {
          _thumbnailPath = legacy;
          _isLoading = false;
        });
        return;
      }

      final path = await VideoThumbnailCacheManager.getOrGenerateThumbnail(
        videoPath: widget.videoPath,
        existingDbThumbnail: widget.existingThumbnailPath,
        maxEdge: edge,
        quality: VideoThumbnailCacheManager.defaultQuality,
      );

      if (path != null && path.isNotEmpty) {
        _legacyPathCache[legacyKey] = path;
      }

      if (!mounted) return;
      setState(() {
        _thumbnailPath = path;
        _isLoading = false;
        _hasError = path == null || path.isEmpty;
      });
    } catch (e) {
      debugPrint('[VideoThumbnailWidget] error: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isLoading)
              Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[300],
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_hasError)
              Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[300],
                child: const Icon(
                  Icons.videocam_off,
                  color: Colors.grey,
                  size: 48,
                ),
              )
            else if (_thumbnailPath != null)
              isAndroid
                  ? ExtendedImage.file(
                      File(_thumbnailPath!),
                      width: widget.width,
                      height: widget.height,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      clearMemoryCacheWhenDispose: false,
                      gaplessPlayback: true,
                    )
                  : Image.file(
                      File(_thumbnailPath!),
                      width: widget.width,
                      height: widget.height,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    )
            else
              Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[300],
              ),
            if (!_isLoading && !_hasError)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: widget.onPlayTap,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.onDelete != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
