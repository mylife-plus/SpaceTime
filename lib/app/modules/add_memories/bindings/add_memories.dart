import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../controllers/add_memories_controller.dart';

class AddMemoriesBindings extends Bindings {
  @override
  void dependencies() {
    // AddMemoriesController should be a permanent singleton
    // to avoid recreation and maintain filter state across views
    if (!Get.isRegistered<AddMemoriesController>()) {
      debugPrint('[AddMemoriesBindings] AddMemoriesController not found, creating new instance');
      Get.put<AddMemoriesController>(AddMemoriesController(), permanent: true);
    } else {
      debugPrint('[AddMemoriesBindings] AddMemoriesController already registered, using existing instance');
    }
  }
}
