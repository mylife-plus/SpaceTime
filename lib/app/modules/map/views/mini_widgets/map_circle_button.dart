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
  final int? badgeCount; // Optional badge count

  const MapCircleButton({
    super.key,
    required this.overlayImagePath,
    this.onTap,
    this.size = 44,
    this.backgroundImg = true,
    this.badgeCount,
  });

  static const String _backgroundImagePath = AppImages.rectangle;

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      final mainColor = uiController.mainColor.value;
      final useOriginalImage = mainColor == 'blue';

      return Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
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
          ),
          // Badge indicator
          if (badgeCount != null && badgeCount! > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: uiController.darkMode.value ? Colors.black : Colors.white,
                    width: 1.5,
                  ),
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Center(
                  child: Text(
                    badgeCount! > 9 ? '9+' : badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
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
