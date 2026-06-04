import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/memories/views/memory_view.dart';

/// Fade-in push — lighter than Cupertino on dark mode (less compositing during motion).
const Duration memoryViewRouteDuration = Duration(milliseconds: 220);

/// Pushes [MemoryView]. Heavy init is deferred until after [memoryViewRouteDuration].
Future<T?> openMemoryView<T>({
  bool editMode = false,
  Map<String, dynamic>? memoryData,
  Bindings? binding,
}) {
  final route = Get.to<T>(
    () => MemoryView(editMode: editMode, memoryData: memoryData),
    binding: binding,
    transition: Transition.fadeIn,
    duration: memoryViewRouteDuration,
    curve: Curves.easeOut,
    opaque: true,
  );
  return route ?? Future<T?>.value(null);
}
