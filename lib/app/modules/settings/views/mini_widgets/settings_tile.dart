import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../ui/controllers/ui_controller.dart';

class SettingsTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;
  /// When false, no trailing chevron; use [trailing] for custom content (e.g. selection check).
  final bool showChevron;
  final Widget? trailing;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showDivider = false,
    this.showChevron = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () => Container(
        color:
            controller.darkMode.value ? controller.darkSurfaceColor : Colors.white,
        child: Column(
          children: [
            ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: Center(child: icon),
              ),
              title: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color:
                      controller.darkMode.value ? Colors.white : Colors.black,
                ),
              ),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: controller.darkMode.value
                            ? Colors.white70
                            : Colors.black54,
                      ),
                    ),
              trailing:
                  showChevron
                      ? (trailing ??
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color:
                                controller.darkMode.value
                                    ? Colors.white70
                                    : Colors.grey,
                          ))
                      : (trailing ?? const SizedBox.shrink()),
              onTap: onTap,
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color:
                    controller.darkMode.value
                        ? Colors.white24
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
