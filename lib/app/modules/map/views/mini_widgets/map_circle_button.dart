import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_colors.dart';

class MapCircleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final double size;
  final String overlayImagePath;
  final bool backgroundImg;

  const MapCircleButton({
    super.key,
    required this.overlayImagePath,
    this.onTap,
    this.size = 44,
    this.backgroundImg = true,
  });

  static const String _backgroundImagePath = AppImages.rectangle;

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      final mainColor = uiController.mainColor.value;
      final useOriginalImage = mainColor == 'blue';

      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration:
              backgroundImg
                  ? BoxDecoration(
                    image: DecorationImage(
                      image: const AssetImage(_backgroundImagePath),
                      fit: BoxFit.contain,
                      colorFilter:
                          uiController.darkMode.value
                              ? uiController.mainColor.value == 'blue'
                                  ? const ColorFilter.mode(
                                    Color(0xFF001937),
                                    BlendMode.srcIn,
                                  )
                                  : ColorFilter.mode(
                                    (uiController.iconColor ?? AppColors.blue),
                                    BlendMode.srcIn,
                                  )
                              : ColorFilter.mode(
                                (uiController.currentMainColor ??
                                    AppColors.blue),
                                BlendMode.srcIn,
                              ),
                    ),
                  )
                  : null,
          child: Center(
            child: Image.asset(
              overlayImagePath,
              width: size * 0.65,
              height: size * 0.65,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    });
  }
}
