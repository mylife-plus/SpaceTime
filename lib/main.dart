import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_input_theme.dart';
import 'package:spacetime/app/config/app_locale.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/helpers/offline_water_service.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/theme/app_system_ui.dart';
import 'package:spacetime/services/app_lock_controller.dart';
import 'package:spacetime/services/memory_import_blocking_controller.dart';
import 'package:spacetime/widgets/app_lock_gate.dart';
import 'package:spacetime/widgets/memory_import_blocking_overlay.dart';
import 'package:spacetime/services/connectivity_service.dart';
import 'package:spacetime/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:background_downloader/background_downloader.dart';

import 'app/routes/app_pages.dart';
import 'app/shared/widgets/restart_widget.dart';
import 'app/services/memory_db.dart';
import 'app/services/path_migration_helper.dart';
import 'app/helpers/mapbox_zoom_helper.dart';
// Mapbox tile downloading services removed - using URL-based mbtiles download instead
// import 'services/background_tile_download_service.dart';
// import 'app/services/offline_map_service.dart';
// import 'app/repositories/offline_map_repository.dart';
// import 'app/services/offline_map_coordinator_service.dart';
// import 'app/services/native_tile_download_service.dart';
import 'services/asset_tile_loader_service.dart';
import 'services/mbtiles_download_service.dart';
import 'services/mbtiles_server_service.dart';
import 'services/style_json_download_service.dart';
import 'services/memory_geojson_service.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'app/modules/get_started/controllers/get_started_controller.dart';

/// True after [main] runs until the app enters [AppLifecycleState.paused].
/// Reset only on a new process start (not on resume from background).
class AppProcessLaunch {
  static bool isFreshLaunch = false;
}

Future<void> main() async {
  AppProcessLaunch.isFreshLaunch = true;

  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  await L10nLoader.init();

  // Only what MyApp needs for the first frame — everything else runs after paint
  // so the engine reaches runApp quickly and the native splash can dismiss.
  Get.put(UiController(), permanent: true);
  Get.put(AppLockController(), permanent: true);
  Get.put(MemoryImportBlockingController(), permanent: true);

  runApp(RestartWidget(child: MyApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _bootstrapAfterFirstPaint();
  });
}

Future<void> _bootstrapAfterFirstPaint() async {
  // Wait one extra frame so background images decode before splash lifts.
  final splashCompleter = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
    splashCompleter.complete();
  });
  await splashCompleter.future;

  try {
    await AppSystemUi.enableEdgeToEdge();
    if (Get.isRegistered<UiController>()) {
      AppSystemUi.syncTheme(Get.find<UiController>().darkMode.value);
    }
  } catch (e) {
    debugPrint('[main] edge-to-edge / system UI: $e');
  }

  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e) {
    debugPrint('[main] setPreferredOrientations: $e');
  }

  try {
    await dotenv.load(fileName: ".env");
    MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));
  } catch (e) {
    debugPrint('[main] dotenv / Mapbox token: $e');
  }

  FileDownloader().trackTasks();
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

  Get.put(ConnectivityService(), permanent: true);
  Get.put(PermissionService(), permanent: true);
  Get.put(StyleJsonDownloadService(), permanent: true);

  if (Get.isRegistered<GetStartedController>()) {
    Get.find<GetStartedController>().runStartupInitialization();
  }

  unawaited(_deferGeoAssets());
}

Future<void> _deferGeoAssets() async {
  // Wait until after first map frame / Get Started so CSV/GeoJSON workers
  // do not compete with Mapbox style setup on a cold start (ANR risk).
  await Future<void>.delayed(const Duration(seconds: 2));
  await _initAssets();
}

Future<void> _initAssets() async {
  try {
    await NearestRegionService().loadFromAssets();
    await OfflineWaterService.instance.init(
      oceanGeoJson: 'assets/geo/ne_110m_geography_marine_polys.json',
      lakeGeoJson: 'assets/geo/ne_110m_lakes.json',
    );
  } catch (e) {
    debugPrint('[GetStartedController] Assets init error: $e');
  }
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final UiController uiController = Get.find();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      AppProcessLaunch.isFreshLaunch = false;
    }
    // App-level (iOS) lifecycle logging. iOS only reports `paused` on a full
    // background and `resumed` on return; a system sheet / Settings round-trip
    // often only reaches `inactive`/`hidden`, so log every state to make the
    // real transition visible.
    if (Platform.isIOS) {
      switch (state) {
        case AppLifecycleState.resumed:
          debugPrint('📱 [APP][iOS] RESUMED (foregrounded / app opened)');
          break;
        case AppLifecycleState.inactive:
          debugPrint('📱 [APP][iOS] INACTIVE (transitioning / system sheet)');
          break;
        case AppLifecycleState.hidden:
          debugPrint('📱 [APP][iOS] HIDDEN');
          break;
        case AppLifecycleState.paused:
          debugPrint('📱 [APP][iOS] PAUSED (backgrounded)');
          break;
        case AppLifecycleState.detached:
          debugPrint('📱 [APP][iOS] DETACHED');
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final accent = uiController.currentMainColor;
      final trackLight = accent.withValues(alpha: 0.14);
      final trackDark = accent.withValues(alpha: 0.22);

      return GetMaterialApp(
        title: 'title_literal_application'.tr,
        translations: SpaceTimeTranslations(),
        locale: appLocaleFromLanguageCode(uiController.selectedLanguage.value),
        fallbackLocale: const Locale('en'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('es'),
          Locale('fr'),
          Locale('de'),
        ],
        initialRoute: AppPages.INITIAL,
        getPages: AppPages.routes,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          final ui = Get.find<UiController>();
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppSystemUi.overlayStyle(dark: ui.darkMode.value),
            child: MemoryImportBlockingOverlay(
              child: AppLockGate(child: child),
            ),
          );
        },
        theme: ThemeData.light().copyWith(
          inputDecorationTheme: AppInputTheme.singleLineDecorationTheme,
          progressIndicatorTheme: ProgressIndicatorThemeData(
            color: accent,
            circularTrackColor: trackLight,
            linearTrackColor: trackLight,
          ),
        ),
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
          inputDecorationTheme: AppInputTheme.singleLineDecorationTheme,
          progressIndicatorTheme: ProgressIndicatorThemeData(
            color: accent,
            circularTrackColor: trackDark,
            linearTrackColor: trackDark,
          ),
        ),
        themeMode:
            uiController.darkMode.value ? ThemeMode.dark : ThemeMode.light,
      );
    });
  }
}
