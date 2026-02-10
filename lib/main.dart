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
  
  await NearestRegionService().loadFromAssets();
  await OfflineWaterService.instance.init(
    oceanGeoJson: 'assets/geo/ne_110m_geography_marine_polys.json',
    lakeGeoJson: 'assets/geo/ne_110m_lakes.json',
  );
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

  // Migrate absolute paths to relative paths
  debugPrint('🔄 [MAIN] Running path migration...');
  try {
    await PathMigrationHelper.instance.migrateAllPathsToRelative();
    debugPrint('🔄 [MAIN] Path migration completed');
  } catch (e) {
    debugPrint('🔄 [MAIN] Path migration failed: $e');
    // Continue with app startup even if migration fails
  }

  // Initialize hashtag groups if not already done
  debugPrint('🏷️ [MAIN] Initializing hashtag groups...');
  try {
    await DatabaseHelper.instance.initializeHashtagGroupsIfNeeded();
    debugPrint('🏷️ [MAIN] Hashtag groups initialization completed');
  } catch (e) {
    debugPrint('🏷️ [MAIN] Hashtag groups initialization failed: $e');
  }

  // Initialize Mapbox Zoom Helper (must be done before any map initialization)
  debugPrint('🔍 [MAIN] Initializing Mapbox Zoom Helper...');
  try {
    await MapboxZoomHelper.initialize();
    debugPrint('🔍 [MAIN] Mapbox Zoom Helper initialized successfully');
  } catch (e) {
    debugPrint('🔍 [MAIN] Mapbox Zoom Helper initialization failed: $e');
  }

  // Initialize year color index cache (once per app launch)
  debugPrint('🎨 [MAIN] Initializing year color index cache...');
  try {
    MemoryGeoJsonService.initializeYearColorIndexCache();
    debugPrint('🎨 [MAIN] Year color index cache initialized successfully');
  } catch (e) {
    debugPrint('🎨 [MAIN] Year color index cache initialization failed: $e');
  }

  // Start local tile server in background if tiles are downloaded
  debugPrint('🗺️ [MAIN] Checking for downloaded tiles and starting server...');
  await _initializeBackgroundTileServer();

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
  Get.put(StyleJsonDownloadService(), permanent: true);
  // MemoryLocationPickerController

  // Mapbox tile downloading services removed - using URL-based mbtiles download instead
  // Get.put(BackgroundTileDownloadService(), permanent: true);
  // Get.put(OfflineMapService(), permanent: true);
  // Get.put(OfflineMapRepository(), permanent: true);
  // Get.put(OfflineMapCoordinatorService(), permanent: true);
  // Get.put(NativeTileDownloadService(), permanent: true);

  debugPrint('✅ Global services initialized');

  // Initialize controllers as permanent singletons
  debugPrint('🎮 Initializing controllers...');
  Get.put(UiController(), permanent: true);
  Get.put(GetStartedController(), permanent: true); // Initialize Get Started controller first
  Get.put(MemoryController(), permanent: true);
  Get.put(FilterController(), permanent: true); // Initialize FilterController before AddMemoriesController and MapControllerNew
  Get.put(AddMemoriesController(), permanent: true);
  Get.put(MapControllerNew(), permanent: true);
  Get.put(MemoryLocationPickerControllerWithRadius(), permanent: true);
  debugPrint('✅ Controllers initialized as permanent singletons');

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
