import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../config/app_images.dart';
import '../../../ui/controllers/ui_controller.dart';

class AudioPlayerPopup extends StatefulWidget {
  final String audioPath;
  final String? duration;
  final String? fileName;

  const AudioPlayerPopup({
    super.key,
    required this.audioPath,
    this.duration,
    this.fileName,
  });

  @override
  State<AudioPlayerPopup> createState() => _AudioPlayerPopupState();
}

class _AudioPlayerPopupState extends State<AudioPlayerPopup>
    with TickerProviderStateMixin {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  late AnimationController _waveAnimationController;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayer();
    _setupAnimations();
    _validateAudioFile();
  }

  Future<void> _validateAudioFile() async {
    try {
      final file = File(widget.audioPath);
      if (await file.exists()) {
        final fileSize = await file.length();
        debugPrint('🎵 Audio file validation:');
        debugPrint('  Path: ${widget.audioPath}');
        debugPrint('  Size: $fileSize bytes');
        debugPrint('  Extension: ${widget.audioPath.split('.').last}');

        if (fileSize == 0) {
          debugPrint('❌ Audio file is empty');
        } else {
          debugPrint('✅ Audio file appears valid');
        }
      } else {
        debugPrint('❌ Audio file does not exist at path: ${widget.audioPath}');
      }
    } catch (e) {
      debugPrint('❌ Error validating audio file: $e');
    }
  }

  void _setupAnimations() {
    _waveAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  void _setupAudioPlayer() {
    debugPrint('🎵 Setting up audio player for: ${widget.audioPath}');

    _audioPlayer.onDurationChanged.listen((duration) {
      debugPrint('🎵 Duration changed: $duration');
      setState(() {
        _totalDuration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      debugPrint('🎵 Player state changed: $state');
      setState(() {
        _isPlaying = state == PlayerState.playing;
        _isLoading = state == PlayerState.playing && _currentPosition == Duration.zero;
      });

      if (_isPlaying) {
        _waveAnimationController.repeat();
      } else {
        _waveAnimationController.stop();
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      debugPrint('🎵 Audio playback completed');
      setState(() {
        _isPlaying = false;
        _currentPosition = Duration.zero;
      });
      _waveAnimationController.stop();
    });

    // Add error listener
    _audioPlayer.onLog.listen((message) {
      debugPrint('🎵 Audio player log: $message');
    });
  }

  Future<void> _playPause() async {
    try {
      debugPrint('🎵 Attempting to play audio: ${widget.audioPath}');

      // Check if file exists before trying to play
      final file = File(widget.audioPath);
      if (!await file.exists()) {
        debugPrint('❌ Audio file does not exist: ${widget.audioPath}');
        Get.snackbar(
          'Error',
          'Audio file not found',
          backgroundColor: Colors.red.shade400,
          colorText: Colors.white,
          margin: const EdgeInsets.all(12),
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 2),
        );
        return;
      }

      debugPrint('✅ Audio file exists, size: ${await file.length()} bytes');

      if (_isPlaying) {
        debugPrint('⏸️ Pausing audio');
        await _audioPlayer.pause();
      } else {
        if (_currentPosition == Duration.zero) {
          debugPrint('▶️ Starting audio from beginning');

          // Set audio mode for better compatibility
          await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);

          // Start from beginning - try different source types
          try {
            debugPrint('🔄 Trying DeviceFileSource...');
            await _audioPlayer.play(DeviceFileSource(widget.audioPath));
            debugPrint('✅ DeviceFileSource worked');
          } catch (deviceSourceError) {
            debugPrint('❌ DeviceFileSource failed: $deviceSourceError');

            // Try alternative approach with file:// protocol
            try {
              debugPrint('🔄 Trying UrlSource with file:// protocol...');
              await _audioPlayer.play(UrlSource('file://${widget.audioPath}'));
              debugPrint('✅ UrlSource with file:// protocol worked');
            } catch (urlSourceError) {
              debugPrint('❌ UrlSource with file:// also failed: $urlSourceError');

              // Try without file:// protocol
              try {
                debugPrint('🔄 Trying UrlSource without protocol...');
                await _audioPlayer.play(UrlSource(widget.audioPath));
                debugPrint('✅ UrlSource without protocol worked');
              } catch (finalError) {
                debugPrint('❌ All source types failed: $finalError');
                rethrow;
              }
            }
          }
        } else {
          debugPrint('▶️ Resuming audio from position: $_currentPosition');
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      debugPrint('❌ Error playing audio: $e');
      debugPrint('❌ Audio path: ${widget.audioPath}');
      debugPrint('❌ Error type: ${e.runtimeType}');

      Get.snackbar(
        'Playback Error',
        'Could not play audio file: ${e.toString()}',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _stop() async {
    await _audioPlayer.stop();
    setState(() {
      _currentPosition = Duration.zero;
    });
  }

  Future<void> _seek(double value) async {
    final position = Duration(milliseconds: (value * _totalDuration.inMilliseconds).round());
    await _audioPlayer.seek(position);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _waveAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: uiController.darkMode.value
              ? Colors.grey[900]
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Opacity(
                  opacity: 0,
                   child: IconButton(
                    onPressed: () => Get.back(),
                    icon: Icon(
                      Icons.close,
                      color: uiController.darkMode.value ? Colors.white : Colors.black,
                    ),
                                   ),
                 ),
                Text(
                  'Audio Player',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                  ),
                ),
                IconButton(
                  onPressed: () => Get.back(),
                  icon: Icon(
                    Icons.close,
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // File name and debug info
            // if (widget.fileName != null)
            //   Column(
            //     children: [
            //       Text(
            //         widget.fileName!,
            //         style: TextStyle(
            //           fontSize: 16,
            //           color: uiController.darkMode.value ? Colors.grey[300] : Colors.grey[600],
            //         ),
            //         textAlign: TextAlign.center,
            //         maxLines: 2,
            //         overflow: TextOverflow.ellipsis,
            //       ),
            //       const SizedBox(height: 8),
            //       // Debug info
            //       Text(
            //         'Path: ${widget.audioPath.split('/').last}',
            //         style: TextStyle(
            //           fontSize: 12,
            //           color: uiController.darkMode.value ? Colors.grey[400] : Colors.grey[500],
            //         ),
            //         textAlign: TextAlign.center,
            //         maxLines: 1,
            //         overflow: TextOverflow.ellipsis,
            //       ),
            //       if (widget.duration != null)
            //         Text(
            //           'Duration: ${widget.duration}',
            //           style: TextStyle(
            //             fontSize: 12,
            //             color: uiController.darkMode.value ? Colors.grey[400] : Colors.grey[500],
            //           ),
            //           textAlign: TextAlign.center,
            //         ),
            //     ],
            //   ),
            
            const SizedBox(height: 30),
            
            // Audio wave visualization
            Container(
              height: 80,
              width: double.infinity,
              decoration: BoxDecoration(
                color: uiController.darkMode.value
                    ? Colors.grey[800]
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: AnimatedBuilder(
                  animation: _waveAnimation,
                  builder: (context, child) {
                    return Image.asset(
                      AppImages.audioWaves,
                      width: 60,
                      height: 60,
                      color: _isPlaying
                          ? Colors.blue.withValues(alpha: 0.7 + 0.3 * _waveAnimation.value)
                          : (uiController.darkMode.value ? Colors.white : Colors.black),
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Progress bar
            Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.blue,
                    inactiveTrackColor: Colors.grey[300],
                    thumbColor: Colors.blue,
                    overlayColor: Colors.blue.withValues(alpha: 0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _totalDuration.inMilliseconds > 0
                        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
                        : 0.0,
                    onChanged: _seek,
                  ),
                ),
                
                // Time display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_currentPosition),
                        style: TextStyle(
                          color: uiController.darkMode.value ? Colors.grey[300] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(_totalDuration),
                        style: TextStyle(
                          color: uiController.darkMode.value ? Colors.grey[300] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),

            // // Debug button (temporary)
            // ElevatedButton(
            //   onPressed: () async {
            //     debugPrint('🔧 Debug button pressed');
            //     final file = File(widget.audioPath);
            //     final exists = await file.exists();
            //     final size = exists ? await file.length() : 0;

            //     Get.snackbar(
            //       'Debug Info',
            //       'File exists: $exists\nSize: $size bytes\nPath: ${widget.audioPath}',
            //       backgroundColor: Colors.blue.shade400,
            //       colorText: Colors.white,
            //       margin: const EdgeInsets.all(12),
            //       snackPosition: SnackPosition.BOTTOM,
            //       duration: const Duration(seconds: 5),
            //     );
            //   },
            //   child: const Text('Debug File Info'),
            // ),

            const SizedBox(height: 20),

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Stop button
                IconButton(
                  onPressed: _stop,
                  icon: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.stop,
                      color: uiController.darkMode.value ? Colors.white : Colors.black,
                      size: 24,
                    ),
                  ),
                ),
                
                // Play/Pause button
                IconButton(
                  onPressed: _isLoading ? null : _playPause,
                  icon: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                  ),
                ),
                
                // Placeholder for symmetry
                IconButton(
                  onPressed: null,
                  icon: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.stop,
                      color: Colors.transparent,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
