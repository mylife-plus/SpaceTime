import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Summary tile matching [KmzPastUploadsView] list rows (memories line + date range + optional ago + trash).
class TrackPreviewSummaryCard extends StatelessWidget {
  const TrackPreviewSummaryCard({
    super.key,
    required this.primaryLabel,
    required this.valueLine,
    this.uploadedAgoLabel,
    this.onDelete,
  });

  final String primaryLabel;
  final String valueLine;
  /// When set (non-empty), shown muted on the right before delete — same as past uploads list.
  final String? uploadedAgoLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      final cardBg =
          isDark ? ui.darkSurfaceColor : const Color(0xFFF3F3F3);

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    primaryLabel,
                    style: AppFonts.regular(
                      16,
                      color: ui.currentMainColor,
                    ),
                  ),
                  Text(
                    valueLine,
                    style: AppFonts.regular(
                      18,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.87)
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            if (uploadedAgoLabel != null &&
                uploadedAgoLabel!.trim().isNotEmpty)
              Text(
                uploadedAgoLabel!.trim(),
                style: AppFonts.regular(
                  16,
                  color: isDark
                      ? Colors.white54
                      : Colors.grey.shade600,
                ),
              ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: Image.asset(
                  'assets/images/trash.png',
                  width: 22,
                  height: 22,
                ),
              ),
          ],
        ),
      );
    });
  }
}
