import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late AnimationController _overlayController;
  late AnimationController _fadeController;
  bool _showOverlay = true;

  // Add image preloading cache
  final Map<int, ImageProvider> _imageCache = {};
  final Map<int, bool> _imageLoadingStates = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

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
  void dispose() {
    _pageController.dispose();
    _overlayController.dispose();
    _fadeController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          children: [
            // Main image viewer
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                HapticFeedback.lightImpact();
              },
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                return Hero(
                  tag: 'image_${widget.images[index]}',
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: FadeTransition(
                        opacity: _fadeController,
                        child: _buildImageWidget(widget.images[index]),
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
                      child: SafeArea(
                        child: AppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          leading: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              Navigator.of(context).pop();
                              HapticFeedback.lightImpact();
                            },
                          ),
                          title: Center(
                            child: Text(
                              '${_currentIndex + 1} of ${widget.images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          actions: [
                            IconButton(
                              icon: const Icon(
                                Icons.download,
                                color: Colors.transparent,
                              ),
                              onPressed: () {
                                // Add your action here
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
            if (widget.images.length > 1)
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
                                widget.images.length,
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
      ),
    );
  }
}
