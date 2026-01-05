import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper class to manage all Mapbox zoom levels across the application
/// All zoom values are centralized here and loaded from preferences
class MapboxZoomHelper {
  // Singleton instance
  static final MapboxZoomHelper _instance = MapboxZoomHelper._internal();
  factory MapboxZoomHelper() => _instance;
  MapboxZoomHelper._internal();

  // SharedPreferences keys
  static const String _keyMinZoom = 'mapbox_min_zoom';
  static const String _keyMaxZoom = 'mapbox_max_zoom';
  static const String _keyClusterVisibilityMaxZoom = 'mapbox_cluster_visibility_max_zoom';
  static const String _keyIndividualVisibilityMinZoom = 'mapbox_individual_visibility_min_zoom';
  static const String _keyDetailVisibilityMinZoom = 'mapbox_detail_visibility_min_zoom';
  static const String _keyClusterMaxZoom = 'mapbox_cluster_max_zoom';
  static const String _keyInitialCameraZoom = 'mapbox_initial_camera_zoom';
  static const String _keyCurrentLocationZoom = 'mapbox_current_location_zoom';
  static const String _keyDefaultZoom = 'mapbox_default_zoom';
  static const String _keyCurrentZoomInitial = 'mapbox_current_zoom_initial';
  static const String _keyCurrentZoomAfterLocation = 'mapbox_current_zoom_after_location';

  // ============================================================================
  // DEFAULT VALUES (Fixed constants - will be stored in preferences on first run)
  // ============================================================================
  
  /// Minimum zoom level for vector sources and map (default: 0)
  static const double defaultMinZoom = 0.0;
  
  /// Maximum zoom level for vector sources and map (default: 10)
  /// Changed from 18 to 10 as per requirements
  static const double defaultMaxZoom = 18.0;
  
  /// Maximum zoom level for cluster visibility (default: 4.0)
  /// Clusters are hidden when zoomed in past this level
  /// Changed from 9.0 to 4.0 as per requirements
  static const double defaultClusterVisibilityMaxZoom = 4.0;
  
  /// Minimum zoom level for individual memory visibility (default: 4.0)
  /// Individual memories are shown when zoomed in past this level
  /// Changed from 9.0 to 4.0 as per requirements
  static const double defaultIndividualVisibilityMinZoom = 4.0;
  
  /// Minimum zoom level for detail visibility (default: 9.0)
  /// Detailed annotations are shown at this zoom level and above
  /// Changed from 12.0 to 9.0 as per requirements
  static const double defaultDetailVisibilityMinZoom = 9.0;
  
  /// Maximum zoom for clustering (default: 10.0)
  /// Changed from 14.0 to 10.0 as per requirements
  static const double defaultClusterMaxZoom = 11.0;
  
  /// Initial camera zoom level (default: 8.0)
  static const double defaultInitialCameraZoom = 8.0;
  
  /// Zoom level when showing current location (default: 9.0)
  /// Changed from 14.0 to 9.0 as per requirements
  static const double defaultCurrentLocationZoom = 9.0;
  
  /// Default zoom level (default: 10.0)
  static const double defaultDefaultZoom = 11.0;
  
  /// Initial current zoom value (default: 0.3)
  static const double defaultCurrentZoomInitial = 0.3;
  
  /// Current zoom after location is obtained (default: 1.6)
  static const double defaultCurrentZoomAfterLocation = 1.6;

  // ============================================================================
  // REACTIVE VALUES (Loaded from preferences)
  // ============================================================================
  
  final RxDouble minZoom = defaultMinZoom.obs;
  final RxDouble maxZoom = defaultMaxZoom.obs;
  final RxDouble clusterVisibilityMaxZoom = defaultClusterVisibilityMaxZoom.obs;
  final RxDouble individualVisibilityMinZoom = defaultIndividualVisibilityMinZoom.obs;
  final RxDouble detailVisibilityMinZoom = defaultDetailVisibilityMinZoom.obs;
  final RxDouble clusterMaxZoom = defaultClusterMaxZoom.obs;
  final RxDouble initialCameraZoom = defaultInitialCameraZoom.obs;
  final RxDouble currentLocationZoom = defaultCurrentLocationZoom.obs;
  final RxDouble defaultZoom = defaultDefaultZoom.obs;
  final RxDouble currentZoomInitial = defaultCurrentZoomInitial.obs;
  final RxDouble currentZoomAfterLocation = defaultCurrentZoomAfterLocation.obs;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================
  
  /// Initialize the helper - load values from preferences or set defaults
  /// This should be called from main() on app startup
  static Future<void> initialize() async {
    final instance = MapboxZoomHelper();
    final prefs = await SharedPreferences.getInstance();
    
    // Load or set default values
    instance.minZoom.value = prefs.getDouble(_keyMinZoom) ?? defaultMinZoom;
    instance.maxZoom.value = prefs.getDouble(_keyMaxZoom) ?? defaultMaxZoom;
    instance.clusterVisibilityMaxZoom.value = prefs.getDouble(_keyClusterVisibilityMaxZoom) ?? defaultClusterVisibilityMaxZoom;
    instance.individualVisibilityMinZoom.value = prefs.getDouble(_keyIndividualVisibilityMinZoom) ?? defaultIndividualVisibilityMinZoom;
    instance.detailVisibilityMinZoom.value = prefs.getDouble(_keyDetailVisibilityMinZoom) ?? defaultDetailVisibilityMinZoom;
    instance.clusterMaxZoom.value = prefs.getDouble(_keyClusterMaxZoom) ?? defaultClusterMaxZoom;
    instance.initialCameraZoom.value = prefs.getDouble(_keyInitialCameraZoom) ?? defaultInitialCameraZoom;
    instance.currentLocationZoom.value = prefs.getDouble(_keyCurrentLocationZoom) ?? defaultCurrentLocationZoom;
    instance.defaultZoom.value = prefs.getDouble(_keyDefaultZoom) ?? defaultDefaultZoom;
    instance.currentZoomInitial.value = prefs.getDouble(_keyCurrentZoomInitial) ?? defaultCurrentZoomInitial;
    instance.currentZoomAfterLocation.value = prefs.getDouble(_keyCurrentZoomAfterLocation) ?? defaultCurrentZoomAfterLocation;
    
    // If values don't exist in preferences, save the defaults
    if (!prefs.containsKey(_keyMinZoom)) {
      await instance._saveAllDefaults(prefs);
    }
    
    print('[MapboxZoomHelper] ✅ Initialized with values:');
    print('[MapboxZoomHelper] - Min Zoom: ${instance.minZoom.value}');
    print('[MapboxZoomHelper] - Max Zoom: ${instance.maxZoom.value}');
    print('[MapboxZoomHelper] - Cluster Visibility Max: ${instance.clusterVisibilityMaxZoom.value}');
    print('[MapboxZoomHelper] - Individual Visibility Min: ${instance.individualVisibilityMinZoom.value}');
    print('[MapboxZoomHelper] - Detail Visibility Min: ${instance.detailVisibilityMinZoom.value}');
    print('[MapboxZoomHelper] - Cluster Max Zoom: ${instance.clusterMaxZoom.value}');
    print('[MapboxZoomHelper] - Initial Camera Zoom: ${instance.initialCameraZoom.value}');
    print('[MapboxZoomHelper] - Current Location Zoom: ${instance.currentLocationZoom.value}');
  }

  /// Save all default values to preferences
  Future<void> _saveAllDefaults(SharedPreferences prefs) async {
    await prefs.setDouble(_keyMinZoom, defaultMinZoom);
    await prefs.setDouble(_keyMaxZoom, defaultMaxZoom);
    await prefs.setDouble(_keyClusterVisibilityMaxZoom, defaultClusterVisibilityMaxZoom);
    await prefs.setDouble(_keyIndividualVisibilityMinZoom, defaultIndividualVisibilityMinZoom);
    await prefs.setDouble(_keyDetailVisibilityMinZoom, defaultDetailVisibilityMinZoom);
    await prefs.setDouble(_keyClusterMaxZoom, defaultClusterMaxZoom);
    await prefs.setDouble(_keyInitialCameraZoom, defaultInitialCameraZoom);
    await prefs.setDouble(_keyCurrentLocationZoom, defaultCurrentLocationZoom);
    await prefs.setDouble(_keyDefaultZoom, defaultDefaultZoom);
    await prefs.setDouble(_keyCurrentZoomInitial, defaultCurrentZoomInitial);
    await prefs.setDouble(_keyCurrentZoomAfterLocation, defaultCurrentZoomAfterLocation);
    print('[MapboxZoomHelper] 💾 Saved default values to preferences');
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Clamp a zoom value to the min/max range
  double clampZoom(double zoom) {
    return zoom.clamp(minZoom.value, maxZoom.value);
  }

  /// Get zoom level based on radius (for location picker)
  /// Clamped to min/max zoom from preferences
  /// Updated to work with maxZoom of 11.0 and provide better zoom-to-radius mapping
  double getZoomForRadius(double radiusKm) {
    double zoom;

    // Optimized zoom levels for maxZoom = 11.0
    // Smaller radius = higher zoom (more zoomed in)
    // Larger radius = lower zoom (more zoomed out)
    
    if (radiusKm <= 1) {
      zoom = 11.0;  // Maximum zoom for very small radius
    } else if (radiusKm <= 2) {
      zoom = 10.5;
    } else if (radiusKm <= 5) {
      zoom = 10.0;
    } else if (radiusKm <= 10) {
      zoom = 9.0;
    } else if (radiusKm <= 20) {
      zoom = 8.0;
    } else if (radiusKm <= 30) {
      zoom = 7.5;
    } else if (radiusKm <= 50) {
      zoom = 7.0;
    } else if (radiusKm <= 75) {
      zoom = 6.5;
    } else if (radiusKm <= 100) {
      zoom = 6.0;
    } else if (radiusKm <= 150) {
      zoom = 5.5;
    } else if (radiusKm <= 200) {
      zoom = 5.0;
    } else {
      zoom = 4.0;  // Minimum zoom for very large radius
    }

    // Clamp to min/max zoom
    return clampZoom(zoom);
  }

  /// Get zoom level based on geographical spread (for memory distribution)
  /// Clamped to min/max zoom from preferences
  double getZoomForSpread(double maxDiff) {
    double zoom = defaultZoom.value;

    if (maxDiff > 10) {
      zoom = 2.0;
    } else if (maxDiff > 5) {
      zoom = 4.0;
    } else if (maxDiff > 1) {
      zoom = 6.0;
    } else if (maxDiff > 0.1) {
      zoom = 8.0;
    }

    // Clamp to min/max zoom
    return clampZoom(zoom);
  }

  // ============================================================================
  // UPDATE METHODS (for future UI configuration)
  // ============================================================================

  /// Update min zoom and save to preferences
  Future<void> updateMinZoom(double value) async {
    minZoom.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMinZoom, value);
    print('[MapboxZoomHelper] Updated min zoom to: $value');
  }

  /// Update max zoom and save to preferences
  Future<void> updateMaxZoom(double value) async {
    maxZoom.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMaxZoom, value);
    print('[MapboxZoomHelper] Updated max zoom to: $value');
  }

  /// Reset all values to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await _saveAllDefaults(prefs);

    // Update reactive values
    minZoom.value = defaultMinZoom;
    maxZoom.value = defaultMaxZoom;
    clusterVisibilityMaxZoom.value = defaultClusterVisibilityMaxZoom;
    individualVisibilityMinZoom.value = defaultIndividualVisibilityMinZoom;
    detailVisibilityMinZoom.value = defaultDetailVisibilityMinZoom;
    clusterMaxZoom.value = defaultClusterMaxZoom;
    initialCameraZoom.value = defaultInitialCameraZoom;
    currentLocationZoom.value = defaultCurrentLocationZoom;
    defaultZoom.value = defaultDefaultZoom;
    currentZoomInitial.value = defaultCurrentZoomInitial;
    currentZoomAfterLocation.value = defaultCurrentZoomAfterLocation;

    print('[MapboxZoomHelper] ✅ Reset all values to defaults');
  }
}

