import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/app_bootstrap.dart';
import '../controllers/map_controller_new.dart';

class MapBindingNew extends Bindings {
  @override
  void dependencies() {
    ensureHeavyAppControllersRegistered();
    final controller = Get.find<MapControllerNew>();
    debugPrint('[MapBindingNew] Using existing MapControllerNew instance: ${controller.hashCode}');
  }
}
