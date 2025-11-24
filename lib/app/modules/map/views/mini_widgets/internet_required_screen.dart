import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/connectivity_service.dart';

class InternetRequiredScreen extends StatefulWidget {
  const InternetRequiredScreen({super.key});

  @override
  State<InternetRequiredScreen> createState() => _InternetRequiredScreenState();
}

class _InternetRequiredScreenState extends State<InternetRequiredScreen> {
  late final ConnectivityService connectivityService;
  late final MapController mapController;
  late final UiController uiController;

  @override
  void initState() {
    super.initState();

    // Initialize services
    connectivityService = Get.find<ConnectivityService>();
    mapController = Get.find<MapController>();
    uiController = Get.find<UiController>();

    // Set up automatic connectivity restoration listener
    _setupConnectivityListener();

    // Add periodic connectivity status refresh
    _startPeriodicStatusRefresh();
  }

  /// Set up listener for automatic screen dismissal when connectivity is restored
  void _setupConnectivityListener() {
    // Listen for connectivity changes
    ever(connectivityService.isConnected, (bool isConnected) {
      if (isConnected && connectivityService.connectionType.value != 'none') {
        debugPrint(
          '🌐 [InternetRequiredScreen] Connectivity restored automatically - verifying with existing ping methods',
        );

        // Immediately trigger verification with existing ping methods
        Future.microtask(() async {
          try {
            // Use existing Mapbox-specific internet check
            bool hasInternet = await connectivityService.hasInternetForMapbox();

            // If Mapbox check fails, try quick check as fallback
            if (!hasInternet) {
              hasInternet = await connectivityService.hasInternetQuickCheck();
              debugPrint(
                '🌐 [InternetRequiredScreen] Fallback quick check result: $hasInternet',
              );
            }

            if (hasInternet) {
              debugPrint(
                '🌐 [InternetRequiredScreen] Internet confirmed - immediately advancing state',
              );

              // Immediately advance state to hide this screen
              mapController.setState(MapInitializationState.loadingMap);

              // Then trigger automatic map reload
              mapController.refreshMapView();

              // Get.snackbar(
              //   'Connected',
              //   'Internet restored - loading map',
              //   backgroundColor: Colors.green.withValues(alpha: 0.8),
              //   colorText: Colors.white,
              //   snackPosition: SnackPosition.BOTTOM,
              //   margin: const EdgeInsets.all(16),
              //   borderRadius: 12,
              //   duration: const Duration(seconds: 1),
              // );
            }
          } catch (e) {
            debugPrint(
              '❌ [InternetRequiredScreen] Error during automatic connectivity handling: $e',
            );
          }
        });
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

                    // Description with better typography
                    Text(
                      'Internet connection is required to download map tiles. Once tiles are downloaded, you can use the app fully in offline mode.',
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
                          // Get.dialog(
                          //   Center(
                          //     child: Container(
                          //       padding: const EdgeInsets.all(24),
                          //       decoration: BoxDecoration(
                          //         color: uiController.darkMode.value
                          //             ? const Color(0xFF1E1E1E)
                          //             : Colors.white,
                          //         borderRadius: BorderRadius.circular(16),
                          //       ),
                          //       child: Column(
                          //         mainAxisSize: MainAxisSize.min,
                          //         children: [
                          //           CircularProgressIndicator(
                          //             color: uiController.currentMainColor,
                          //           ),

                          //         ],
                          //       ),
                          //     ),
                          //   ),
                          //   barrierDismissible: false,
                          // );

                          try {
                            // Use the enhanced connectivity refresh method
                            debugPrint(
                              '🌐 [InternetRequiredScreen] Starting enhanced connectivity refresh...',
                            );
                            // await mapController.forceConnectivityRefresh();

                            // Check final connectivity state
                            // final isConnectedValue = connectivityService.isConnected.value;
                            // final connectionType = connectivityService.connectionType.value;

                            debugPrint(
                              '🌐 [InternetRequiredScreen] Final connectivity state:',
                            );
                            // debugPrint('🌐 [InternetRequiredScreen] - isConnected: $isConnectedValue');
                            // debugPrint('🌐 [InternetRequiredScreen] - connectionType: $connectionType');

                            // Use existing ping methods for verification
                            bool hasRealInternet = false;
                            try {
                              debugPrint(
                                '🌐 [InternetRequiredScreen] Performing enhanced internet check...',
                              );

                              // Use the existing Mapbox-specific internet check (includes HTTP ping)
                              hasRealInternet =
                                  await connectivityService
                                      .hasInternetForMapbox();
                              debugPrint(
                                '🌐 [InternetRequiredScreen] Mapbox internet check result: $hasRealInternet',
                              );

                              // If Mapbox check fails, try the quick check as fallback
                              if (!hasRealInternet) {
                                hasRealInternet =
                                    await connectivityService
                                        .hasInternetQuickCheck();
                                debugPrint(
                                  '🌐 [InternetRequiredScreen] Quick internet check result: $hasRealInternet',
                                );
                              }
                            } catch (e) {
                              debugPrint(
                                '🌐 [InternetRequiredScreen] Internet verification failed: $e',
                              );
                              hasRealInternet = false;
                            }

                            // if (context.mounted) {
                            // Navigator.pop(context); // Close loading dialog
                            // }

                            if (hasRealInternet) {
                              debugPrint(
                                '🌐 [InternetRequiredScreen] Internet confirmed - connection restored',
                              );

                              // Immediately hide this screen by advancing map state
                              mapController.setState(
                                MapInitializationState.loadingMap,
                              );

                              // Trigger map reload in background
                              Future.microtask(() async {
                                await mapController
                                    .automaticMapReloadAfterConnectivityRestore();
                              });

                              // Show success message
                              // Get.snackbar(
                              //   'Connection Restored',
                              //   'Internet connection verified. Loading map...',
                              //   backgroundColor: Colors.green.withValues(alpha: 0.9),
                              //   colorText: Colors.white,
                              //   snackPosition: SnackPosition.BOTTOM,
                              //   margin: const EdgeInsets.all(16),
                              //   borderRadius: 12,
                              //   duration: const Duration(seconds: 2),
                              // );
                            } else {
                              // debugPrint('🌐 [InternetRequiredScreen] No internet confirmed - showing error message');
                              // debugPrint('🌐 [InternetRequiredScreen] - isConnected: $isConnectedValue, connectionType: $connectionType, realInternet: $hasRealInternet');

                              // No internet notification removed as requested
                            }
                          } catch (e) {
                            // if (context.mounted) {
                            // Navigator.pop(context); // Close loading dialog on error
                            // }
                            debugPrint(
                              '❌ [InternetRequiredScreen] Error during connectivity check: $e',
                            );
                            // Get.snackbar(
                            //   'Error',
                            //   'Failed to check internet connection. Please try again.',
                            //   backgroundColor: Colors.orange.withValues(alpha: 0.9),
                            //   colorText: Colors.white,
                            //   snackPosition: SnackPosition.BOTTOM,
                            //   margin: const EdgeInsets.all(16),
                            //   borderRadius: 12,
                            // );
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

                    // Modern Help Text with Icon
                    Container(
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
                            Icons.lightbulb_outline_rounded,
                            size: 20,
                            color: uiController.currentMainColor.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Once map tiles are downloaded, you can use the app without internet connection.',
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showOptionsDialog(BuildContext context, UiController uiController) {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          decoration: BoxDecoration(
            color:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: uiController.currentMainColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: uiController.currentMainColor.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      uiController.currentMainColor.withValues(alpha: 0.1),
                      uiController.currentMainColor.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: uiController.currentMainColor.withValues(
                          alpha: 0.2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.settings_rounded,
                        color: uiController.currentMainColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Connection Options',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color:
                            uiController.darkMode.value
                                ? Colors.white
                                : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // WiFi Option
                    _buildOptionTile(
                      icon: Icons.wifi_rounded,
                      title: 'WiFi Settings',
                      subtitle: 'Open device WiFi settings',
                      uiController: uiController,
                      onTap: () {
                        Get.back();
                        Get.snackbar(
                          'WiFi Settings',
                          'Please open WiFi settings from your device settings',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: uiController.currentMainColor
                              .withValues(alpha: 0.9),
                          colorText: Colors.white,
                          borderRadius: 12,
                          margin: const EdgeInsets.all(16),        duration: const Duration(seconds: 2),

                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Mobile Data Option
                    _buildOptionTile(
                      icon: Icons.signal_cellular_alt_rounded,
                      title: 'Mobile Data',
                      subtitle: 'Check mobile data connection',
                      uiController: uiController,
                      onTap: () {
                        Get.back();
                        Get.snackbar(
                          'Mobile Data',
                          'Please check your mobile data connection in device settings',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: uiController.currentMainColor
                              .withValues(alpha: 0.9),
                          colorText: Colors.white,
                          borderRadius: 12,
                          margin: const EdgeInsets.all(16),        duration: const Duration(seconds: 2),

                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Close Button
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: uiController.currentMainColor.withValues(
                            alpha: 0.3,
                          ),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextButton(
                        onPressed: () => Get.back(),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            color: uiController.currentMainColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required UiController uiController,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              uiController.darkMode.value
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                uiController.darkMode.value
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: uiController.currentMainColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: uiController.currentMainColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color:
                          uiController.darkMode.value
                              ? Colors.white
                              : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          uiController.darkMode.value
                              ? Colors.white60
                              : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: uiController.currentMainColor.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  String getConnectivityStatus(bool isConnected, String connectionType) {
    if (!isConnected) return 'No Internet';

    switch (connectionType) {
      case 'wifi':
        mapController.onInit();
        mapController.refreshMapView();
        return 'WiFi Connected';

      // break;
      case 'mobile':
        mapController.onInit();
        mapController.refreshMapView();
        return 'Mobile Data';

      case 'ethernet':
        mapController.onInit();
        mapController.refreshMapView();
        return 'Ethernet';
      case 'other':
        mapController.onInit();
        mapController.refreshMapView();
        return 'Connected';
      default:
        return 'Checking Internet...';
    }
  }
}
