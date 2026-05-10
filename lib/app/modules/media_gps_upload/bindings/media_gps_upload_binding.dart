import 'package:get/get.dart';
import 'package:spacetime/app/modules/media_gps_upload/controllers/media_gps_upload_controller.dart';

class MediaGpsUploadBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MediaGpsUploadController>(() => MediaGpsUploadController());
  }
}
