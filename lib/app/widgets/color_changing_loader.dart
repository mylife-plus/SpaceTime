import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Centered [CircularProgressIndicator] using [UiController.currentMainColor].
class ColorChangingLoader extends StatelessWidget {
  const ColorChangingLoader({super.key, this.strokeWidth = 4});

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(
      () => Center(
        child: CircularProgressIndicator(
          color: ui.currentMainColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}
