import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_text.dart';

/// Service for creating styled map markers with consistent design patterns
/// Based on the styling from MapController with enhanced reusability
class MapMarkerCreationService extends GetxService {
  static MapMarkerCreationService get instance =>
      Get.find<MapMarkerCreationService>();

  // Predefined colors for memory markers (20 colors) - same as MapController
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

  /// Get color for a specific year
  /// Maps years to colors in a repeating cycle of 20 colors
  Color getColorForYear(int year) {
    final yearDifference = year - baseYear;
    final colorIndex = (yearDifference % markerColors.length).abs();
    return markerColors[colorIndex];
  }

  /// Get color for memory based on its year
  Color getColorForMemoryYear(DateTime memoryDate) {
    return getColorForYear(memoryDate.year);
  }

  /// Get color index for a year (0-19)
  int getColorIndexForYear(int year) {
    final yearDifference = year - baseYear;
    return (yearDifference % markerColors.length).abs();
  }

  /// Get color name for a year (for debugging/display)
  String getColorNameForYear(int year) {
    return AppTexts.paletteColorNameForYear(year, baseYear);
  }

  /// Create a cluster marker image with consistent styling
  ///
  /// Parameters:
  /// - [memoryCount]: Number of memories in the cluster
  /// - [isSingleMemory]: Whether this is a single memory or cluster
  /// - [memoryDate]: Date of the memory (for color selection)
  /// - [clusterId]: Unique identifier for the cluster
  /// - [size]: Size of the marker (default: 60.0)
  Future<Uint8List> createClusterMarkerImage({
    required int memoryCount,
    required bool isSingleMemory,
    required DateTime memoryDate,
    required String clusterId,
    double size = 60.0,
  }) async {
    try {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final radius = size / 2;

      debugPrint(
        '[MapMarkerCreationService] Creating cluster marker: count=$memoryCount, single=$isSingleMemory, id=$clusterId',
      );

      // Choose color based on memory date for consistent year-based coloring
      Color markerColor = getColorForMemoryYear(memoryDate);
      Color borderColor = Colors.white;
      double borderWidth = 3.0;

      if (!isSingleMemory) {
        // Group markers have distinct styling
        borderWidth = 2.0;
        borderColor = const Color.fromARGB(255, 255, 255, 255); // Gold border for groups
      }

      // Fill the entire canvas with transparent background
      final backgroundPaint = Paint()..color = Colors.transparent;
      canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

      // Draw outer ring for group markers
      if (!isSingleMemory) {
        final outerPaint =
            Paint()
              ..color = borderColor.withValues(alpha: 0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6.0;
        canvas.drawCircle(Offset(radius, radius), radius - 3, outerPaint);
      }

      // Draw main circle
      final paint =
          Paint()
            ..color = markerColor
            ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(radius, radius), radius - 6, paint);

      // Add border
      final border =
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth;
      canvas.drawCircle(Offset(radius, radius), radius - 6, border);

      // Draw count text - make it more prominent
      final fontSize =
          memoryCount > 99
              ? 10.0
              : memoryCount > 9
              ? 12.0
              : 14.0;

      final textPainter = TextPainter(
        text: TextSpan(
          text: isSingleMemory ? '1' : memoryCount.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            shadows: [
              const Shadow(
                offset: Offset(0.5, 0.5),
                blurRadius: 1,
                color: Colors.black87,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout();

      // Center the text in the circle
      final textOffset = Offset(
        radius - textPainter.width / 2,
        radius - textPainter.height / 2,
      );

      textPainter.paint(canvas, textOffset);

      // Add cluster indicator dots for groups
      if (!isSingleMemory && memoryCount > 1) {
        final indicatorPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.8)
              ..style = PaintingStyle.fill;

        // Draw small dots around the marker to indicate it's a cluster
        const dotRadius = 1.5;
        final dotDistance = radius - 10;
        final dotCount = memoryCount > 10 ? 8 : 6;

        for (int i = 0; i < dotCount; i++) {
          final angle = (i * (360 / dotCount)) * (pi / 180);
          final x = radius + cos(angle) * dotDistance;
          final y = radius + sin(angle) * dotDistance;
          canvas.drawCircle(Offset(x, y), dotRadius, indicatorPaint);
        }
      }

      final picture = recorder.endRecording();

      // Ensure size is valid
      final imageSize = size.toInt();
      if (imageSize <= 0) {
        throw Exception('Invalid image size: $imageSize');
      }

      final image = await picture.toImage(imageSize, imageSize);
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to create image byte data');
      }

      final imageBytes = byteData.buffer.asUint8List();
      debugPrint(
        '✅ Created cluster marker image: ${imageBytes.length} bytes, ${imageSize}x${imageSize}px',
      );

      return imageBytes;
    } catch (e) {
      debugPrint('❌ Error creating cluster marker image: $e');
      // Return a simple fallback image
      return _createSimpleFallbackMarkerImage(memoryCount, size);
    }
  }

  /// Create a simple fallback marker image when main creation fails
  Future<Uint8List> _createSimpleFallbackMarkerImage(
    int count,
    double size,
  ) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 2;

    // Draw simple circle
    final paint =
        Paint()
          ..color = const Color(0xFF2196F3)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(radius, radius), radius - 5, paint);

    // Draw border
    final border =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    canvas.drawCircle(Offset(radius, radius), radius - 5, border);

    // Draw count text
    final textPainter = TextPainter(
      text: TextSpan(
        text: count == 1 ? '1' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  /// Create an arrow head image for chronological arrows
  ///
  /// Parameters:
  /// - [colorValue]: Color value for the arrow (default: green)
  /// - [size]: Size of the arrow head (default: 24)
  Future<Uint8List> createArrowHeadImage({
    int colorValue = 0xFF2E7D32,
    int size = 24,
  }) async {
    try {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      // Fill background with transparent
      final backgroundPaint = Paint()..color = Colors.transparent;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        backgroundPaint,
      );

      final paint =
          Paint()
            ..color = Color(colorValue)
            ..style = PaintingStyle.fill;

      // Draw arrow head triangle pointing right (east) with better proportions
      final path = Path();
      path.moveTo(size * 0.85, size * 0.5); // Sharp point (rightmost)
      path.lineTo(size * 0.15, size * 0.15); // Top left
      path.lineTo(size * 0.35, size * 0.5); // Middle left (creates shaft)
      path.lineTo(size * 0.15, size * 0.85); // Bottom left
      path.close();

      canvas.drawPath(path, paint);

      // Add white border for better visibility and definition
      final borderPaint =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
      canvas.drawPath(path, borderPaint);

      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('❌ Failed to create arrow head image data');
        return Uint8List(0);
      }

      final imageBytes = byteData.buffer.asUint8List();
      debugPrint(
        '✅ Created arrow head image: ${imageBytes.length} bytes, ${size}x${size}px',
      );
      return imageBytes;
    } catch (e) {
      debugPrint('❌ Error creating arrow head image: $e');
      return Uint8List(0);
    }
  }

  /// Create a simple circular marker with custom color
  ///
  /// Parameters:
  /// - [color]: Color of the marker
  /// - [size]: Size of the marker (default: 40.0)
  /// - [text]: Optional text to display in the marker
  /// - [borderColor]: Border color (default: white)
  /// - [borderWidth]: Border width (default: 2.0)
  Future<Uint8List> createSimpleMarker({
    required Color color,
    double size = 40.0,
    String? text,
    Color borderColor = Colors.white,
    double borderWidth = 2.0,
  }) async {
    try {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final radius = size / 2;

      // Fill background with transparent
      final backgroundPaint = Paint()..color = Colors.transparent;
      canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

      // Draw main circle
      final paint =
          Paint()
            ..color = color
            ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(radius, radius), radius - borderWidth, paint);

      // Add border
      final border =
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth;
      canvas.drawCircle(Offset(radius, radius), radius - borderWidth, border);

      // Draw text if provided
      if (text != null && text.isNotEmpty) {
        final fontSize = text.length > 2 ? 10.0 : 12.0;
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              shadows: [
                const Shadow(
                  offset: Offset(0.5, 0.5),
                  blurRadius: 1,
                  color: Colors.black87,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );

        textPainter.layout();
        final textOffset = Offset(
          radius - textPainter.width / 2,
          radius - textPainter.height / 2,
        );
        textPainter.paint(canvas, textOffset);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      return byteData?.buffer.asUint8List() ?? Uint8List(0);
    } catch (e) {
      debugPrint('❌ Error creating simple marker: $e');
      return Uint8List(0);
    }
  }

  /// Create a location pin marker with custom styling
  ///
  /// Parameters:
  /// - [color]: Color of the pin
  /// - [size]: Size of the pin (default: 50.0)
  /// - [icon]: Optional icon to display in the pin
  Future<Uint8List> createLocationPinMarker({
    required Color color,
    double size = 50.0,
    IconData? icon,
  }) async {
    try {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final radius = size * 0.3;

      // Fill background with transparent
      final backgroundPaint = Paint()..color = Colors.transparent;
      canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

      // Draw pin shape
      final paint =
          Paint()
            ..color = color
            ..style = PaintingStyle.fill;

      final path = Path();
      // Pin body (circle)
      path.addOval(
        Rect.fromCircle(center: Offset(size / 2, size * 0.35), radius: radius),
      );
      // Pin point (triangle)
      path.moveTo(size / 2, size * 0.35 + radius);
      path.lineTo(size / 2 - radius * 0.3, size * 0.8);
      path.lineTo(size / 2 + radius * 0.3, size * 0.8);
      path.close();

      canvas.drawPath(path, paint);

      // Add border
      final border =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
      canvas.drawPath(path, border);

      // Draw icon if provided
      if (icon != null) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              fontSize: radius * 0.8,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );

        textPainter.layout();
        final iconOffset = Offset(
          size / 2 - textPainter.width / 2,
          size * 0.35 - textPainter.height / 2,
        );
        textPainter.paint(canvas, iconOffset);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      return byteData?.buffer.asUint8List() ?? Uint8List(0);
    } catch (e) {
      debugPrint('❌ Error creating location pin marker: $e');
      return Uint8List(0);
    }
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

  /// Debug method to print year-color mappings
  void debugPrintYearColorMappings() {
    debugPrint('📅 YEAR-COLOR MAPPINGS:');

    // Past years
    debugPrint('📜 PAST YEARS (${baseYear - 10} to ${baseYear - 1}):');
    for (int year = baseYear - 10; year < baseYear; year++) {
      final color = getColorForYear(year);
      final colorName = getColorNameForYear(year);
      final colorIndex = getColorIndexForYear(year);
      debugPrint(
        '  $year: $colorName (Index: $colorIndex, Color: ${color.toString()})',
      );
    }

    // Current year
    debugPrint('🎯 CURRENT YEAR:');
    final currentColor = getColorForYear(baseYear);
    final currentColorName = getColorNameForYear(baseYear);
    final currentColorIndex = getColorIndexForYear(baseYear);
    debugPrint(
      '  $baseYear: $currentColorName (Index: $currentColorIndex, Color: ${currentColor.toString()}) ⭐',
    );

    // Future years
    debugPrint('🔮 FUTURE YEARS (${baseYear + 1} to ${baseYear + 10}):');
    for (int year = baseYear + 1; year <= baseYear + 10; year++) {
      final color = getColorForYear(year);
      final colorName = getColorNameForYear(year);
      final colorIndex = getColorIndexForYear(year);
      debugPrint(
        '  $year: $colorName (Index: $colorIndex, Color: ${color.toString()})',
      );
    }
  }
}
