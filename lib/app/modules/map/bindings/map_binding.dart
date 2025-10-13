import 'package:get/get.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller.dart';

class MapBinding extends Bindings {
  @override
  void dependencies() {
    // Use permanent controller to prevent disposal on navigation
    if (!Get.isRegistered<MapController>()) {
      Get.put<MapController>(MapController(), permanent: true);
    }
  }
}
