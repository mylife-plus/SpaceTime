import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';

import '../../../config/app_images.dart';
import '../controllers/security_controller.dart';
import 'mini_widgets/security_tile.dart';

class SecurityView extends GetView<SecurityController> {
  const SecurityView({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Scaffold(
      backgroundColor:
          controller.darkMode.value
              ? controller.darkBackgroundColor
              : controller.getLightModeBackgroundColor(
                controller.mainColor.value,
              ),
      appBar: CustomAppBar(
        title: AppTexts.security,
        icon: Image.asset(AppImages.security),
      ),
      body: Obx(
        () => SecurityTile(
          title: AppTexts.activePhoneVerification,
          isActive: controller.phoneVerificationEnabled.value,
          onChanged:
              (value) => controller.phoneVerificationEnabled.value = value,
        ),
      ),
    );
  }
}
