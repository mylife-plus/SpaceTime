import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Service for converting memories to GeoJSON format for MapBox native clustering
class MemoryGeoJsonService {
  /// Convert memories to GeoJSON FeatureCollection for MapBox clustering
  static String createGeoJsonFromMemories(List<Map<String, dynamic>> memories) {
    final features = <Map<String, dynamic>>[];

    // Calculate the latest memory year to use as base for color mapping
    final baseYear = getLatestMemoryYear(memories);
    print('🎨 Using latest memory year as base: $baseYear');

    for (final memory in memories) {
      final lat = memory['location_latitude'] as double?;
      final lng = memory['location_longitude'] as double?;

      if (lat == null || lng == null) continue;
      print('Memory Year ${memory['year']}');
      // Extract memory properties for styling and interaction
      final memoryDate =
          DateTime.tryParse('${memory['memory_date']} ${ memory['year']}' ?? '') ?? DateTime.now();
      final year = memory['year'].toString();
      final category = memory['category'] as String? ?? 'general';
      final description =
          memory['text'] as String? ?? memory['description'] as String? ?? '';
      final images = memory['images'] as List<dynamic>? ?? [];
      final audios = memory['audios'] as List<dynamic>? ?? [];

  var endDate = DateTime.tryParse(memory['date'] ?? '') ?? DateTime.now();
      // final toMemoryYear = endDate.year; // e.g., 2023


      print('🛑🛑🛑🛑🛑 checcking geo js');

      print('🛑🛑🛑🛑🛑ColorsExpressionData Results for year ${int.parse(year)} ${colors[getColorIndexForYear(int.parse(year), DateTime.now().year)]}');
      // Create GeoJSON feature
      final feature = {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [lng, lat], // GeoJSON uses [lng, lat] order
        },
        'properties': {
          'id': '${memory['id']},',
          'year': year,
          'category': category,
          'description': description,
          'memory_date': memory['date'],
          'has_images': images.isNotEmpty,
          'timestamp': memoryDate.millisecondsSinceEpoch, // 👈 ADD
          'color_index': getColorIndexForYear(int.parse(year),  DateTime.now().year),
          'memory_timestamp': memoryDate.millisecondsSinceEpoch,
          'has_audios': audios.isNotEmpty,
          'color': colors[getColorIndexForYear(int.parse(year), DateTime.now().year)],
          'image_count': images.length,
          'audio_count': audios.length,
          'location_name': memory['location_name'] ?? '',
          'location_address': memory['location_address'] ?? '',
          'location_city': memory['location_city'] ?? '',
          'location_country': memory['location_country'] ?? '',
          // 'color_index': getColorIndexForYear(year),
          'memory_data': memory,
          'toMemoryYear': int.parse(year),
        },
      };

      features.add(feature);
    }

    final geoJson = {'type': 'FeatureCollection', 'features': features};

    return jsonEncode(geoJson);
  }

  /// Static cache for year-to-color-index mappings (initialized once per app launch)
  static Map<int, int>? _yearColorIndexCache;
  static int? _cacheBaseYear;
  static bool _isInitialized = false;

  /// Initialize the year-to-color-index cache for at least 100 previous years
  /// This should be called ONCE at app launch in main.dart
  static void initializeYearColorIndexCache({int? baseYear}) {
    final base = baseYear ?? DateTime.now().year;

    // If already initialized with the same base year, skip
    if (_isInitialized && _cacheBaseYear == base) {
      debugPrint('🎨 Year color index cache already initialized with base year $base, skipping...');
      return;
    }

    // If base year changed, re-initialize
    if (_isInitialized && _cacheBaseYear != base) {
      debugPrint('🎨 Base year changed from $_cacheBaseYear to $base, re-initializing cache...');
    }

    debugPrint('🎨 Initializing year color index cache with base year: $base');

    _yearColorIndexCache = {};
    _cacheBaseYear = base;
    const colorCount = 20; // Match existing 20-color system

    // Pre-calculate for 100 years before and 20 years after base year
    for (int year = base - 100; year <= base + 20; year++) {
      final yearDifference = year - base;
      final colorIndex = (yearDifference % colorCount).abs();
      _yearColorIndexCache![year] = colorIndex;
    }

    _isInitialized = true;
    debugPrint('🎨 Year color index cache initialized with ${_yearColorIndexCache!.length} entries (${base - 100} to ${base + 20})');
  }

  /// Get color index for year-based styling (matches map controller exactly)
  /// [year] - The year to get the color index for
  /// [baseYear] - Optional base year to use for color mapping. If null, uses cached base year.
  static int getColorIndexForYear(int year, int? baseYear) {
    // If baseYear is provided and different from cached base year, re-initialize
    if (baseYear != null && baseYear != _cacheBaseYear) {
      debugPrint('🎨 Base year mismatch: cached=$_cacheBaseYear, requested=$baseYear. Re-initializing...');
      initializeYearColorIndexCache(baseYear: baseYear);
    }

    // Ensure cache is initialized (fallback in case it wasn't called at app launch)
    if (!_isInitialized) {
      debugPrint('⚠️ Year color index cache not initialized! Initializing now...');
      initializeYearColorIndexCache(baseYear: baseYear);
    }

    // Try to get from cache first
    if (_yearColorIndexCache!.containsKey(year)) {
      return _yearColorIndexCache![year]!;
    }

    // If year is not in cache (outside the pre-calculated range), calculate on-the-fly
    final base = _cacheBaseYear ?? DateTime.now().year;
    const colorCount = 20;
    final yearDifference = year - base;
    final colorIndex = (yearDifference % colorCount).abs();

    // Add to cache for future use
    _yearColorIndexCache![year] = colorIndex;
    debugPrint('🎨 Added year $year to cache (color index: $colorIndex)');

    return colorIndex;
  }

  /// Get the latest (most recent) year from a list of memories
  /// Returns null if no valid years found
  static int? getLatestMemoryYear(List<Map<String, dynamic>> memories) {
    int? latestYear;

    for (final memory in memories) {
      final yearStr = memory['year'] as String?;
      if (yearStr != null && yearStr.isNotEmpty) {
        try {
          final year = int.parse(yearStr);
          if (latestYear == null || year > latestYear) {
            latestYear = year;
          }
        } catch (e) {
          // Skip invalid year values
        }
      }
    }

    return latestYear;
  }

  static const colors = [
      '#2196F3', // Blue
      '#4CAF50', // Green
      '#FF9800', // Orange
      '#9C27B0', // Purple
      '#F44336', // Red
      '#00BCD4', // Cyan
      '#FFEB3B', // Yellow
      '#795548', // Brown
      '#607D8B', // Blue Grey
      '#E91E63', // Pink
      '#3F51B5', // Indigo
      '#009688', // Teal
      '#FF5722', // Deep Orange
      '#8BC34A', // Light Green
      '#CDDC39', // Lime
      '#FFC107', // Amber
      '#673AB7', // Deep Purple
      '#00E676', // Green Accent
      '#FF1744', // Red Accent
      '#2979FF', // Blue Accent
    ];

  /// Create year-based color expression for MapBox styling
  static List<dynamic> createYearColorExpression() {
    // MapBox expression for year-based colors
    // Uses the exact same 20-color system as map controller
    

    final List<dynamic> expression = ['case'];

    for (int i = 0; i < colors.length; i++) {
      expression.addAll([
        [
          '==',
          ['get', 'color_index'],
          i,
        ],
        colors[i],
      ]);
    }

    // Default color if no match
    expression.add('#808080');

    return expression;
  }

  static List<dynamic> createIndividualMarkerSizeExpression() {
    return [
      'case',
      [
        '>',
        ['get', 'image_count'],
        5,
      ],
      40, // Bigger marker if more than 5 images
      [
        '>',
        ['get', 'image_count'],
        0,
      ],
      40, // Medium if has some images
      40, // Default size
    ];
  }

  /// Create cluster size-based radius expression (uniform size for all clusters)
  static int createClusterRadius() {
    return 40; // Fixed size for all clusters regardless of point count
  }

  /// Create cluster size-based color expression
  static List<dynamic> createClusterColorExpression() {
    return [
      'step',
      ['get', 'point_count'],
      '#4CAF50', // Green for small clusters (2-9)
      10,
      '#FF9800', // Orange for medium clusters (10-49)
      50,
      '#F44336', // Red for large clusters (50+)
    ];
  }

  /// Extract memories from GeoJSON for arrow generation
  static List<Map<String, dynamic>> extractMemoriesFromGeoJson(
    String geoJsonString,
  ) {
    final geoJson = jsonDecode(geoJsonString) as Map<String, dynamic>;
    final features = geoJson['features'] as List<dynamic>;

    return features.map((feature) {
      final properties = feature['properties'] as Map<String, dynamic>;
      return properties['memory_data'] as Map<String, dynamic>;
    }).toList();
  }

  /// Create chronological arrows from memories (earliest to latest)
  static List<Map<String, dynamic>> createChronologicalArrows(
    List<Map<String, dynamic>> memories,
  ) {
    if (memories.length < 2) return [];

    // Sort memories by date (earliest to latest)
    final sortedMemories = List<Map<String, dynamic>>.from(memories);
    sortedMemories.sort((a, b) {
      final dateA = DateTime.tryParse(a['memory_date'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['memory_date'] ?? '') ?? DateTime.now();
      return dateA.compareTo(dateB);
    });

    final arrows = <Map<String, dynamic>>[];

    // Create arrows between consecutive memories
    for (int i = 0; i < sortedMemories.length - 1; i++) {
      final currentMemory = sortedMemories[i];
      final nextMemory = sortedMemories[i + 1];

      final currentLat = currentMemory['location_latitude'] as double?;
      final currentLng = currentMemory['location_longitude'] as double?;
      final nextLat = nextMemory['location_latitude'] as double?;
      final nextLng = nextMemory['location_longitude'] as double?;

      if (currentLat == null ||
          currentLng == null ||
          nextLat == null ||
          nextLng == null) {
        continue;
      }

      final currentDate =
          DateTime.tryParse(currentMemory['memory_date'] ?? '') ??
          DateTime.now();
      final nextDate =
          DateTime.tryParse(nextMemory['memory_date'] ?? '') ?? DateTime.now();

      arrows.add({
        'fromLatitude': currentLat,
        'fromLongitude': currentLng,
        'toLatitude': nextLat,
        'toLongitude': nextLng,
        'fromDate': currentDate,
        'toDate': nextDate,
        'fromMemoryId': currentMemory['id'],
        'toMemoryId': nextMemory['id'],
      });
    }

    return arrows;
  }

  /// Create GeoJSON for chronological arrows (for line layers)
  static String createArrowLinesGeoJson(List<Map<String, dynamic>> arrows) {
    final features = <Map<String, dynamic>>[];

    for (int i = 0; i < arrows.length; i++) {
      final arrow = arrows[i];

      final feature = {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [arrow['fromLongitude'], arrow['fromLatitude']],
            [arrow['toLongitude'], arrow['toLatitude']],
          ],
        },
        'properties': {
          'arrow_id': 'arrow_$i',
          'from_memory_id': arrow['fromMemoryId'],
          'to_memory_id': arrow['toMemoryId'],
          'from_date': (arrow['fromDate'] as DateTime).toIso8601String(),
          'to_date': (arrow['toDate'] as DateTime).toIso8601String(),
          'year': (arrow['toDate'] as DateTime).year,
          'color_index': getColorIndexForYear(
            (arrow['toDate'] as DateTime).year, DateTime.now().year
          ),
        },
      };

      features.add(feature);
    }

    final geoJson = {'type': 'FeatureCollection', 'features': features};

    return jsonEncode(geoJson);
  }

  /// Create GeoJSON for arrow heads (point markers at arrow tips)
  static String createArrowHeadsGeoJson(List<Map<String, dynamic>> arrows) {
    final features = <Map<String, dynamic>>[];

    for (int i = 0; i < arrows.length; i++) {
      final arrow = arrows[i];

      // Calculate arrow head position (80% along the line, like in map controller)
      const t = 0.8;
      final fromLat = arrow['fromLatitude'] as double;
      final fromLng = arrow['fromLongitude'] as double;
      final toLat = arrow['toLatitude'] as double;
      final toLng = arrow['toLongitude'] as double;

      final arrowHeadLat = fromLat + (toLat - fromLat) * t;
      final arrowHeadLng = fromLng + (toLng - fromLng) * t;

      // Calculate bearing for arrow rotation
      final bearing = _calculateBearing(fromLat, fromLng, toLat, toLng);

      final feature = {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [arrowHeadLng, arrowHeadLat],
        },
        'properties': {
          'arrow_head_id': 'arrow_head_$i',
          'arrow_id': 'arrow_$i',
          'bearing': bearing,
          'year': (arrow['toDate'] as DateTime).year,
          'color_index': getColorIndexForYear(
            (arrow['toDate'] as DateTime).year, DateTime.now().year,
          ),
          'from_memory_id': arrow['fromMemoryId'],
          'to_memory_id': arrow['toMemoryId'],
        },
      };

      features.add(feature);
    }

    final geoJson = {'type': 'FeatureCollection', 'features': features};

    return jsonEncode(geoJson);
  }

  /// Calculate bearing between two points (for arrow rotation)
  static double _calculateBearing(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLng = (lng2 - lng1) * (3.14159265359 / 180.0);
    final lat1Rad = lat1 * (3.14159265359 / 180.0);
    final lat2Rad = lat2 * (3.14159265359 / 180.0);

    final y = sin(dLng) * cos(lat2Rad);
    final x =
        cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLng);

    final bearing = atan2(y, x) * (180.0 / 3.14159265359);
    return (bearing + 360.0) % 360.0;
  }

  /// Create line width expression for arrows
  static double createArrowLineWidth() {
    return 5.0; // Fixed width like in map controller
  }

  /// Create line color expression for arrows (based on year)
  static List<dynamic> createArrowLineColorExpression() {
    return createYearColorExpression(); // Use same color logic as markers
  }

  /// Create arrow line opacity expression
  static double createArrowLineOpacity() {
    return 1.0; // Full opacity like in map controller
  }

  /// Create shadow line width expression (for line shadows)
  static double createShadowLineWidth() {
    return 7.0; // Main line width + 2 (like in map controller)
  }

  /// Create shadow line color expression
  static String createShadowLineColor() {
    return '#000000'; // Black shadow
  }

  /// Create shadow line opacity expression
  static double createShadowLineOpacity() {
    return 0.20; // 20% opacity like in map controller
  }
}
