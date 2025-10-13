import 'package:get/get.dart';

import '../controllers/contact_groups_controller.dart';

class ContactGroupsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ContactGroupsController>(() => ContactGroupsController());
  }
}
