import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/open_source_community_labels.dart';

import '../../ui/controllers/ui_controller.dart';
import 'mini_widgets/settings_tile.dart';
import 'open_source_community_detail_view.dart';

class OpenSourceCommunityView extends StatelessWidget {
  OpenSourceCommunityView({super.key});

  static const String _progressUrl =
      'https://github.com/mylife-plus/SpaceTime/issues';
  static const String _expendituresUrl =
      'https://docs.fileverse.io/d/020026850001#k=wp0bbBQO78bpwxXivDEtKY-XT_lq2M-dexBZxi2Mex0';
  static const String _feedbacksUrl =
      'https://docs.fileverse.io/d/020026850000#k=Qe6uSoq9yVsfwLghMIdipb_Q94WD_uYru_0ElZHiDRs';

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
                    icon: const Text('✍️', style: TextStyle(fontSize: 22)),
                    titleL10nKey: 'apptexts_see_all_feedbacks',
                    showDivider: false,
                    onTap: () {
                      Get.to(
                        () => OpenSourceCommunityDetailView(
                          title: 'apptexts_see_all_feedbacks'.tr,
                          url: _feedbacksUrl,
                          appBarIcon: const Text(
                            '✍️',
                            style: TextStyle(fontSize: 24),
                          ),
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
