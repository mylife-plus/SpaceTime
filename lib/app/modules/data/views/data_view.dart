import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/widgets/appbar.dart';

import '../../../config/app_images.dart';
import '../../ui/controllers/ui_controller.dart';
import '../controllers/data_controller.dart';
import 'mini_widgets/data_tile.dart';

class DataView extends GetView<DataController> {
  const DataView({super.key});
  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      final busy = controller.isBusy.value;
      return Scaffold(
        backgroundColor:
            uiController.darkMode.value
                ? uiController.darkBackgroundColor
                : uiController.getLightModeBackgroundColor(
                  uiController.mainColor.value,
                ),
        appBar: CustomAppBar(
          title: AppTexts.data,
          icon: Image.asset(AppImages.data),
        ),
        body: Stack(
          children: [
            ListView(
              children: [
                Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      DataTile(
                        title: AppTexts.uploadGPS,
                        trailingIcon: Icons.arrow_forward_ios,
                        onTap: () {},
                        showDivider: true,
                      ),
                      DataTile(
                        title: AppTexts.uploadMedia,
                        trailingIcon: Icons.arrow_forward_ios,
                        onTap: () {},
                        showDivider: true,
                      ),
                      DataTile(
                        title: AppTexts.backupMemories,
                        trailingIcon: Icons.arrow_forward_ios,
                        onTap: busy ? null : controller.exportFullData,
                        showDivider: true,
                      ),
                      DataTile(
                        title: AppTexts.uploadMemories,
                        trailingIcon: Icons.arrow_forward_ios,
                        onTap: busy ? null : controller.importFullData,
                        showDivider: true,
                      ),
                      DataTile(
                        title: AppTexts.eraseAllData,
                        trailingIcon: Icons.arrow_forward_ios,
                        titleColor: Colors.red,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      );
    });
  }
}
