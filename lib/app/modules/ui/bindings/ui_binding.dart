import 'package:get/get.dart';

import '../controllers/ui_controller.dart';

class UiBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UiController>(() => UiController());
  }
}
