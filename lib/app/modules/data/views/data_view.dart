import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/widgets/appbar.dart';

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
                  color: uiController.darkMode.value
                      ? uiController.darkSurfaceColor
                      : Colors.white,
                  child: Column(
                    children: [
                DataTile(
                  title: trKey('apptexts_upload_kmz_gpx'),
                  onTap: busy ? null : controller.openKmzGpxUpload,
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.uploadMedia,
                  onTap: busy ? null : controller.openMediaGpsUpload,
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.backupMemories,
                  onTap: busy ? null : controller.exportFullData,
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.uploadMemories,
                  onTap: busy ? null : controller.importFullData,
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.eraseAllData,
                  titleColor: Colors.red,
                  onTap: busy ? null : controller.eraseAllMemories,
                  showDivider: false,
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
