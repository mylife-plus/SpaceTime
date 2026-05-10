import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../services/app_lock_controller.dart';

/// Full-screen overlay when [AppLockController.isLocked] is true.
/// Styling follows [UiController] theme (same family as main app screens).
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = Get.find<AppLockController>();
    return Obx(() {
      if (!lock.isLocked.value) return child;
      final ui = Get.find<UiController>();
      final _ = ui.selectedLanguage.value;
      final authErr = lock.authError.value;
      final isDark = ui.darkMode.value;
      final pageBg = isDark
          ? ui.darkBackgroundColor
          : ui.getLightModeBackgroundColor(ui.mainColor.value);
      final surface = isDark ? ui.darkSurfaceColor : Colors.white;
      final accent = ui.currentMainColor;
      final titleColor = isDark ? Colors.white : Colors.black87;
      final bodyColor = isDark ? Colors.white70 : Colors.black54;
      final borderColor =
          isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: Material(
              color: pageBg,
              child: SafeArea(bottom: false,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 44,
                                color: accent,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'text_app_locked'.tr,
                                textAlign: TextAlign.center,
                                style: AppFonts.bold(20, color: titleColor),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'app_lock_unlock_instructions'.tr,
                                textAlign: TextAlign.center,
                                style: AppFonts.regular(15, color: bodyColor).copyWith(height: 1.4),
                              ),
                              if (authErr != null && authErr.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    authErr.tr,
                                    textAlign: TextAlign.center,
                                    style: AppFonts.medium(14, color: Colors.red.shade400),
                                  ),
                                ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      lock.authenticate(isColdStart: false),
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'app_lock_button_unlock'.tr,
                                    style: AppFonts.bold(16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
