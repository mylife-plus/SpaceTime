import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../ui/controllers/ui_controller.dart';

class DataTile extends StatelessWidget {
  final String title;
  final bool showDivider;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final Color? titleColor;

  const DataTile({
    super.key,
    required this.title,
    this.showDivider = false,
    this.trailingIcon,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Column(
      children: [
        Obx(
          () => Container(
            color:
                controller.darkMode.value ? controller.darkSurfaceColor : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Title
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color:
                          titleColor ??
                          (controller.darkMode.value
                              ? Colors.white
                              : Colors.black),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Optional trailing icon
                if (trailingIcon != null)
                  InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        trailingIcon,
                        size: 16,
                        color:
                            controller.darkMode.value
                                ? Colors.white70
                                : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Optional divider
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1.5,
            color: Colors.black.withOpacity(0.1),

            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}
