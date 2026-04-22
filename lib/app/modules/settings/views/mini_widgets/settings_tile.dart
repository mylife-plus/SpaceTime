import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../ui/controllers/ui_controller.dart';

class SettingsTile extends StatelessWidget {
  final Widget icon;
  /// Plain title when [titleL10nKey] is null.
  final String title;
  /// When set, title is resolved with `.tr` inside [Obx] so it updates on language change.
  final String? titleL10nKey;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;
  /// When false, no trailing chevron; use [trailing] for custom content (e.g. selection check).
  final bool showChevron;
  final Widget? trailing;

  SettingsTile({
    super.key,
    required this.icon,
    this.title = '',
    this.titleL10nKey,
    this.subtitle,
    this.onTap,
    this.showDivider = false,
    this.showChevron = true,
    this.trailing,
  }) : assert(
          titleL10nKey != null || title.isNotEmpty,
          'Provide titleL10nKey or a non-empty title',
        );

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () {
        if (titleL10nKey != null) {
          controller.selectedLanguage.value;
        }
        final titleText =
            titleL10nKey != null ? titleL10nKey!.tr : title;
        return Container(
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
                titleText,
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
      );
      },
    );
  }
}
