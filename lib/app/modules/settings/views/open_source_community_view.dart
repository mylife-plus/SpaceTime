import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/open_source_community_labels.dart';

import '../../../config/app_images.dart';
import '../../ui/controllers/ui_controller.dart';
import 'mini_widgets/settings_tile.dart';
import 'open_source_community_detail_view.dart';

class OpenSourceCommunityView extends StatelessWidget {
  OpenSourceCommunityView({super.key});

  static const String _progressUrl = 'https://github.com/';
  static const String _expendituresUrl = 'https://opencollective.com/';
  static const String _feedbacksUrl = 'https://meta.discourse.org/';

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
          title: '',
          titleWidget: OpenSourceCommunityLabels.appBarTitle(),
          icon: const Text('❤️', style: TextStyle(fontSize: 26)),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: OpenSourceCommunityLabels.introParagraph(),
            ),
            Container(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              child: Column(
                children: [
                  SettingsTile(
                    icon: const Text('💪', style: TextStyle(fontSize: 22)),
                    titleL10nKey: 'apptexts_follow_progress',
                    showDivider: true,
                    onTap: () {
                      Get.to(
                        () => OpenSourceCommunityDetailView(
                          title: 'apptexts_follow_progress'.tr,
                          url: _progressUrl,
                          appBarIcon: const Text(
                            '💪',
                            style: TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  ),
                  SettingsTile(
                    icon: const Text('🤑', style: TextStyle(fontSize: 22)),
                    titleL10nKey: 'apptexts_expenditures_donations',
                    showDivider: true,
                    onTap: () {
                      Get.to(
                        () => OpenSourceCommunityDetailView(
                          title: 'apptexts_expenditures_donations'.tr,
                          url: _expendituresUrl,
                          appBarIcon: const Text(
                            '🤑',
                            style: TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  ),
                  SettingsTile(
                    icon: Image.asset(AppImages.feedback),
                    titleL10nKey: 'apptexts_see_all_feedbacks',
                    showDivider: false,
                    onTap: () {
                      Get.to(
                        () => OpenSourceCommunityDetailView(
                          title: 'apptexts_see_all_feedbacks'.tr,
                          url: _feedbacksUrl,
                          appBarIcon: Image.asset(AppImages.feedback),
                        ),
                      );
                    },
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
