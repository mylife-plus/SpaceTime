import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

class VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPlayTap;

  const VideoThumbnailWidget({
    super.key,
    required this.videoPath,
    this.width = 120,
    this.height = 170,
    this.onTap,
    this.onDelete,
    this.onPlayTap,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🎬 VideoThumbnailWidget created for: ${widget.videoPath}');
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      debugPrint('🎬 Generating thumbnail for: ${widget.videoPath}');
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.PNG,
        maxHeight: 1080,
        quality: 100,
      );

      debugPrint('🎬 Thumbnail generated: $thumbnailPath');
      if (mounted) {
        setState(() {
          _thumbnailPath = thumbnailPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error generating video thumbnail: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
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
            // Thumbnail or placeholder
            _isLoading
                ? Container(
                    width: widget.width,
                    height: widget.height,
                    color: Colors.grey[300],
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _hasError
                    ? Container(
                        width: widget.width,
                        height: widget.height,
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.videocam_off,
                          color: Colors.grey,
                          size: 48,
                        ),
                      )
                    : _thumbnailPath != null
                        ? Image.file(
                            File(_thumbnailPath!),
                            width: widget.width,
                            height: widget.height,
                            fit: BoxFit.cover,
                          )
                        : Container(
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
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.zoom_in,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Delete button
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
    // Clean up thumbnail file if it exists
    if (_thumbnailPath != null) {
      try {
        final file = File(_thumbnailPath!);
        if (file.existsSync()) {
          file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting thumbnail: $e');
      }
    }
    super.dispose();
  }
}

