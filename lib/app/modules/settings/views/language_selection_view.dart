import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_text.dart';
import 'package:spacetime/app/config/supported_languages.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';

import 'mini_widgets/settings_tile.dart';

class LanguageSelectionView extends StatelessWidget {
  const LanguageSelectionView({super.key});

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();

    return Obx(
      () => Scaffold(
        backgroundColor:
            ui.darkMode.value
                ? ui.darkBackgroundColor
                : ui.getLightModeBackgroundColor(ui.mainColor.value),
        appBar: CustomAppBar(
          title: AppTexts.language,
          icon: const Icon(Icons.language, color: Colors.white),
        ),
        body: ListView(
          children: [
            Container(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              child: Column(
                children: [
                  for (var i = 0; i < kSupportedLanguages.length; i++)
                    SettingsTile(
                      icon: Text(
                        kSupportedLanguages[i].emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: kSupportedLanguages[i].nativeName,
                      showDivider: i < kSupportedLanguages.length - 1,
                      showChevron: false,
                      trailing:
                          ui.selectedLanguage.value ==
                                  kSupportedLanguages[i].code
                              ? Icon(
                                Icons.check,
                                size: 22,
                                color:
                                    ui.darkMode.value
                                        ? Colors.white
                                        : Colors.black87,
                              )
                              : null,
                      onTap: () {
                        ui.setLanguage(kSupportedLanguages[i].code);
                        Get.back();
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
