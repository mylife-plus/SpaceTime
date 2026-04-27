import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/config/supported_languages.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/modules/settings/views/language_selection_view.dart';
import '../../ui/controllers/ui_controller.dart';
import '../../security/views/security_view.dart';
import '../../ui/views/ui_view.dart';
import '../../data/views/data_view.dart';
import '../../hashtag_groups/views/hashtag_groups_view.dart';
import '../../contact_groups/views/contact_groups_view.dart';
import '../../../modules/memories/views/mini_widgets/category_picker_widget.dart';
import '../../feedback/views/feedback_view.dart';
import '../../gpx_kmz_upload/bindings/gpx_kmz_upload_binding.dart';
import '../../gpx_kmz_upload/views/gpx_kmz_upload_view.dart';
import '../../add_memories/controllers/add_memories_controller.dart';
import '../../filter/controllers/filter_controller.dart';
import '../../map/controllers/map_controller_new.dart';
import '../controllers/settings_controller.dart';
import '../../../services/memory_db.dart';
import 'mini_widgets/settings_spacer.dart';
import 'mini_widgets/settings_tile.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  Future<void> _eraseAllMemories(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all memories'),
        content: const Text(
          'This will delete all memories and imported KMZ logs. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await DatabaseHelper.instance.clearAllMemories();

      if (Get.isRegistered<FilterController>()) {
        Get.find<FilterController>().resetFilters();
      }
      if (Get.isRegistered<AddMemoriesController>()) {
        await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
      }
      if (Get.isRegistered<MapControllerNew>() && Get.isRegistered<FilterController>()) {
        final map = Get.find<MapControllerNew>();
        final fc = Get.find<FilterController>();
        await map.loadMemoriesFromDB(fc.filteredMemories.toList());
        map.showLoadedDataOnMap();
      }

      Get.snackbar(
        'Done',
        'All memories erased',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to erase memories: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

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
                    icon: Image.asset(AppImages.security),
                    titleL10nKey: 'apptexts_security',
                    showDivider: true,
                    onTap: () {
                      Get.to(() => SecurityView());
                    },
                  ),
                  SettingsTile(
                    icon: Icon(
                      Icons.language,
                      color: controller.darkMode.value
                          ? Colors.white70
                          : Colors.blueGrey,
                    ),
                    titleL10nKey: 'apptexts_language',
                    subtitle: displayLabelForLanguageCode(
                      controller.selectedLanguage.value,
                    ),
                    showDivider: true,
                    onTap: () {
                      Get.to(() => const LanguageSelectionView());
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
                    showDivider: true,
                    onTap: () {
                      Get.to(() => DataView());
                    },
                  ),
                  SettingsTile(
                    icon: Icon(
                      Icons.upload_file,
                      color: controller.darkMode.value
                          ? Colors.white70
                          : Colors.blueGrey,
                    ),
                    titleL10nKey: 'apptexts_upload_kmz_gpx',
                    onTap: () {
                      Get.to(
                        () => const GpxKmzUploadView(),
                        binding: GpxKmzUploadBinding(),
                      );
                    },
                  ),
                  SettingsTile(
                    icon: Icon(
                      Icons.delete_forever,
                      color: Colors.red.shade700,
                    ),
                    title: 'Erase All Memories',
                    onTap: () => _eraseAllMemories(context),
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
            const SettingsGroupSpacer(),
            Container(
              color: Theme.of(context).textTheme.bodyMedium?.color,

              child: SettingsTile(
                icon: Image.asset(AppImages.feedback),
                titleL10nKey: 'apptexts_feedback',
                onTap: () {
                  Get.to(() => FeedbackView());
                },
              ),
            ),
          ],
        ),
      );
      },
    );
  }
}
