import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/modules/ui/views/screens/colors_view.dart';
import 'package:spacetime/app/modules/ui/views/screens/languages.dart';
import 'package:spacetime/app/widgets/appbar.dart';

import '../../../config/app_images.dart';
import '../controllers/ui_controller.dart';
import 'mini_widgets/ui_tile.dart';

class UiView extends GetView<UiController> {
  const UiView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () => Scaffold(
        backgroundColor:
            controller.darkMode.value
                ? Colors.black
                : controller.getLightModeBackgroundColor(
                  controller.mainColor.value,
                ),

        appBar: CustomAppBar(
          title: AppTexts.ui,
          icon: Image.asset(AppImages.ui),
        ),
        body: ListView(
          children: [
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  UiTile(
                    title: AppTexts.language,
                    subtitle: AppTexts.eng,
                    trailingIcon: Icons.arrow_forward_ios,
                    onTap: () => Get.to(() => LanguageSelectionView()),
                    showDivider: true,
                  ),
                  Obx(
                    () => UiTile(
                      title: AppTexts.darkMode,
                      isActive: controller.darkMode.value,
                      onChanged: (val) => controller.setDarkMode(val),
                      showDivider: true,
                    ),
                  ),

                  Obx(
                    () => UiTile(
                      title: AppTexts.mainColor,

                      subtitle:
                          '(${controller.mainColor.value.capitalizeFirst})',
                      trailingIcon: Icons.arrow_forward_ios,
                      onTap: () => Get.to(() => MainColorSelectionView()),
                      // showDivider: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
