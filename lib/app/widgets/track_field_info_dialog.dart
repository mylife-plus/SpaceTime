import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Themed help popup for GPX/KMZ and media-GPS cluster fields ([UiController]).
Future<void> showTrackFieldInfoDialog(String titleKey, String bodyKey) {
  final ui0 = Get.find<UiController>();
  return Get.dialog<void>(
    Obx(() {
      final ui = Get.find<UiController>();
      final _ = ui.selectedLanguage.value;
      final isDark = ui.darkMode.value;
      final accent =
          isDark ? ui.currentMainColor : (ui.primaryColor ?? ui.currentMainColor);
      final titleColor = isDark ? Colors.white : Colors.black87;
      final bodyColor = isDark ? Colors.white70 : Colors.black87;
      final dialogBg = isDark
          ? ui.darkSurfaceColor
          : Color.lerp(
                Colors.white,
                ui.getLightModeBackgroundColor(ui.mainColor.value),
                0.55,
              )!;
      return AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: accent.withValues(alpha: isDark ? 0.35 : 0.42),
            width: 1,
          ),
        ),
        title: Text(
          titleKey.tr,
          style: AppFonts.bold(18, color: titleColor),
        ),
        content: SingleChildScrollView(
          child: Text(
            bodyKey.tr,
            style: AppFonts.medium(15, color: bodyColor).copyWith(height: 1.35),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<void>(),
            style: TextButton.styleFrom(foregroundColor: accent),
            child: Text(
              'text_ok'.tr,
              style: AppFonts.medium(16, color: accent),
            ),
          ),
        ],
      );
    }),
    barrierColor: ui0.darkOverlayColor,
  );
}
