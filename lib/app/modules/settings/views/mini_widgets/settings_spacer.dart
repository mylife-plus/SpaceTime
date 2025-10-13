import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../ui/controllers/ui_controller.dart';

class SettingsGroupSpacer extends StatelessWidget {
  const SettingsGroupSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () => Container(
        height: 8,
        color:
            controller.darkMode.value
                ? Colors.black
                : controller.currentMainColor.withValues(alpha: 0.1),
      ),
    );
  }
}
