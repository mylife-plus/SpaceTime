import 'package:get/get.dart';

import '../controllers/add_memories_controller.dart';

class AddMemoriesBindings extends Bindings {
  @override
  void dependencies() {
    Get.put<AddMemoriesController>(AddMemoriesController());
  }
}
