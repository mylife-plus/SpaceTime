import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../controllers/map_controller_new.dart';

class MapBindingNew extends Bindings {
  @override
  void dependencies() {
    // MapControllerNew is initialized in main.dart as permanent singleton
    // Always use Get.find() - it should always be available
    final controller = Get.find<MapControllerNew>();
    debugPrint('[MapBindingNew] Using existing MapControllerNew instance: ${controller.hashCode}');
  }
}
