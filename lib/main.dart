import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/helpers/offline_water_service.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/map/controllers/memory_location_picker_with_radius_controller.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_location_picker_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/services/connectivity_service.dart';
import 'package:spacetime/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:background_downloader/background_downloader.dart';

import 'app/modules/memories/controllers/memory_controller.dart';
import 'app/modules/map/controllers/map_controller_new.dart';
import 'app/repositories/memory_repository.dart';
import 'app/repositories/cluster_repository.dart';
import 'app/services/map_marker_service.dart';
import 'app/services/map_marker_creation_service.dart';
import 'app/routes/app_pages.dart';
import 'app/services/memory_db.dart';
import 'app/services/path_migration_helper.dart';
import 'app/helpers/mapbox_zoom_helper.dart';
// Mapbox tile downloading services removed - using URL-based mbtiles download instead
// import 'services/background_tile_download_service.dart';
// import 'app/services/offline_map_service.dart';
// import 'app/repositories/offline_map_repository.dart';
// import 'app/services/offline_map_coordinator_service.dart';
// import 'app/services/native_tile_download_service.dart';
import 'app/modules/get_started/controllers/get_started_controller.dart';
import 'services/asset_tile_loader_service.dart';
import 'services/mbtiles_download_service.dart';
import 'services/mbtiles_server_service.dart';
import 'services/style_json_download_service.dart';
import 'services/memory_geojson_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restrict orientation to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables
  await dotenv.load(fileName: ".env");
  MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));

  // Initialize background downloader
  await FileDownloader().trackTasks();
  FileDownloader().configureNotification(
    running: const TaskNotification('Downloading', 'Download in progress'),
    complete: const TaskNotification('Download complete', 'File downloaded successfully'),
    error: const TaskNotification('Download failed', 'An error occurred'),
    paused: const TaskNotification('Download paused', 'Tap to resume'),
    progressBar: true,
  );
  FileDownloader().registerCallbacks(
    taskNotificationTapCallback: (task, notificationType) {
      debugPrint('[BackgroundDownloader] Notification tapped: $notificationType');
    },
  );

  // Initialize only critical services
  Get.put(UiController(), permanent: true);
  Get.put(ConnectivityService(), permanent: true);
  Get.put(PermissionService(), permanent: true);
  Get.put(MemoryRepository(), permanent: true);
  Get.put(ClusterRepository(), permanent: true);
  Get.put(MapMarkerCreationService(), permanent: true);
  Get.put(MapMarkerService(), permanent: true);
  Get.put(StyleJsonDownloadService(), permanent: true);
  Get.put(GeocodingIsolateService(), permanent: true);

  // Initialize controllers - GetStartedController handles heavy init
  Get.put(GetStartedController(), permanent: true);
  Get.put(MemoryController(), permanent: true);
  Get.put(FilterController(), permanent: true);
  Get.put(AddMemoriesController(), permanent: true);
  Get.put(MapControllerNew(), permanent: true);
  Get.put(MemoryLocationPickerControllerWithRadius(), permanent: true);

  runApp(MyApp());
}

Future<void> clearAppData() async {
  try {
    // 1️⃣ Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 2️⃣ Clear temp/cache directories
    final tempDir = await getTemporaryDirectory();
    final appSupportDir = await getApplicationSupportDirectory();
    final appDocDir = await getApplicationDocumentsDirectory();

    for (final dir in [tempDir, appSupportDir, appDocDir]) {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }

    debugPrint('✅ App data cleared successfully.');
  } catch (e) {
    debugPrint('⚠️ Error clearing app data: $e');
  }
}


/// Test the geocoding service with sample coordinates
Future<void> _testGeocodingService() async {
  try {
    debugPrint('🧪 Testing GeocodingIsolateService...');

    final geocodingService = GeocodingIsolateService.instance;

    // }
  } catch (e) {
    debugPrint('❌ Test failed: $e');
  }
}

/// Initialize background tile server if tiles are downloaded
/// This runs once when the app starts
Future<void> _initializeBackgroundTileServer() async {
  try {
    debugPrint('🗺️ [MAIN] Checking if mbtiles are downloaded...');

    final mbtilesService = MbtilesDownloadService.instance;
    final isDownloaded = await mbtilesService.isMbtilesDownloaded();
    final tilesPath = mbtilesService.getLocalMbtilesPath();

    debugPrint('🗺️ [MAIN] MBTiles check: isDownloaded=$isDownloaded, tilesPath=$tilesPath');

    if (isDownloaded && tilesPath != null) {
      debugPrint('🗺️ [MAIN] ✅ MBTiles found, starting background tile server...');

      final serverService = MbtilesServerService.instance;
      final serverUrl = await serverService.startServer(tilesPath);

      if (serverUrl != null) {
        debugPrint('🗺️ [MAIN] ✅ Background tile server started successfully at: $serverUrl');
        debugPrint('🗺️ [MAIN] 📡 Tiles will be served from: $serverUrl/{z}/{x}/{y}.pbf');
      } else {
        debugPrint('🗺️ [MAIN] ❌ Failed to start background tile server');
      }
    } else {
      debugPrint('🗺️ [MAIN] ⚠️ MBTiles not downloaded - server not started');
      debugPrint('🗺️ [MAIN] ℹ️ User will be directed to Get Started screen to download tiles');
    }
  } catch (e) {
    debugPrint('🗺️ [MAIN] ❌ Error initializing background tile server: $e');
    // Continue app startup even if server fails
  }
}

class MyApp extends StatelessWidget {
  MyApp({super.key});
  final UiController uiController = Get.find();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => GetMaterialApp(
        title: "Application",
        initialRoute: AppPages.INITIAL,
        getPages: AppPages.routes,
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: Colors.white),
            bodySmall: TextStyle(color: Colors.white),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            iconTheme: IconThemeData(color: Colors.white),
          ),
        ),
        themeMode:
            uiController.darkMode.value ? ThemeMode.dark : ThemeMode.light,
      ),
    );
  }
}
