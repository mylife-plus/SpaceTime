import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

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

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  /// Path → generated thumb file (keeps list scroll from re-decoding the same video).
  static final Map<String, String> _pathCache = <String, String>{};

  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;
  bool _ownsGeneratedFile = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  @override
  void didUpdateWidget(covariant VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath ||
        oldWidget.existingThumbnailPath != widget.existingThumbnailPath) {
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

      final existing = widget.existingThumbnailPath;
      if (existing != null && existing.isNotEmpty) {
        final f = File(existing);
        if (await f.exists()) {
          if (!mounted) return;
          setState(() {
            _thumbnailPath = existing;
            _ownsGeneratedFile = false;
            _isLoading = false;
          });
          return;
        }
      }

      final cached = _pathCache[widget.videoPath];
      if (cached != null && await File(cached).exists()) {
        if (!mounted) return;
        setState(() {
          _thumbnailPath = cached;
          _ownsGeneratedFile = false;
          _isLoading = false;
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      // Keep list thumbs small — full 1080 PNG was lagging Android scroll.
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 320,
        quality: 55,
      );

      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        _pathCache[widget.videoPath] = thumbnailPath;
      }

      if (!mounted) return;
      setState(() {
        _thumbnailPath = thumbnailPath;
        _ownsGeneratedFile = false; // kept in [_pathCache]
        _isLoading = false;
        _hasError = thumbnailPath == null || thumbnailPath.isEmpty;
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
              Image.file(
                File(_thumbnailPath!),
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
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
    // Cached thumbs are shared across list rebuilds — do not delete.
    if (_ownsGeneratedFile && _thumbnailPath != null) {
      try {
        final file = File(_thumbnailPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
    super.dispose();
  }
}
