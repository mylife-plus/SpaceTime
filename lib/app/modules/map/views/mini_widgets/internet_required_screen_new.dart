import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/connectivity_service.dart';

class InternetRequiredScreenNew extends StatefulWidget {
  const InternetRequiredScreenNew({super.key});

  @override
  State<InternetRequiredScreenNew> createState() =>
      _InternetRequiredScreenNewState();
}

class _InternetRequiredScreenNewState extends State<InternetRequiredScreenNew>
    with TickerProviderStateMixin {
  late final ConnectivityService connectivityService;
  late final MapControllerNew mapController;
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
      mapController = Get.find<MapControllerNew>();
      debugPrint(
        '[InternetRequiredScreenNew] Services initialized successfully',
      );
    } catch (e) {
      debugPrint('[InternetRequiredScreenNew] Error initializing services: $e');
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

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _pulseController.repeat(reverse: true);
    _fadeController.forward();
  }

  void _setupConnectivityListener() {
    ever(connectivityService.isConnected, (bool isConnected) {
      if (isConnected && connectivityService.connectionType.value != 'none') {
        debugPrint(
          '[InternetRequiredScreenNew] Connectivity restored, verifying internet access',
        );
        _verifyInternetAndDismiss();
      }
    });
  }

  void _startPeriodicStatusRefresh() {
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _checkConnectivityStatus();
      }
    });
  }

  Future<void> _verifyInternetAndDismiss() async {
    try {
     

      // First check basic connectivity
      if (!connectivityService.isConnected.value) {
       
        return;
      }

      // Use the connectivity service's more reliable ping method
      bool hasInternet = await connectivityService.hasInternetQuickCheck();

      if (hasInternet) {
        

        // Update map controller state
        // mapController.hasInternetConnection.value = true;
        // mapController.showInternetRequiredScreen.value = false;

        // Retry map initialization
        await mapController.retryLocationPermission();
      } else {
       
      }
    } catch (e) {
      // debugPrint('[InternetRequiredScreenNew] Error verifying internet: $e');
    }
  }

  Future<void> _checkConnectivityStatus() async {
    try {
      await connectivityService.refreshConnectivity();
    } catch (e) {
      debugPrint('[InternetRequiredScreenNew] Error checking connectivity: $e');
    }
  }

  Future<void> _manualRetry() async {
    debugPrint('[InternetRequiredScreenNew] Manual retry initiated');

    // Show loading state
    setState(() {});

    // Start retry timer to prevent spam
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() {});
    });

    // Force refresh connectivity first
    debugPrint(
      '[InternetRequiredScreenNew] Refreshing connectivity before retry',
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
      final mainColor = uiController.currentMainColor;

      // Define colors based on theme
      final backgroundColor = isDarkMode
          ? Colors.black
          : uiController.getLightModeBackgroundColor(uiController.mainColor.value);

      final gradientColors = isDarkMode
          ? [
              Color.lerp(mainColor, Colors.black, 0.3)!.withValues(alpha: 0.8),
              Colors.black87,
              Color.lerp(mainColor, Colors.black, 0.5)!.withValues(alpha: 0.6),
            ]
          : [
              Color.lerp(mainColor, Colors.white, 0.8)!.withValues(alpha: 0.9),
              backgroundColor,
              Color.lerp(mainColor, Colors.white, 0.6)!.withValues(alpha: 0.7),
            ];

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
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated WiFi Icon
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      final iconColor = isDarkMode
                          ? Colors.red.shade300
                          : Colors.red.shade600;
                      final circleColor = isDarkMode
                          ? Colors.red.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.1);
                      final borderColor = isDarkMode
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.red.withValues(alpha: 0.3);

                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: circleColor,
                            border: Border.all(
                              color: borderColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.wifi_off,
                            size: 80,
                            color: iconColor,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // Title
                  Text(
                    'text_no_internet_connection'.tr,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                          color: isDarkMode
                              ? Colors.black.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'text_mapbox_requires_an_active_internet_connection_to_lo'.tr,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.8),
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
                      'text_the_app_will_automatically_continue_when_your_conne'.tr,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode
                            ? mainColor.withValues(alpha: 0.8)
                            : mainColor.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Connection Status
                  Obx(
                    () {
                      final statusColor = connectivityService.isConnected.value
                          ? (isDarkMode ? Colors.green.shade300 : Colors.green.shade600)
                          : (isDarkMode ? Colors.red.shade300 : Colors.red.shade600);

                      final containerColor = isDarkMode
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.3);

                      final borderColor = isDarkMode
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.2);

                      final textColor = isDarkMode
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.black.withValues(alpha: 0.8);

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: containerColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: borderColor,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              connectivityService.isConnected.value
                                  ? Icons.signal_wifi_4_bar
                                  : Icons.signal_wifi_off,
                              color: statusColor,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              connectivityService.isConnected.value
                                  ? 'Connected to ${connectivityService.connectionType.value.toUpperCase()}'
                                  : 'No Network Connection',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

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
                      backgroundColor: mainColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Help Text
                  Text(
                    'text_check_your_wifi_or_mobile_data_connection'.tr,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      );
    });
  }
}
