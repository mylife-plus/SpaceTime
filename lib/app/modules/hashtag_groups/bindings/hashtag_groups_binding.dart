import 'package:get/get.dart';

import '../controllers/hashtag_groups_controller.dart';

class HashtagGroupsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HashtagGroupsController>(() => HashtagGroupsController());
  }
}
