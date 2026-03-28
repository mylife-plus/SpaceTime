import 'package:get/get.dart';
import '../controllers/get_started_controller.dart';

class GetStartedBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<GetStartedController>()) {
      Get.put<GetStartedController>(GetStartedController(), permanent: true);
    }
  }
}
