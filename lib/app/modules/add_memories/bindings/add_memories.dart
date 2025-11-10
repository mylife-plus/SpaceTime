import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../controllers/add_memories_controller.dart';

class AddMemoriesBindings extends Bindings {
  @override
  void dependencies() {
    // AddMemoriesController is initialized in main.dart as permanent singleton
    // Always use Get.find() - it should always be available
    final controller = Get.find<AddMemoriesController>();
    debugPrint('[AddMemoriesBindings] Using existing AddMemoriesController instance: ${controller.hashCode}');
  }
}
