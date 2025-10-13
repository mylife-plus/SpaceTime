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
    final controller = Get.find<UiController>();

    return Scaffold(
      backgroundColor:
          controller.darkMode.value
              ? Colors.black
              : controller.getLightModeBackgroundColor(
                controller.mainColor.value,
              ),
      appBar: CustomAppBar(
        title: AppTexts.data,
        icon: Image.asset(AppImages.data),
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            child: Column(
              children: [
                DataTile(
                  title: AppTexts.uploadGPS,
                  trailingIcon: Icons.arrow_forward_ios,
                  onTap: () {
                    debugPrint('Download tapped');
                  },
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.uploadMedia,
                  trailingIcon: Icons.arrow_forward_ios,
                  onTap: () {
                    debugPrint('Download tapped');
                  },
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.backupMemories,
                  trailingIcon: Icons.arrow_forward_ios,
                  onTap: () {
                    debugPrint('Download tapped');
                  },
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.uploadMemories,
                  trailingIcon: Icons.arrow_forward_ios,
                  onTap: () {
                    debugPrint('Download tapped');
                  },
                  showDivider: true,
                ),
                DataTile(
                  title: AppTexts.eraseAllData,
                  trailingIcon: Icons.arrow_forward_ios,
                  titleColor:
                      controller.darkMode.value ? Colors.red : Colors.red,
                  onTap: () {
                    debugPrint('Download tapped');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
