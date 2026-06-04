import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../config/app_fonts.dart';
import '../../../../widgets/right_nav_trailing_icon.dart';
import '../../../ui/controllers/ui_controller.dart';

class DataTile extends StatelessWidget {
  final String title;
  final bool showDivider;
  final VoidCallback? onTap;
  final Color? titleColor;

  const DataTile({
    super.key,
    required this.title,
    this.showDivider = false,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      final bg = isDark ? ui.darkSurfaceColor : Colors.white;
      final defaultTitleColor = isDark ? Colors.white : Colors.black;
      final paddedRow = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppFonts.medium(
                  16,
                  color: titleColor ?? defaultTitleColor,
                ).copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null)
              RightNavTrailingIcon(
                size: 16,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
          ],
        ),
      );
      return Column(
        children: [
          Material(
            color: bg,
            child: onTap != null
                ? InkWell(onTap: onTap, child: paddedRow)
                : paddedRow,
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              // Same separator color in dark mode as in light mode.
              color: Colors.black.withValues(alpha: 0.1),
              indent: 16,
              endIndent: 16,
            ),
        ],
      );
    });
  }
}
