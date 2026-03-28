import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/app_bootstrap.dart';

import '../controllers/add_memories_controller.dart';

class AddMemoriesBindings extends Bindings {
  @override
  void dependencies() {
    ensureHeavyAppControllersRegistered();
    final controller = Get.find<AddMemoriesController>();
    debugPrint('[AddMemoriesBindings] Using existing AddMemoriesController instance: ${controller.hashCode}');
  }
}
