import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/services/connectivity_service.dart';
import 'package:spacetime/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'app/modules/memories/controllers/memory_controller.dart';
import 'app/modules/map/controllers/map_controller_new.dart';
import 'app/repositories/memory_repository.dart';
import 'app/repositories/cluster_repository.dart';
import 'app/services/map_marker_service.dart';
import 'app/services/map_marker_creation_service.dart';
import 'app/routes/app_pages.dart';
import 'app/services/memory_db.dart';
import 'services/background_tile_download_service.dart';
import 'app/services/offline_map_service.dart';
import 'app/repositories/offline_map_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restrict orientation to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize database with health check
  debugPrint('🗄️ [MAIN] Initializing database...');
  try {
    await DatabaseHelper.instance.database;

    // Verify database health
    final isHealthy = await DatabaseHelper.instance.isDatabaseHealthy();
    if (!isHealthy) {
      debugPrint('🗄️ [MAIN] Database unhealthy, resetting connection...');
      await DatabaseHelper.instance.resetDatabaseConnection();
    }

    debugPrint('🗄️ [MAIN] Database initialization completed successfully');
  } catch (e) {
    debugPrint('🗄️ [MAIN] Database initialization failed: $e');
    // Continue with app startup even if database fails
  }

  // Initialize place categories if not already done
  debugPrint('🏷️ [MAIN] Initializing place categories...');
  await DatabaseHelper.instance.initializePlaceCategoriesIfNeeded();
  debugPrint('🏷️ [MAIN] Place categories initialization completed');

  await dotenv.load(fileName: ".env");
  MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));

  // Initialize services
  debugPrint('🚀 Initializing GeocodingIsolateService...');
  final geocodingService = Get.put(GeocodingIsolateService(), permanent: true);

  // Ensure the service is properly initialized
  try {
    await geocodingService.ensureInitialized();
    debugPrint('✅ GeocodingIsolateService initialized successfully');
  } catch (e) {
    debugPrint('❌ Failed to initialize GeocodingIsolateService: $e');
  }

  // Initialize global services
  debugPrint('🔧 Initializing global services...');
  Get.put(ConnectivityService(), permanent: true);
  Get.put(PermissionService(), permanent: true);
  Get.put(MemoryRepository(), permanent: true);
  Get.put(ClusterRepository(), permanent: true);
  Get.put(MapMarkerCreationService(), permanent: true);
  Get.put(MapMarkerService(), permanent: true);
  Get.put(BackgroundTileDownloadService(), permanent: true);
  Get.put(OfflineMapService(), permanent: true);
  Get.put(OfflineMapRepository(), permanent: true);
  debugPrint('✅ Global services initialized');

  // Initialize controllers
  Get.put(UiController());
  Get.put(MemoryController());
  Get.put(AddMemoriesController());
  Get.put(MapControllerNew());

  // Test the geocoding service
  _testGeocodingService();

  // TEMPORARY: Clear app data for testing (comment out when not needed)
  // await _clearAppData();

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
