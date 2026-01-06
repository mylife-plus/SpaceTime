import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Generates custom circular cluster icons with count numbers
class ClusterIconGenerator {
  /// Generate a circular cluster icon with a count number
  /// Returns the image as Uint8List (PNG format)
  static Future<Uint8List> generateClusterIcon({
    required int count,
    double size = 80.0,
    Color backgroundColor = const Color(0xFF51BBD6),
    Color textColor = Colors.white,
    Color strokeColor = Colors.white,
    double strokeWidth = 6.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - strokeWidth;

    // Draw outer stroke (white border)
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius + (strokeWidth / 2), strokePaint);

    // Draw filled circle (background)
    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // Draw count text
    final textSpan = TextSpan(
      text: count.toString(),
      style: TextStyle(
        color: textColor,
        fontSize: size * 0.35, // 35% of icon size
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.5),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    final textOffset = Offset(
      center.dx - (textPainter.width / 2),
      center.dy - (textPainter.height / 2),
    );
    textPainter.paint(canvas, textOffset);

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Generate cluster icons for different size ranges
  /// Returns a map of icon names to image data
  static Future<Map<String, Uint8List>> generateClusterIconSet({
    List<int> counts = const [2, 5, 10, 20, 50, 100],
    double size = 80.0,
  }) async {
    final icons = <String, Uint8List>{};

    for (final count in counts) {
      // Determine color based on count
      Color backgroundColor;
      if (count < 10) {
        backgroundColor = const Color(0xFF51BBD6); // Blue for small
      } else if (count < 50) {
        backgroundColor = const Color(0xFFFFA726); // Orange for medium
      } else {
        backgroundColor = const Color(0xFFEF5350); // Red for large
      }

      final iconData = await generateClusterIcon(
        count: count,
        size: size,
        backgroundColor: backgroundColor,
      );

      icons['cluster-$count'] = iconData;
    }

    return icons;
  }

  /// Generate a single individual point icon with "1" text
  /// Uses the same style as cluster icons for consistency
  static Future<Uint8List> generateIndividualIcon({
    double size = 50.0,
    Color backgroundColor = const Color(0xFF11B4DA),
    Color strokeColor = Colors.white,
    double strokeWidth = 10.0,
    Color textColor = Colors.white,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - strokeWidth;

    // Draw outer stroke (white border) - same as cluster
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius + (strokeWidth / 2), strokePaint);

    // Draw filled circle (background) - same as cluster
    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // Draw "1" text - SAME STYLE AS CLUSTER
    final textSpan = TextSpan(
      text: '1',
      style: TextStyle(
        color: textColor,
        fontSize: size * 0.35, // Same 35% as cluster icons
        fontWeight: FontWeight.bold, // Same as cluster
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.5),
            offset: const Offset(0, 1), // Same as cluster
            blurRadius: 2, // Same as cluster
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center, // Same as cluster
    );

    textPainter.layout();
    final textOffset = Offset(
      center.dx - (textPainter.width / 2),
      center.dy - (textPainter.height / 2),
    );
    textPainter.paint(canvas, textOffset);

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Get the appropriate icon name based on cluster count
  static String getIconNameForCount(int count) {
    if (count < 5) return 'cluster-2';
    if (count < 10) return 'cluster-5';
    if (count < 20) return 'cluster-10';
    if (count < 50) return 'cluster-20';
    if (count < 100) return 'cluster-50';
    return 'cluster-100';
  }
}

