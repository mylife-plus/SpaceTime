import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_text.dart';

import '../../../../widgets/appbar.dart';
import '../../controllers/ui_controller.dart';
import '../mini_widgets/ui_tile.dart';

class MainColorSelectionView extends StatelessWidget {
  MainColorSelectionView({super.key});

  static const List<Map<String, dynamic>> _colors = [
    {'value': 'blue', 'color': Colors.blue},
    {'value': 'red', 'color': Colors.red},
    {'value': 'green', 'color': Colors.green},
    {'value': 'purple', 'color': Colors.purple},
  ];

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Obx(() {
      // Read selection at the top so Obx always tracks it (not only inside
      // ListView.builder itemBuilder, which can miss subscriptions on Android).
      final selectedColor = controller.mainColor.value;
      final isDark = controller.darkMode.value;
      final _ = controller.selectedLanguage.value;

      return Scaffold(
        backgroundColor:
            isDark
                ? controller.darkBackgroundColor
                : controller.getLightModeBackgroundColor(selectedColor),
        appBar: CustomAppBar(
          title: AppTexts.selectThemeColor,
          icon: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                colors: [Colors.red, Colors.yellow],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds);
            },
            child: const Icon(Icons.color_lens, color: Colors.yellow),
          ),
        ),
        body: ListView.builder(
          itemCount: _colors.length,
          itemBuilder: (context, index) {
            final colorItem = _colors[index];
            final value = colorItem['value'] as String;
            final isSelected = selectedColor == value;

            return UiTile(
              key: ValueKey('color-$value-$isSelected'),
              title: AppTexts.themeColorDisplayName(value),
              leading: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: colorItem['color'] as Color,
                  shape: BoxShape.circle,
                ),
              ),
              trailing:
                  isSelected
                      ? Icon(
                        Icons.check,
                        color: isDark ? Colors.white70 : Colors.blueGrey,
                      )
                      : null,
              onTap:
                  () => unawaited(controller.setMainColor(value)),
              showDivider: index < _colors.length - 1,
            );
          },
        ),
      );
    });
  }
}
