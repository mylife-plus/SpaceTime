import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/connectivity_service.dart';
import 'package:spacetime/services/background_tile_download_service.dart';

class InternetRequiredLocationPickerScreen extends StatefulWidget {
  final VoidCallback? onRetryCallback;

  const InternetRequiredLocationPickerScreen({super.key, this.onRetryCallback});

  @override
  State<InternetRequiredLocationPickerScreen> createState() =>
      _InternetRequiredLocationPickerScreenState();
}

class _InternetRequiredLocationPickerScreenState
    extends State<InternetRequiredLocationPickerScreen> {
  late final ConnectivityService connectivityService;
  late final UiController uiController;
  late final BackgroundTileDownloadService backgroundService;

  @override
  void initState() {
    super.initState();

    // Initialize services
    connectivityService = Get.find<ConnectivityService>();
    uiController = Get.find<UiController>();
    backgroundService = Get.find<BackgroundTileDownloadService>();

    // Set up automatic connectivity restoration listener
    _setupConnectivityListener();

    // Add periodic connectivity status refresh
    _startPeriodicStatusRefresh();
  }

  /// Set up listener for automatic screen dismissal when connectivity is restored
  void _setupConnectivityListener() {
    // Use periodic ping checks instead of reactive connectivity listener
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        debugPrint('🌐 [LocationPicker] Periodic connectivity check...');

        // Use existing Mapbox-specific internet check
        bool hasInternet = await connectivityService.hasInternetForMapbox();

        // If Mapbox check fails, try quick check as fallback
        if (!hasInternet) {
          hasInternet = await connectivityService.hasInternetQuickCheck();
          debugPrint(
            '🌐 [LocationPicker] Fallback quick check result: $hasInternet',
          );
        }

        if (hasInternet) {
          debugPrint(
            '🌐 [LocationPicker] Internet confirmed via ping - calling retry callback',
          );

          // Cancel the timer to prevent multiple calls
          timer.cancel();

          // Call the retry callback to reinitialize location picker
          if (widget.onRetryCallback != null && mounted) {
            widget.onRetryCallback!();
          }

          // hide this internet required popup and move to next state

          // if (mounted) {
          //   Get.snackbar(
          //     'Connected',
          //     'Internet restored - loading location picker',
          //     backgroundColor: Colors.green.withValues(alpha: 0.8),
          //     colorText: Colors.white,
          //     snackPosition: SnackPosition.BOTTOM,
          //     margin: const EdgeInsets.all(16),
          //     borderRadius: 12,
          //     duration: const Duration(seconds: 1),
          //   );

          // }
        }
      } catch (e) {
        debugPrint(
          '❌ [LocationPicker] Error during periodic connectivity check: $e',
        );
      }
    });
  }

  /// Start periodic status refresh to ensure UI stays updated
  void _startPeriodicStatusRefresh() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        // Force refresh connectivity service values
        connectivityService.isConnected.refresh();
        connectivityService.connectionType.refresh();
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Container(
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxWidth: 380),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color:
                  uiController.darkMode.value
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: uiController.currentMainColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: uiController.currentMainColor.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated Icon with Gradient Background
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            uiController.currentMainColor.withValues(
                              alpha: 0.2,
                            ),
                            uiController.currentMainColor.withValues(
                              alpha: 0.05,
                            ),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: uiController.currentMainColor.withValues(
                            alpha: 0.3,
                          ),
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing animation background
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: uiController.currentMainColor.withValues(
                                alpha: 0.1,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Main icon
                          Icon(
                            connectivityService.isConnected.value
                                ? Icons.wifi_find
                                : Icons.wifi_off_rounded,
                            size: 48,
                            color: uiController.currentMainColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Title with theme colors
                    Text(
                      'Internet Connection Required',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color:
                            uiController.darkMode.value
                                ? Colors.white
                                : Colors.black87,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Description with better typography - customized for location picker
                    Text(
                      'Location picker needs internet connection or offline maps (30,000+ tiles) to function properly.',
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            uiController.darkMode.value
                                ? Colors.white70
                                : Colors.black54,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Check Connection Button
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            uiController.currentMainColor,
                            uiController.currentMainColor.withValues(
                              alpha: 0.8,
                            ),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: uiController.currentMainColor.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Show modern loading dialog
                          Get.dialog(
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color:
                                      uiController.darkMode.value
                                          ? const Color(0xFF1E1E1E)
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: uiController.currentMainColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            barrierDismissible: false,
                          );

                          try {
                            debugPrint(
                              '🌐 [LocationPicker] Starting connectivity check...',
                            );

                            // Check connectivity
                            bool hasRealInternet = false;
                            try {
                              // Use the existing Mapbox-specific internet check
                              hasRealInternet =
                                  await connectivityService
                                      .hasInternetForMapbox();
                              debugPrint(
                                '🌐 [LocationPicker] Mapbox internet check result: $hasRealInternet',
                              );

                              // If Mapbox check fails, try the quick check as fallback
                              if (!hasRealInternet) {
                                hasRealInternet =
                                    await connectivityService
                                        .hasInternetQuickCheck();
                                debugPrint(
                                  '🌐 [LocationPicker] Quick internet check result: $hasRealInternet',
                                );
                              }
                            } catch (e) {
                              debugPrint(
                                '🌐 [LocationPicker] Internet verification failed: $e',
                              );
                              hasRealInternet = false;
                            }

                            Navigator.pop(context); // Close loading dialog

                            if (hasRealInternet) {
                              debugPrint(
                                '🌐 [LocationPicker] Internet confirmed - connection restored',
                              );

                              // Call retry callback to reinitialize location picker
                              if (widget.onRetryCallback != null) {
                                widget.onRetryCallback!();
                              }
                            } else {
                              debugPrint(
                                '🌐 [LocationPicker] No internet confirmed - showing error message',
                              );

                              // Check tile count for better error message
                              final tileCount =
                                  backgroundService.totalTilesDownloaded.value;
                              final errorMessage =
                                  tileCount < 30000
                                      ? 'No internet connection and insufficient offline tiles ($tileCount/30,000). Please connect to internet.'
                                      : 'Please check your internet connection and try again.';

                              Get.snackbar(
                                'No Internet',
                                errorMessage,
                                backgroundColor: Colors.red.withValues(
                                  alpha: 0.9,
                                ),
                                colorText: Colors.white,
                                snackPosition: SnackPosition.BOTTOM,
                                margin: const EdgeInsets.all(16),
                                borderRadius: 12,
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.pop(
                                context,
                              ); // Close loading dialog on error
                            }
                            debugPrint(
                              '❌ [LocationPicker] Error during connectivity check: $e',
                            );
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text(
                          'Check Connection',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tile count info
                    Obx(
                      () => Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: uiController.currentMainColor.withValues(
                            alpha: 0.05,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: uiController.currentMainColor.withValues(
                              alpha: 0.1,
                            ),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.map_outlined,
                              size: 20,
                              color: uiController.currentMainColor.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Offline tiles: ${backgroundService.totalTilesDownloaded.value.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} / 30,000 required',
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      uiController.darkMode.value
                                          ? Colors.white60
                                          : Colors.black54,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
