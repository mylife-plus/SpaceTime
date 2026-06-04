import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/open_source_community_labels.dart';
import '../../ui/controllers/ui_controller.dart';
import '../../security/views/security_view.dart';
import '../../ui/views/ui_view.dart';
import '../../data/bindings/data_binding.dart';
import '../../data/views/data_view.dart';
import '../../hashtag_groups/views/hashtag_groups_view.dart';
import '../../contact_groups/views/contact_groups_view.dart';
import '../../../modules/memories/views/mini_widgets/category_picker_widget.dart';
import '../../feedback/views/feedback_view.dart';
import '../controllers/settings_controller.dart';
import 'mini_widgets/settings_spacer.dart';
import 'mini_widgets/settings_tile.dart';
import 'open_source_community_view.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () {
        final _ = controller.selectedLanguage.value;
        return Scaffold(
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
                    icon: const Text('❤️', style: TextStyle(fontSize: 22)),
                    titleOverride: OpenSourceCommunityLabels.settingsTileTitle(),
                    showDivider: true,
                    onTap: () {
                      Get.to(() => OpenSourceCommunityView());
                    },
                  ),
                  SettingsTile(
                    icon: const Text('✍️', style: TextStyle(fontSize: 22)),
                    titleL10nKey: 'apptexts_feedback',
                    showDivider: false,
                    onTap: () {
                      Get.to(() => FeedbackView());
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
                    icon: Image.asset(AppImages.security),
                    titleL10nKey: 'apptexts_security',
                    showDivider: true,
                    onTap: () {
                      Get.to(() => SecurityView());
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(AppImages.ui),
                    titleL10nKey: 'apptexts_ui',
                    showDivider: true,
                    onTap: () {
                      Get.to(() => UiView());
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(AppImages.data),
                    titleL10nKey: 'apptexts_data',
                    showDivider: false,
                    onTap: () {
                      Get.to(
                        () => const DataView(),
                        binding: DataBinding(),
                      );
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
                    icon: Text('text_4'.tr, style: TextStyle(fontSize: 22)),
                    titleL10nKey: 'apptexts_places',
                                        showDivider: true,

                    onTap: () {
                      Get.to(
                        () => const CategoryPickerWidget(
                          openedFromSettings: true,
                        ),
                      );
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(
                      AppImages.hash,
                      // show
                      color: controller.darkMode.value ? Colors.white : null,
                    ),
                    titleL10nKey: 'apptexts_hashtag_groups',
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
                    titleL10nKey: 'apptexts_contact_groups',
                    showDivider: false,
                    onTap: () {
                      Get.to(() => ContactGroupsView());
                    },
                  ),
              
                ],
              ),
            ),
          ],
        ),
      );
      },
    );
  }
}
