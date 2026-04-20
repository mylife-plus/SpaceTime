import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/connectivity_service.dart';

class InternetRequiredScreenLocationPicker extends StatefulWidget {
  final VoidCallback? onRetryCallback;
  
  const InternetRequiredScreenLocationPicker({
    super.key,
    this.onRetryCallback,
  });

  @override
  State<InternetRequiredScreenLocationPicker> createState() =>
      _InternetRequiredScreenLocationPickerState();
}

class _InternetRequiredScreenLocationPickerState extends State<InternetRequiredScreenLocationPicker>
    with TickerProviderStateMixin {
  late final ConnectivityService connectivityService;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _statusRefreshTimer;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupAnimations();
    _setupConnectivityListener();
    _startPeriodicStatusRefresh();
  }

  void _initializeServices() {
    try {
      connectivityService = Get.find<ConnectivityService>();
      debugPrint(
        '[InternetRequiredScreenLocationPicker] Services initialized successfully',
      );
    } catch (e) {
      debugPrint('[InternetRequiredScreenLocationPicker] Error initializing services: $e');
    }
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
    _fadeController.repeat(reverse: true);
  }

  void _setupConnectivityListener() {
    // Listen for connectivity changes
    ever(connectivityService.isConnected, (bool isConnected) {
      if (isConnected && mounted) {
        debugPrint(
          '[InternetRequiredScreenLocationPicker] Connectivity restored, verifying internet...',
        );
        _verifyInternetAndDismiss();
      }
    });
  }

  void _startPeriodicStatusRefresh() {
    _statusRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        if (mounted) {
          _verifyInternetAndDismiss();
        }
      },
    );
  }

  Future<void> _verifyInternetAndDismiss() async {
    try {
     

      // Check if we have internet connectivity
      final hasInternet = await connectivityService.hasInternetQuickCheck();

      if (hasInternet) {
        debugPrint(
          '[InternetRequiredScreenLocationPicker] Internet verified, dismissing screen',
        );

        // Call the retry callback if provided
        if (widget.onRetryCallback != null) {
          widget.onRetryCallback!();
        }
      } else {
        debugPrint(
          '[InternetRequiredScreenLocationPicker] Internet verification failed, staying on screen',
        );
      }
    } catch (e) {
      debugPrint('[InternetRequiredScreenLocationPicker] Error verifying internet: $e');
    }
  }

  Future<void> _manualRetry() async {
    debugPrint('[InternetRequiredScreenLocationPicker] Manual retry initiated');

    // Show loading state
    setState(() {});

    // Start retry timer to prevent spam
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() {});
    });

    // Force refresh connectivity first
    debugPrint(
      '[InternetRequiredScreenLocationPicker] Refreshing connectivity before retry',
    );
    await connectivityService.refreshConnectivity();

    // Then verify internet and dismiss
    await _verifyInternetAndDismiss();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _statusRefreshTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      final isDarkMode = uiController.darkMode.value;
      final mainColor = uiController.currentMainColor; // Use the getter that converts to Color

      // Dynamic color scheme based on theme
      final backgroundColor = isDarkMode ? Colors.black : Colors.white;
      final gradientColors = [
        Color.lerp(mainColor, Colors.black, 0.8)!.withValues(alpha: 0.9),
        backgroundColor,
        Color.lerp(mainColor, Colors.white, 0.6)!.withValues(alpha: 0.7),
      ];

      // Text colors
      final textColor = isDarkMode ? Colors.white : Colors.black87;
      final buttonColor = mainColor; // Uses UI controller's current main color

      return Scaffold(
        backgroundColor: backgroundColor,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated WiFi Icon
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: AnimatedBuilder(
                          animation: _fadeAnimation,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _fadeAnimation.value,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: mainColor.withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: mainColor.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.wifi_off_rounded,
                                  size: 60,
                                  color: mainColor,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // Title
                  Text(
                    'text_no_internet_connection_2'.tr,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'text_please_check_your_internet_connection_and_try_again'.tr,
                      style: TextStyle(
                        fontSize: 16,
                        color: textColor.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Auto-retry message
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'text_the_app_will_automatically_continue_when_your_conne_2'.tr,
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Connection Status
                  Obx(() {
                    final isConnected = connectivityService.isConnected.value;
                    final connectionType = connectivityService.connectionType.value;
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isConnected 
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: isConnected 
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isConnected ? Icons.check_circle : Icons.error,
                            color: isConnected ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isConnected 
                                ? 'Connected via $connectionType'
                                : 'No Connection',
                            style: TextStyle(
                              color: isConnected ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 30),

                  // Manual Retry Button
                  ElevatedButton.icon(
                    onPressed:
                        _retryTimer?.isActive == true ? null : _manualRetry,
                    icon:
                        _retryTimer?.isActive == true
                            ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
                            )
                            : Icon(Icons.refresh,
                                color: isDarkMode ? Colors.white : Colors.black),
                    label: Text(
                      _retryTimer?.isActive == true
                          ? 'Checking...'
                          : 'Try Again',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: isDarkMode ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                      shadowColor: buttonColor.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
