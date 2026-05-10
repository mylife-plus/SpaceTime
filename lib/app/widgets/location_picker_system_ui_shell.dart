import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/theme/app_system_ui.dart';

/// Status-bar inset + icon/nav contrast for full-screen map location pickers (same idea as map tab).
class LocationPickerSystemUiShell extends StatelessWidget {
  const LocationPickerSystemUiShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppSystemUi.overlayStyle(dark: isDark),
        child: ColoredBox(
          color: isDark ? ui.darkBackgroundColor : Colors.white,
          child: child,
        ),
      );
    });
  }
}
