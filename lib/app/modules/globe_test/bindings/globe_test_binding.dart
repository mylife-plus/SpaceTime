import 'package:get/get.dart';
import '../controllers/globe_test_controller.dart';

class GlobeTestBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<GlobeTestController>(() => GlobeTestController());
  }
}

