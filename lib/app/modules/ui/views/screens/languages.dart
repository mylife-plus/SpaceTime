import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../widgets/appbar.dart';
import '../../controllers/ui_controller.dart';
import '../mini_widgets/ui_tile.dart';

class LanguageSelectionView extends StatelessWidget {
  LanguageSelectionView({super.key});

  final List<Map<String, String>> languages = [
    {"code": "en", "name": "English", "flag": "🇺🇸"},
    // {"code": "ur", "name": "اردو", "flag": "🇵🇰"},
    // {"code": "zh", "name": "中文", "flag": "🇨🇳"},
    // {"code": "es", "name": "Español", "flag": "🇪🇸"},
    // {"code": "fr", "name": "Français", "flag": "🇫🇷"},
  ];

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
        title: "Select Language",
        icon: const Icon(Icons.language, color: Colors.white),
      ),
      body: ListView.builder(
        itemCount: languages.length,
        itemBuilder: (context, index) {
          final lang = languages[index];
          final isSelected = controller.selectedLanguage.value == lang["code"];

          return UiTile(
            title: lang["name"]!,
            leading: Text(lang["flag"]!, style: const TextStyle(fontSize: 20)),
            trailingIcon: isSelected ? Icons.check : null,
            onTap: () {
              controller.selectedLanguage.value = lang["code"]!;
              Get.back();
            },
            showDivider: index < languages.length - 1,
          );
        },
      ),
    );
  }
}
