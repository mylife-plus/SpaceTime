import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Split l10n so the localized “open source” phrase renders in bold everywhere.
abstract final class OpenSourceCommunityLabels {
  static const _introPre = 'apptexts_open_source_intro_pre';
  static const _introBold = 'apptexts_open_source_intro_bold';
  static const _introPost = 'apptexts_open_source_intro_post';

  static TextSpan _introSpan(TextStyle normal, TextStyle bold) {
    return TextSpan(
      style: normal,
      children: [
        TextSpan(text: _introPre.tr),
        TextSpan(text: _introBold.tr, style: bold),
        TextSpan(text: _introPost.tr),
      ],
    );
  }

  /// Settings list row.
  static Widget settingsTileTitle() {
    return Obx(() {
      final ui = Get.find<UiController>();
      ui.selectedLanguage.value;
      final dark = ui.darkMode.value;
      final color = dark ? Colors.white : Colors.black;
      return Text(
        'apptexts_community_app'.tr,
        style: AppFonts.medium(16, color: color).copyWith(
          fontWeight: FontWeight.w600,
        ),
      );
    });
  }

  /// [CustomAppBar] title — same label as the settings row.
  static Widget appBarTitle() {
    return Obx(() {
      final ui = Get.find<UiController>();
      ui.selectedLanguage.value;
      return Text(
        'apptexts_community_app'.tr,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppFonts.medium(18, color: Colors.white).copyWith(
          fontWeight: FontWeight.w600,
        ),
      );
    });
  }

  /// Intro copy on the open-source screen.
  static Widget introParagraph() {
    return Obx(() {
      final ui = Get.find<UiController>();
      ui.selectedLanguage.value;
      final dark = ui.darkMode.value;
      final color = dark ? Colors.white : Colors.black87;
      final normal = AppFonts.medium(16, color: color).copyWith(
        fontWeight: FontWeight.w600,
      );
      final bold = AppFonts.medium(16, color: color).copyWith(
        fontWeight: FontWeight.w800,
      );
      return Text.rich(_introSpan(normal, bold));
    });
  }
}
