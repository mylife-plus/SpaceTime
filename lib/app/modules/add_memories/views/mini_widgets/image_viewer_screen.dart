import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/utils/memory_media_image_cache.dart';
import 'package:spacetime/app/widgets/keep_alive_page.dart';
import 'package:spacetime/app/widgets/tappable_back_button.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final List<String> videoPaths;
  final int initialIndex;
  final bool allowHorizontal;
  final List<Map<String, dynamic>>? orderedMedia;

  const ImageViewerScreen({
    super.key,
    required this.images,
    this.videoPaths = const [],
    required this.initialIndex,
    this.allowHorizontal = true,
    this.orderedMedia,
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

  final Map<int, VideoPlayerController> _videoControllers = {};

  bool get _hasOrderedMedia => widget.orderedMedia != null && widget.orderedMedia!.isNotEmpty;

  int get _totalCount => _hasOrderedMedia
      ? widget.orderedMedia!.length
      : widget.images.length + widget.videoPaths.length;

  bool _isVideoAtIndex(int index) {
    if (_hasOrderedMedia) {
      return widget.orderedMedia![index]['type'] == 'video';
    }
    return index >= widget.images.length;
  }

  String _getVideoPath(int index) {
    if (_hasOrderedMedia) {
      return widget.orderedMedia![index]['path'] as String;
    }
    return widget.videoPaths[index - widget.images.length];
  }

  String _getImageData(int index) {
    if (_hasOrderedMedia) {
      return widget.orderedMedia![index]['path'] as String;
    }
    return widget.images[index];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyPreferredOrientations();
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

    unawaited(MemoryMediaImageProviderCache.instance.ensureDocumentsRoot());

    // Preload images to prevent black screens during swiping. Deferred to after
    // the first frame: _preloadImages() reads MediaQuery.of(context), which must
    // not be depended on during initState() (throws "dependOnInheritedWidget…
    // called before initState completed").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadImages();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      // Re-apply orientations so OS rotation-lock changes are respected.
      _applyPreferredOrientations();
    }
    setState(() {});
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // Rotation-lock toggle and/or device rotation can trigger metrics changes.
    // Re-applying preferred orientations helps iOS update the actual rotation.
    _applyPreferredOrientations();
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

  void _applyPreferredOrientations() {
    if (!widget.allowHorizontal) return;
    // If fullscreen is on, lock to landscape. Otherwise allow both so the
    // OS rotation-lock toggle can be respected immediately.
    SystemChrome.setPreferredOrientations(
      _isFullScreen
          ? [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  void _startAutoHideTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showOverlay) {
        _toggleOverlay();
      }
    });
  }

  void _preloadImages() {
    for (int i = 0; i < _totalCount; i++) {
      _preloadImageAt(i);
    }
  }

  void _preloadImageAt(int index) {
    if (index < 0 || index >= _totalCount || _isVideoAtIndex(index)) return;
    final imageData = _getImageData(index);
    final decodeW = MediaQuery.sizeOf(context).shortestSide > 0
        ? MemoryMediaImageProviderCache.decodeWidthForLayout(
            context,
            layoutHeight: MediaQuery.sizeOf(context).height,
            maxDecode: 2048,
          )
        : 2048;
    unawaited(
      MemoryMediaImageProviderCache.instance.precache(
        context,
        imageData,
        cacheWidth: decodeW,
      ),
    );
  }

  Widget _buildImageWidget(String imageData, int index) {
    final decodeW = MemoryMediaImageProviderCache.decodeWidthForLayout(
      context,
      layoutHeight: MediaQuery.sizeOf(context).height,
      maxDecode: 2048,
    );
    return MemoryMediaImageProviderCache.instance.buildImage(
      context: context,
      imageData: imageData,
      fit: BoxFit.contain,
      cacheWidth: decodeW,
      placeholderColor: Colors.black,
      errorChild: const Center(
        child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
      ),
    );
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
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
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
            // Keep play button visible whenever video is paused.
            opacity: (_showOverlay || !vc.value.isPlaying) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              icon: Icon(
                vc.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
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
              child: SafeArea(bottom: false,
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
              clipBehavior: Clip.hardEdge,
              onPageChanged: (index) {
                for (final vc in _videoControllers.values) {
                  vc.pause();
                }
                _preloadImageAt(index - 1);
                _preloadImageAt(index);
                _preloadImageAt(index + 1);
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: _totalCount,
              itemBuilder: (context, index) {
                return KeepAlivePage(
                  child: ColoredBox(
                    color: Colors.black,
                    child: _isVideoAtIndex(index)
                        ? _buildVideoPlayer(_getVideoPath(index), index)
                        : GestureDetector(
                            onTap: _toggleOverlay,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Center(
                                child: _buildImageWidget(
                                  _getImageData(index),
                                  index,
                                ),
                              ),
                            ),
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
                      child: SafeArea(bottom: false,
                        child: AppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          leading: TappableBackButton(
                            isClose: true,
                            color: Colors.white,
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
                            child: Obx(() {
                              final _ = controller.selectedLanguage.value;
                              return Text(
                                trKey('text_currentindex_1_of_totalcount', [
                                  _currentIndex + 1,
                                  _totalCount,
                                ]),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            }),
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
                                    // Not fullscreen: allow both portrait + landscape.
                                    SystemChrome.setPreferredOrientations([
                                      DeviceOrientation.portraitUp,
                                      DeviceOrientation.portraitDown,
                                      DeviceOrientation.landscapeLeft,
                                      DeviceOrientation.landscapeRight,
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
                        child: SafeArea(bottom: false,
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
