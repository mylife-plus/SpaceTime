import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../modules/get_started/controllers/get_started_controller.dart';
import '../routes/app_pages.dart';

/// Widget that handles initial routing based on tile download status
class StartupRouter extends StatefulWidget {
  const StartupRouter({super.key});

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  @override
  void initState() {
    super.initState();
    _checkInitialRoute();
  }

  /// Check tile download status and navigate to appropriate screen
  Future<void> _checkInitialRoute() async {
    try {
      // Small delay to ensure app is fully initialized
      await Future.delayed(const Duration(milliseconds: 100));
      
      final shouldShowGetStarted = await GetStartedController.shouldShowGetStarted();
      
      if (shouldShowGetStarted) {
        // Tiles not downloaded - show Get Started screen
        Get.offAllNamed(Routes.GET_STARTED);
      } else {
        // Tiles downloaded - go directly to main app
        Get.offAllNamed(Routes.MAP_NEW);
      }
    } catch (e) {
      debugPrint('[StartupRouter] Error checking initial route: $e');
      // On error, default to Get Started screen
      Get.offAllNamed(Routes.GET_STARTED);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: MediaQuery.sizeOf(context).width,
        height: MediaQuery.sizeOf(context).height,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Start.jpg'),
            fit: BoxFit.fill,
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }
}
