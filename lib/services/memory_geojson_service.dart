import 'dart:convert';
import 'dart:math';

/// Service for converting memories to GeoJSON format for MapBox native clustering
class MemoryGeoJsonService {
  /// Convert memories to GeoJSON FeatureCollection for MapBox clustering
  static String createGeoJsonFromMemories(List<Map<String, dynamic>> memories) {
    final features = <Map<String, dynamic>>[];

    for (final memory in memories) {
      final lat = memory['location_latitude'] as double?;
      final lng = memory['location_longitude'] as double?;

      if (lat == null || lng == null) continue;

      // Extract memory properties for styling and interaction
      final memoryDate =
          DateTime.tryParse(memory['date'] ?? '') ?? DateTime.now();
      final year = memoryDate.year;
      final category = memory['category'] as String? ?? 'general';
      final description =
          memory['text'] as String? ?? memory['description'] as String? ?? '';
      final images = memory['images'] as List<dynamic>? ?? [];
      final audios = memory['audios'] as List<dynamic>? ?? [];

  var endDate = DateTime.tryParse(memory['date'] ?? '') ?? DateTime.now();
      final toMemoryYear = endDate.year; // e.g., 2023

      print('🛑🛑🛑🛑🛑 checcking geo js');

      print('🛑🛑🛑🛑🛑ColorsExpressionData Results for year $year ${colors[getColorIndexForYear(year)]}');
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
          'color_index': getColorIndexForYear(year),
          'memory_timestamp': memoryDate.millisecondsSinceEpoch,
          'has_audios': audios.isNotEmpty,
          'color': colors[getColorIndexForYear(year)],
          'image_count': images.length,
          'audio_count': audios.length,
          'location_name': memory['location_name'] ?? '',
          'location_address': memory['location_address'] ?? '',
          'location_city': memory['location_city'] ?? '',
          'location_country': memory['location_country'] ?? '',
          // 'color_index': getColorIndexForYear(year),
          'memory_data': memory,
          'toMemoryYear': toMemoryYear,
        },
      };

      features.add(feature);
    }

    final geoJson = {'type': 'FeatureCollection', 'features': features};

    return jsonEncode(geoJson);
  }

  /// Get color index for year-based styling (matches map controller exactly)
  static int getColorIndexForYear(int year) {
    // Use current year as base year (matches map controller)
    final baseYear = DateTime.now().year;
    const colorCount = 20; // Match existing 20-color system
    final yearDifference = year - baseYear;
    return (yearDifference % colorCount).abs();
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
            (arrow['toDate'] as DateTime).year,
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
            (arrow['toDate'] as DateTime).year,
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
