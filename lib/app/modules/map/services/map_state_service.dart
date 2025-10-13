import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

/// Service responsible for managing map state and reactive variables
class MapStateService extends GetxService {
  // Core map state
  final annotations = <mapbox.PointAnnotation>[].obs;
  final isFilterOpen = false.obs;
  final hasInitialized = false.obs;
  final isShowingNewLocations = false.obs;
  final currentZoom = 0.3.obs;
  final isMapReady = false.obs;
  final isRefreshing = false.obs;

  // Location and filter state
  final locations = <mapbox.Position>[].obs;
  final fromDate = ''.obs;
  final toDate = ''.obs;
  final locationRadius = ''.obs;
  final placeSearch = ''.obs;
  final hashtagSearch = ''.obs;
  final contactSearch = ''.obs;
  final selectedLocation = ''.obs;
  final filterValues = <String, String>{}.obs;

  // User's current location for initial map center
  final userCurrentLocation = mapbox.Position(0, 0).obs;

  // Map recreation state
  final shouldRecreateMap = false.obs;
  var _mapRecreationCount = 0;
  var _hasTriggeredRecreation = false;

  // Add flag to prevent reactive zoom during location transitions
  var _isTransitioningLocations = false;

  // Timers
  Timer? _oneTimeRecreationTimer;

  // Predefined colors for memory markers (20 colors)
  final List<Color> markerColors = [
    const Color(0xFF2196F3), // Blue
    const Color(0xFF4CAF50), // Green
    const Color(0xFFFF9800), // Orange
    const Color(0xFF9C27B0), // Purple
    const Color(0xFFF44336), // Red
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFFFFEB3B), // Yellow
    const Color(0xFF795548), // Brown
    const Color(0xFF607D8B), // Blue Grey
    const Color(0xFFE91E63), // Pink
    const Color(0xFF3F51B5), // Indigo
    const Color(0xFF009688), // Teal
    const Color(0xFFFF5722), // Deep Orange
    const Color(0xFF8BC34A), // Light Green
    const Color(0xFFCDDC39), // Lime
    const Color(0xFFFFC107), // Amber
    const Color(0xFF673AB7), // Deep Purple
    const Color(0xFF00E676), // Green Accent
    const Color(0xFFFF1744), // Red Accent
    const Color(0xFF2979FF), // Blue Accent
  ];

  // Base year for color mapping (current year)
  final int baseYear = DateTime.now().year;

  @override
  void onClose() {
    _oneTimeRecreationTimer?.cancel();
    super.onClose();
  }

  /// Get color for a specific year
  /// Maps years to colors in a repeating cycle of 20 colors
  /// Covers past 50 years and next 50 years from current year
  Color getColorForYear(int year) {
    // Calculate the difference from base year
    final yearDifference = year - baseYear;

    // Map to a positive index within our 20-color range
    // This ensures consistent color mapping for the same year
    final colorIndex = (yearDifference % markerColors.length).abs();

    return markerColors[colorIndex];
  }

  /// Get all year-color mappings for a range of years
  /// Useful for displaying color legends or year filters
  Map<int, Color> getYearColorMappings({
    int startYear = -50,
    int endYear = 50,
  }) {
    final Map<int, Color> yearColorMap = {};

    for (int i = startYear; i <= endYear; i++) {
      final year = baseYear + i;
      yearColorMap[year] = getColorForYear(year);
    }

    return yearColorMap;
  }

  /// Get years that use a specific color
  /// Useful for filtering memories by color
  List<int> getYearsForColor(
    Color color, {
    int startYear = -50,
    int endYear = 50,
  }) {
    final List<int> years = [];

    for (int i = startYear; i <= endYear; i++) {
      final year = baseYear + i;
      if (getColorForYear(year) == color) {
        years.add(year);
      }
    }

    return years;
  }

  /// Get color index for a year (0-19)
  /// Useful for consistent indexing
  int getColorIndexForYear(int year) {
    final yearDifference = year - baseYear;
    return (yearDifference % markerColors.length).abs();
  }

  /// Set filter date
  void setFilterDate(String hint, String date) {
    filterValues[hint] = date;
  }

  /// Handle text changes for filters
  void onTextChanged(String hint, String value) {
    if (value.contains('@')) {
      // open mention bottom sheet
      debugPrint("[MapStateService] Mention trigger from [$hint]: $value");
    } else if (value.contains('#')) {
      // open tag bottom sheet
      debugPrint("[MapStateService] Tag trigger from [$hint]: $value");
    }
    filterValues[hint] = value;
  }

  /// Set location
  void setLocation(String location) {
    selectedLocation.value = location;
    debugPrint("[MapStateService] Location set to: $location");
  }

  /// Toggle filter state
  void toggleFilter() => isFilterOpen.toggle();

  /// Open filter
  void openFilter() => isFilterOpen.value = true;

  /// Close filter
  void closeFilter() => isFilterOpen.value = false;

  /// Schedule one-time recreation
  void scheduleOneTimeRecreation() {
    debugPrint('[MapStateService] Starting recreation scheduling');
    debugPrint(
      '[MapStateService] _hasTriggeredRecreation: $_hasTriggeredRecreation',
    );
    debugPrint(
      '[MapStateService] _oneTimeRecreationTimer null: ${_oneTimeRecreationTimer == null}',
    );

    if (_hasTriggeredRecreation) {
      debugPrint('[MapStateService] Already triggered, skipping');
      return;
    }

    debugPrint('[MapStateService] Scheduling recreation in 100ms');
    debugPrint(
      '[MapStateService] Current time: ${DateTime.now().millisecondsSinceEpoch}',
    );

    // Note: Timer is commented out in original code, keeping the same behavior
  }

  /// Trigger map recreation to simulate restart behavior
  void triggerMapRecreation() {
    _mapRecreationCount++;
    debugPrint('[MapStateService] Starting recreation #$_mapRecreationCount');
    debugPrint('[MapStateService] Current state before recreation:');
    debugPrint(
      '[MapStateService]   - annotations count: ${annotations.length}',
    );
    debugPrint('[MapStateService]   - hasInitialized: ${hasInitialized.value}');
    debugPrint('[MapStateService]   - isMapReady: ${isMapReady.value}');
    debugPrint(
      '[MapStateService]   - shouldRecreateMap: ${shouldRecreateMap.value}',
    );

    // Toggle the recreation flag to force MapWidget rebuild
    final previousValue = shouldRecreateMap.value;
    shouldRecreateMap.value = !shouldRecreateMap.value;
    debugPrint(
      '[MapStateService] shouldRecreateMap toggled from $previousValue to ${shouldRecreateMap.value}',
    );

    // Reset map state
    debugPrint('[MapStateService] Resetting map state...');
    annotations.clear();
    hasInitialized.value = false;
    isMapReady.value = false;

    debugPrint('[MapStateService] State after reset:');
    debugPrint(
      '[MapStateService]   - annotations count: ${annotations.length}',
    );
    debugPrint('[MapStateService]   - hasInitialized: ${hasInitialized.value}');
    debugPrint('[MapStateService]   - isMapReady: ${isMapReady.value}');
    debugPrint(
      '[MapStateService] Map state reset complete, MapWidget will rebuild',
    );
  }

  /// Public method to manually trigger map recreation (for testing)
  void recreateMap() {
    debugPrint('🔄 PUBLIC - Manual map recreation triggered');
    triggerMapRecreation();
  }

  /// Reset to original locations
  Future<void> resetToOriginalLocations() async {
    debugPrint('[MapStateService] Starting reset to original locations');
    debugPrint('[MapStateService] Current state before reset:');
    debugPrint(
      '[MapStateService]   - _isTransitioningLocations: $_isTransitioningLocations',
    );
    debugPrint(
      '[MapStateService]   - annotations count: ${annotations.length}',
    );
    debugPrint('[MapStateService]   - locations count: ${locations.length}');
    debugPrint('[MapStateService]   - currentZoom: ${currentZoom.value}');
    debugPrint('[MapStateService]   - isMapReady: ${isMapReady.value}');

    // Set transition flag to prevent reactive zoom conflicts
    debugPrint('[MapStateService] Setting transition flag to true');
    _isTransitioningLocations = true;
    debugPrint(
      '[MapStateService] _isTransitioningLocations set to: $_isTransitioningLocations',
    );

    try {
      // Clear existing annotations
      debugPrint('[MapStateService] Clearing annotations list');
      annotations.clear();

      // Reset to original locations (empty in this case)
      locations.clear();
      locations.addAll([]);

      // Reset state flags
      isShowingNewLocations.value = false;
      final newZoomLevel = 1.6 - 0.8; // Calculate the zoomed out level
      currentZoom.value = newZoomLevel;

      debugPrint('🔄 RESET - Updated currentZoom to: ${currentZoom.value}');
      debugPrint('🔄 RESET - Original locations and zoom restored');
    } catch (e) {
      debugPrint('Error resetting to original locations: $e');
    } finally {
      _isTransitioningLocations = false;
      debugPrint('🔄 RESET - Reset complete, reactive zoom enabled');
    }
  }

  /// Check if currently transitioning locations
  bool get isTransitioningLocations => _isTransitioningLocations;

  /// Set transitioning locations state
  void setTransitioningLocations(bool value) {
    _isTransitioningLocations = value;
  }

  /// Get map recreation count
  int get mapRecreationCount => _mapRecreationCount;

  /// Check if recreation has been triggered
  bool get hasTriggeredRecreation => _hasTriggeredRecreation;

  /// Set recreation triggered state
  void setRecreationTriggered(bool value) {
    _hasTriggeredRecreation = value;
  }

  /// Reset all state to initial values
  void resetState() {
    annotations.clear();
    isFilterOpen.value = false;
    hasInitialized.value = false;
    isShowingNewLocations.value = false;
    currentZoom.value = 0.3;
    isMapReady.value = false;
    isRefreshing.value = false;

    locations.clear();
    fromDate.value = '';
    toDate.value = '';
    locationRadius.value = '';
    placeSearch.value = '';
    hashtagSearch.value = '';
    contactSearch.value = '';
    selectedLocation.value = '';
    filterValues.clear();

    userCurrentLocation.value = mapbox.Position(0, 0);
    shouldRecreateMap.value = false;
    _mapRecreationCount = 0;
    _hasTriggeredRecreation = false;
    _isTransitioningLocations = false;

    debugPrint('[MapStateService] All state reset to initial values');
  }

  /// Initialize state with default values
  void initializeState() {
    debugPrint('[MapStateService] Initializing state with default values');

    // Set any default values here if needed
    currentZoom.value = 0.3;
    userCurrentLocation.value = mapbox.Position(0, 0);

    debugPrint('[MapStateService] State initialized');
  }

  /// Get current state summary for debugging
  Map<String, dynamic> getStateSummary() {
    return {
      'annotations_count': annotations.length,
      'is_filter_open': isFilterOpen.value,
      'has_initialized': hasInitialized.value,
      'is_showing_new_locations': isShowingNewLocations.value,
      'current_zoom': currentZoom.value,
      'is_map_ready': isMapReady.value,
      'is_refreshing': isRefreshing.value,
      'locations_count': locations.length,
      'selected_location': selectedLocation.value,
      'filter_values_count': filterValues.length,
      'should_recreate_map': shouldRecreateMap.value,
      'map_recreation_count': _mapRecreationCount,
      'has_triggered_recreation': _hasTriggeredRecreation,
      'is_transitioning_locations': _isTransitioningLocations,
    };
  }
}
