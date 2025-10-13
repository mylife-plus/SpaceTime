import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../controllers/map_controller_new.dart';

class MapBindingNew extends Bindings {
  @override
  void dependencies() {
    // MapControllerNew is already created as permanent in main.dart
    // Just ensure it's available - don't create a new instance
    if (!Get.isRegistered<MapControllerNew>()) {
      debugPrint('[MapBindingNew] MapControllerNew not found, creating new instance');
      Get.put<MapControllerNew>(MapControllerNew(), permanent: true);
    } else {
      debugPrint('[MapBindingNew] MapControllerNew already registered, using existing instance');
    }
  }
}
