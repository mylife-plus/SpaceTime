import 'package:get/get.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_location_picker_controller.dart';

class MemoryLocationPickerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MemoryLocationPickerController>(
      () => MemoryLocationPickerController(),
    );
  }
}

