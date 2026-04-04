import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../routes/app_pages.dart';
import '../services/permission_settings_resume_service.dart';
import '../../../services/mbtiles_download_service.dart';

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

      debugPrint('[StartupRouter] Checking if tiles are downloaded...');

      // Check if mbtiles are downloaded
      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      debugPrint('[StartupRouter] Tiles downloaded: $isDownloaded, path: $tilesPath');

      if (isDownloaded && tilesPath != null) {
        // Tiles downloaded - go directly to MapViewWidgetNew
        debugPrint('[StartupRouter] ✅ Tiles found, navigating to MapViewWidgetNew');
        Get.offAllNamed(Routes.MAP_NEW);
        PermissionSettingsResumeService.scheduleOpenMemoryViewIfPending();
      } else {
        // Tiles not downloaded - show Get Started screen
        debugPrint('[StartupRouter] ⚠️ Tiles not found, navigating to Get Started screen');
        Get.offAllNamed(Routes.GET_STARTED);
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
