import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../../widgets/right_nav_trailing_icon.dart';
import '../../controllers/ui_controller.dart';

class UiTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool? isActive;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;
  /// Shows trailing navigation asset when the row opens another screen.
  final bool showTrailingNav;
  /// Overrides [showTrailingNav] when non-null (e.g. selection checkmark).
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? leading;

  const UiTile({
    super.key,
    required this.title,
    this.subtitle,
    this.isActive,
    this.onChanged,
    this.showDivider = false,
    this.showTrailingNav = false,
    this.trailing,
    this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Obx(
      () => Container(
        color:
            controller.darkMode.value ? controller.darkBackgroundColor : Colors.white,
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              child: Container(
                color:
                    controller.darkMode.value ? controller.darkSurfaceColor : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 8),
                          ],
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(width: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    controller.darkMode.value
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.black.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isActive != null && onChanged != null)
                      SizedBox(
                        height: 24,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Transform.scale(
                            scale: 0.7,
                            child: Switch(
                              value: isActive!,
                              onChanged: onChanged!,
                              activeColor: Colors.white,
                              activeTrackColor: Colors.blue,
                              inactiveThumbColor: Colors.grey.shade300,
                              inactiveTrackColor: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                    if (trailing != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: trailing!,
                      )
                    else if (showTrailingNav)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: RightNavTrailingIcon(
                          size: 16,
                          color: controller.darkMode.value
                              ? Colors.white70
                              : Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color:
                    controller.darkMode.value
                        ? controller.darkSurfaceColor.withOpacity(0.6)
                        : Colors.black.withOpacity(0.1),
                indent: 16,
                endIndent: 16,
              ),
          ],
        ),
      ),
    );
  }
}
