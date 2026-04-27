import 'package:get/get.dart';

import '../controllers/gpx_kmz_upload_controller.dart';

class GpxKmzUploadBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<GpxKmzUploadController>(
      () => GpxKmzUploadController(),
      fenix: true,
    );
  }
}
