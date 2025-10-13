import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../widgets/appbar.dart';
import '../../controllers/ui_controller.dart';
import '../mini_widgets/ui_tile.dart';

class MainColorSelectionView extends StatelessWidget {
  MainColorSelectionView({super.key});

  final List<Map<String, dynamic>> colors = [
    {'name': 'Blue', 'value': 'blue', 'color': Colors.blue},
    {'name': 'Red', 'value': 'red', 'color': Colors.red},
    {'name': 'Green', 'value': 'green', 'color': Colors.green},
    {'name': 'Purple', 'value': 'purple', 'color': Colors.purple},
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
        title: 'Select Theme Color',
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
        itemCount: colors.length,
        itemBuilder: (context, index) {
          final colorItem = colors[index];
          final isSelected = controller.mainColor.value == colorItem['value'];

          return UiTile(
            title: colorItem['name'],
            leading: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: colorItem['color'],
                shape: BoxShape.circle,
              ),
            ),
            trailingIcon: isSelected ? Icons.check : null,
            onTap: () {
              controller.setMainColor(colorItem['value']);
              Get.back();
            },
            showDivider: index < colors.length - 1,
          );
        },
      ),
    );
  }
}
