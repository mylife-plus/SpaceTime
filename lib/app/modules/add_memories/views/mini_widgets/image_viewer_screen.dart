import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final List<String> videoPaths;
  final int initialIndex;
  final bool allowHorizontal;

  const ImageViewerScreen({
    super.key,
    required this.images,
    this.videoPaths = const [],
    required this.initialIndex,
    this.allowHorizontal = true,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  late int _currentIndex;
  late AnimationController _overlayController;
  late AnimationController _fadeController;
  bool _showOverlay = true;
  bool _isFullScreen = false;

  final Map<int, ImageProvider> _imageCache = {};
  final Map<int, bool> _imageLoadingStates = {};
  final Map<int, VideoPlayerController> _videoControllers = {};

  int get _totalCount => widget.images.length + widget.videoPaths.length;

  bool _isVideoAtIndex(int index) => index >= widget.images.length;

  String _getVideoPath(int index) => widget.videoPaths[index - widget.images.length];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.allowHorizontal) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _currentIndex = widget.initialIndex;
    _pageController = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: 1.0,
    );

    // Debug logging for image viewer
    debugPrint('=== IMAGE VIEWER INIT DEBUG ===');
    debugPrint('Received ${widget.images.length} images');
    debugPrint('Initial index: ${widget.initialIndex}');

    for (int i = 0; i < widget.images.length; i++) {
      final image = widget.images[i];
      debugPrint('Image $i: ${image.length} characters');
      debugPrint('Image $i is base64: ${_isBase64Image(image)}');
      if (image.length > 50) {
        debugPrint('Image $i preview: ${image.substring(0, 50)}...');
      }
    }
    debugPrint('==============================');

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _overlayController.forward();
    _fadeController.forward();

    // Auto-hide overlay after 3 seconds
    _startAutoHideTimer();

    // Preload images to prevent black screens during swiping
    _preloadImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.allowHorizontal) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    _overlayController.dispose();
    _fadeController.dispose();
    _pageController.dispose();
    for (final vc in _videoControllers.values) {
      vc.dispose();
    }
    super.dispose();
  }

  void _startAutoHideTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showOverlay) {
        _toggleOverlay();
      }
    });
  }

  // Preload images to prevent black screens during swiping
  void _preloadImages() {
    for (int i = 0; i < widget.images.length; i++) {
      final imageData = widget.images[i];

      try {
        ImageProvider imageProvider;

        if (_isFilePath(imageData)) {
          final file = File(imageData);
          if (file.existsSync()) {
            imageProvider = FileImage(file);
          } else {
            continue; // Skip non-existent files
          }
        } else if (_isBase64Image(imageData)) {
          final bytes = base64Decode(imageData);
          imageProvider = MemoryImage(bytes);
        } else {
          continue; // Skip invalid image data
        }

        // Cache the image provider
        _imageCache[i] = imageProvider;
        _imageLoadingStates[i] = false;

        // Preload the image
        precacheImage(imageProvider, context).then((_) {
          if (mounted) {
            setState(() {
              _imageLoadingStates[i] = true;
            });
          }
        }).catchError((error) {
          debugPrint('Error preloading image $i: $error');
        });

      } catch (e) {
        debugPrint('Error setting up preload for image $i: $e');
      }
    }
  }

  // Build image widget that handles both file paths and base64 images
  Widget _buildImageWidget(String imageData) {
    debugPrint('=== BUILDING IMAGE WIDGET ===');
    debugPrint('Image data length: ${imageData.length}');
    debugPrint('Is file path: ${_isFilePath(imageData)}');
    debugPrint('Is base64: ${_isBase64Image(imageData)}');

    // Check if it's a file path (NEW approach)
    if (_isFilePath(imageData)) {
      debugPrint('Loading image from file path: $imageData');
      final file = File(imageData);

      return file.existsSync()
          ? Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Error loading file image in viewer: $error');
                return const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                );
              },
            )
          : const Center(
              child: Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 64,
              ),
            );
    }
    // Handle base64 images (LEGACY approach)
    else if (_isBase64Image(imageData)) {
      try {
        debugPrint('Attempting to decode base64 image...');
        final bytes = base64Decode(imageData);
        debugPrint('Successfully decoded base64 to ${bytes.length} bytes');

        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading base64 image in viewer: $error');
            debugPrint('Stack trace: $stackTrace');
            return const Center(
              child: Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 64,
              ),
            );
          },
        );
      } catch (e) {
        debugPrint('Error decoding base64 image in viewer: $e');
        return const Center(
          child: Icon(
            Icons.broken_image,
            color: Colors.white54,
            size: 64,
          ),
        );
      }
    } else {
      // Asset image
      return Image.asset(
        imageData,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading asset image in viewer: $error');
          return const Center(
            child: Icon(
              Icons.broken_image,
              color: Colors.white54,
              size: 64,
            ),
          );
        },
      );
    }
  }

  // Check if the image data is a file path
  bool _isFilePath(String imageData) {
    return imageData.startsWith('/') ||
           imageData.contains('\\') ||
           imageData.contains('.jpg') ||
           imageData.contains('.jpeg') ||
           imageData.contains('.png') ||
           imageData.contains('.gif') ||
           imageData.contains('.webp');
  }

  // Check if the image data is base64 encoded
  bool _isBase64Image(String imageData) {
    if (imageData.length < 100) return false;
    if (_isFilePath(imageData)) return false; // File paths are not base64

    try {
      final testData = imageData.length > 100 ? imageData.substring(0, 100) : imageData;
      base64Decode(testData);
      return true;
    } catch (e) {
      return false;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  void _toggleVideoPlayPause(int index) {
    final vc = _videoControllers[index];
    if (vc == null || !vc.value.isInitialized) return;
    setState(() {
      vc.value.isPlaying ? vc.pause() : vc.play();
    });
    if (vc.value.isPlaying) {
      _startAutoHideTimer();
    }
  }

  Widget _buildVideoPlayer(String videoPath, int index) {
    final uiController = Get.find<UiController>();
    if (!_videoControllers.containsKey(index)) {
      final vc = VideoPlayerController.file(File(videoPath));
      _videoControllers[index] = vc;
      vc.initialize().then((_) {
        if (mounted) {
          vc.addListener(() {
            if (mounted) setState(() {});
          });
          setState(() {});
        }
      });
    }
    final vc = _videoControllers[index]!;
    if (!vc.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final accentColor = uiController.darkMode.value
        ? (uiController.mainColor.value == 'blue'
            ? uiController.currentMainColor
            : uiController.primaryColorDark) ?? Colors.blue
        : (uiController.mainColor.value == 'blue'
            ? Colors.blue
            : uiController.primaryColor) ?? Colors.blue;
    return GestureDetector(
      onTap: () {
        setState(() { _showOverlay = !_showOverlay; });
        if (_showOverlay) {
          _overlayController.forward();
          _startAutoHideTimer();
        } else {
          _overlayController.reverse();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: vc.value.size.width,
                height: vc.value.size.height,
                child: VideoPlayer(vc),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _showOverlay ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              icon: Icon(
                vc.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white,
                size: 64,
              ),
              onPressed: () => _toggleVideoPlayPause(index),
            ),
          ),
          if (_showOverlay)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoProgressIndicator(
                        vc,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: accentColor,
                          bufferedColor: Colors.white.withValues(alpha: 0.3),
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatDuration(vc.value.position),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(vc.value.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });

    if (_showOverlay) {
      _overlayController.forward();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      _overlayController.reverse();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
  }



  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (index) {
                for (final vc in _videoControllers.values) {
                  vc.pause();
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: _totalCount,
              itemBuilder: (context, index) {
                if (_isVideoAtIndex(index)) {
                  return _buildVideoPlayer(_getVideoPath(index), index);
                }
                return GestureDetector(
                  onTap: _toggleOverlay,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: _buildImageWidget(widget.images[index]),
                    ),
                  ),
                );
              },
            ),

            // Top overlay (AppBar)
            AnimatedBuilder(
              animation: _overlayController,
              builder: (context, child) {
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Transform.translate(
                    offset: Offset(0, -100 * (1 - _overlayController.value)),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: AppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          leading: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              if (widget.allowHorizontal) {
                                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                SystemChrome.setPreferredOrientations([
                                  DeviceOrientation.portraitUp,
                                  DeviceOrientation.portraitDown,
                                ]);
                              }
                              Navigator.of(context).pop();
                            },
                          ),
                          title: Center(
                            child: Text(
                              '${_currentIndex + 1} of $_totalCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          actions: [
                            if (widget.allowHorizontal)
                              IconButton(
                                icon: Icon(
                                  _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isFullScreen = !_isFullScreen;
                                  });
                                  if (_isFullScreen) {
                                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                                    SystemChrome.setPreferredOrientations([
                                      DeviceOrientation.landscapeLeft,
                                      DeviceOrientation.landscapeRight,
                                    ]);
                                  } else {
                                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                    SystemChrome.setPreferredOrientations([
                                      DeviceOrientation.portraitUp,
                                      DeviceOrientation.portraitDown,
                                    ]);
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Bottom overlay (Dots indicator)
            if (_totalCount > 1)
              AnimatedBuilder(
                animation: _overlayController,
                builder: (context, child) {
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Transform.translate(
                      offset: Offset(0, 100 * (1 - _overlayController.value)),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _totalCount,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: _currentIndex == index ? 24 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color:
                                        _currentIndex == index
                                            ? controller.darkMode.value
                                                ? controller.mainColor.value ==
                                                        'blue'
                                                    ? controller
                                                        .currentMainColor
                                                    : controller
                                                        .primaryColorDark
                                                : controller.mainColor.value ==
                                                    'blue'
                                                ? Colors.blue
                                                : controller.primaryColor
                                            : Colors.white.withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
      ),
    );
  }
}
