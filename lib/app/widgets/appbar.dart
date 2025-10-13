import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart'; // Make sure this import is correct

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget icon;
  final VoidCallback? onBack;

  const CustomAppBar({
    super.key,
    required this.title,
    required this.icon,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Obx(
      () => AppBar(
        automaticallyImplyLeading: false,
        backgroundColor:
            controller.darkMode.value
                ? controller.mainColor.value == 'blue'
                    ? Color(0xFF001937)
                    : controller.primaryColorDark
                : controller.currentMainColor,
        elevation: 0,
        centerTitle: true,
        title: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: onBack ?? Get.back,
              child: Image.asset(
                AppImages.arrowBack,
                width: 24,
                height: 24,
                fit: BoxFit.contain,
              ),
            ),

            const Spacer(),

            // Icon + Title
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: FittedBox(fit: BoxFit.contain, child: icon),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const Spacer(),

            const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}
