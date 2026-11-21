import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Shared Mapbox pan/fling settings so Android coasts after drag like iOS.
///
/// Note: `useNativeFlingDeceleration` is an Android Maps SDK flag that is not
/// exposed in mapbox_maps_flutter 2.9.x yet — scrollDecelerationEnabled is the
/// supported equivalent here.
class MapboxGestureHelper {
  MapboxGestureHelper._();

  static Future<void> applyIosLikePanGestures(MapboxMap map) async {
    try {
      await map.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: true,
          scrollMode: ScrollMode.HORIZONTAL_AND_VERTICAL,
          scrollDecelerationEnabled: true,
          pinchToZoomDecelerationEnabled: true,
          rotateDecelerationEnabled: true,
          pinchPanEnabled: true,
        ),
      );
    } catch (e) {
      debugPrint('[MapboxGestureHelper] gestures update failed: $e');
    }
  }
}
