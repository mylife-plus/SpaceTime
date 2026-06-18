import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/memories/views/memory_view.dart';

/// Cupertino slide — fully opaque over map/add-memories (fadeIn showed map tiles underneath).
const Duration memoryViewRouteDuration = Duration(milliseconds: 320);

/// Pushes [MemoryView] with the same transition from map, add-memories, and memory card edit.
Future<T?> openMemoryView<T>({
  bool editMode = false,
  Map<String, dynamic>? memoryData,
  Bindings? binding,
}) {
  final route = Get.to<T>(
    () => MemoryView(editMode: editMode, memoryData: memoryData),
    binding: binding,
    transition: Transition.cupertino,
    duration: memoryViewRouteDuration,
    curve: Curves.easeOutCubic,
    opaque: true,
  );
  return route ?? Future<T?>.value(null);
}
