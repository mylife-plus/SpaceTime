import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../ui/controllers/ui_controller.dart';

class ContactGroupTile extends StatelessWidget {
  final String title;
  final bool showDivider;
  final String? trailingText;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? trailingTextColor;

  const ContactGroupTile({
    super.key,
    required this.title,
    this.showDivider = false,
    this.trailingText,
    this.trailingIcon,
    this.onTap,
    this.titleColor,
    this.trailingTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Column(
      children: [
        Obx(
          () => InkWell(
            onTap: onTap,
            child: Container(
              color:
                  controller.darkMode.value ? Colors.grey[850] : Colors.white,
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
                            controller.darkMode.value
                                ? Colors.white
                                : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Optional trailing text and icon
                  if (trailingText != null || trailingIcon != null)
                    Row(
                      children: [
                        if (trailingText != null)
                          Text(
                            trailingText!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color:
                                  controller.darkMode.value
                                      ? Colors.white70
                                      : Colors.grey,
                            ),
                          ),
                        if (trailingText != null && trailingIcon != null)
                          const SizedBox(width: 5),
                        if (trailingIcon != null)
                          Icon(
                            trailingIcon,
                            size: 16,
                            color:
                                controller.darkMode.value
                                    ? Colors.white70
                                    : Colors.grey,
                          ),
                      ],
                    ),
                ],
              ),
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
