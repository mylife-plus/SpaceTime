import 'package:get/get.dart';
import 'package:spacetime/app/app_bootstrap.dart';

import '../controllers/memory_controller.dart';

class MemoryBinding extends Bindings {
  @override
  void dependencies() {
    ensureHeavyAppControllersRegistered();
    Get.find<MemoryController>();
  }
}
