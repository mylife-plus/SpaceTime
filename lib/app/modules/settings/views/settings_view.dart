import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import '../../ui/controllers/ui_controller.dart';
import '../../security/views/security_view.dart';
import '../../ui/views/ui_view.dart';
import '../../data/views/data_view.dart';
import '../../hashtag_groups/views/hashtag_groups_view.dart';
import '../../contact_groups/views/contact_groups_view.dart';
import '../../../modules/memories/views/mini_widgets/category_picker_widget.dart';
import '../../feedback/views/feedback_view.dart';
import '../controllers/settings_controller.dart';
import 'mini_widgets/settings_spacer.dart';
import 'mini_widgets/settings_tile.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () => Scaffold(
        backgroundColor:
            controller.darkMode.value
                ? controller.darkBackgroundColor
                : controller.getLightModeBackgroundColor(
                  controller.mainColor.value,
                ),
        appBar: CustomAppBar(
          title: AppTexts.settings,
          icon: Image.asset(AppImages.settings),
        ),
        body: ListView(
          children: [
            Container(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              child: Column(
                children: [
                  SettingsTile(
                    icon: Image.asset(AppImages.security),
                    title: AppTexts.security,
                    showDivider: true,
                    onTap: () {
                      Get.to(() => SecurityView());
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(AppImages.ui),
                    title: AppTexts.ui,
                    showDivider: true,
                    onTap: () {
                      Get.to(() => UiView());
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(AppImages.data),
                    title: AppTexts.data,
                    onTap: () {
                      Get.to(() => DataView());
                    },
                  ),
                ],
              ),
            ),
            const SettingsGroupSpacer(),
            Container(
              color: Theme.of(context).textTheme.bodyMedium?.color,

              child: Column(
                children: [
                      SettingsTile(
                    icon: const Text('📍', style: TextStyle(fontSize: 22)),
                    title: AppTexts.places,
                                        showDivider: true,

                    onTap: () {
                      Get.to(() => const CategoryPickerWidget());
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(
                      AppImages.hash,
                      // show
                      color: controller.darkMode.value ? Colors.white : null,
                    ),
                    title: AppTexts.hashTagGroups,
                    showDivider: true,
                    onTap: () {
                      Get.to(() => HashtagGroupsView());
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(
                      AppImages.contact,
                      color: controller.darkMode.value ? Colors.white : null,
                    ),
                    title: AppTexts.contactGroups,
                    showDivider: false,
                    onTap: () {
                      Get.to(() => ContactGroupsView());
                    },
                  ),
              
                ],
              ),
            ),
            const SettingsGroupSpacer(),
            Container(
              color: Theme.of(context).textTheme.bodyMedium?.color,

              child: SettingsTile(
                icon: Image.asset(AppImages.feedback),
                title: AppTexts.feedBack,
                onTap: () {
                  Get.to(() => FeedbackView());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
