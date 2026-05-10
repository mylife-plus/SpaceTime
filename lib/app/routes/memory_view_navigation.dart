import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/memories/views/memory_view.dart';

/// Pushes [MemoryView] with an animated transition (initialization overlaps motion).
Future<T?> openMemoryView<T>({
  bool editMode = false,
  Map<String, dynamic>? memoryData,
  Bindings? binding,
}) {
  final route = Get.to<T>(
    () => MemoryView(editMode: editMode, memoryData: memoryData),
    binding: binding,
    transition: Transition.cupertino,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
    opaque: true,
  );
  return route ?? Future<T?>.value(null);
}
