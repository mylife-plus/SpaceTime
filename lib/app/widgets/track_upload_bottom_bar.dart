import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Preview / Upload row styled like [FilterPanel] reset + filter buttons.
class TrackUploadBottomBar extends StatelessWidget {
  /// Same pill as the Upload button (e.g. gallery Done). [primary] is typically [UiController.currentMainColor].
  static ButtonStyle uploadButtonStyle(bool isDark, Color primary) {
    final bg = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white;
    return ElevatedButton.styleFrom(
      minimumSize: const Size(120, 44),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bg,
      side: BorderSide.none,
      foregroundColor: primary,
      disabledForegroundColor: primary.withValues(alpha: 0.38),
    );
  }

  static TextStyle uploadButtonTextStyle(Color primary) {
    return GoogleFonts.kumbhSans(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: primary,
    );
  }

  const TrackUploadBottomBar({
    super.key,
    required this.isDark,
    required this.busy,
    required this.onPreview,
    required this.onUpload,
  });

  final bool isDark;
  final bool busy;
  final VoidCallback onPreview;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    final previewFg = ui.trackUploadPreviewLabelColor(isDark);
    final bg = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white;
    final previewStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(120, 44),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bg,
      side: BorderSide.none,
      foregroundColor: previewFg,
      disabledForegroundColor: previewFg.withValues(alpha: 0.38),
    );
    final uploadStyle = uploadButtonStyle(isDark, ui.currentMainColor);

    final theme = Theme.of(context);
    final pi = theme.progressIndicatorTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: previewStyle,
                onPressed: busy ? null : onPreview,
                child: Text(
                  'gpx_button_preview'.tr,
                  style: GoogleFonts.kumbhSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: previewFg,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              ElevatedButton(
                style: uploadStyle,
                onPressed: busy ? null : onUpload,
                child: Text(
                  'gpx_button_upload'.tr,
                  style: uploadButtonTextStyle(ui.currentMainColor),
                ),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                width: double.infinity,
                child: LinearProgressIndicator(
                  backgroundColor: pi.linearTrackColor ??
                      (isDark
                          ? Colors.white24
                          : Colors.grey.shade300),
                  color: pi.color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
