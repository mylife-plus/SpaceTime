import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/memory_import_blocking_controller.dart';

/// Full-screen modal block during track / gallery memory import (no back, no taps).
class MemoryImportBlockingOverlay extends StatelessWidget {
  const MemoryImportBlockingOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final block = Get.find<MemoryImportBlockingController>();
    final ui = Get.find<UiController>();
    return Obx(() {
      final locked = block.importing.value;
      final lang = ui.selectedLanguage.value;
      final isDark = ui.darkMode.value;
      final accent = ui.currentMainColor;
      final veil = Colors.black.withValues(alpha: isDark ? 0.55 : 0.45);

      return PopScope(
        canPop: !locked,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (locked)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: ColoredBox(
                    color: veil,
                    child: Center(
                      child: Material(
                        color: isDark ? ui.darkSurfaceColor : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 8,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 22,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                trForLang('memory_import_overlay_message', lang),
                                textAlign: TextAlign.center,
                                style: AppFonts.medium(
                                  16,
                                  color: isDark ? Colors.white : Colors.black87,
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
          ],
        ),
      );
    });
  }
}
