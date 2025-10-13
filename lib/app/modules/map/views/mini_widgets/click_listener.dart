import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class AnnotationClickListener implements OnPointAnnotationClickListener {
  final void Function(PointAnnotation annotation) onTap;

  AnnotationClickListener(this.onTap);

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    onTap(annotation); // Call your actual logic
  }
}
