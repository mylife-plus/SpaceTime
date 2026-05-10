import 'package:flutter/material.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/widgets/track_upload_bottom_bar.dart';

/// Shown when the OS reports limited photo access and the GPS-media list is empty.
class MediaGpsLimitedLibraryHint extends StatelessWidget {
  const MediaGpsLimitedLibraryHint({
    super.key,
    required this.isDark,
    required this.accent,
    required this.languageCode,
    required this.onOpenSettings,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final bool isDark;
  final Color accent;
  final String languageCode;
  final VoidCallback onOpenSettings;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white70 : Colors.black54;
    final titleColor = isDark ? Colors.white : Colors.black87;
    return Padding(
      padding: contentPadding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 48,
            color: accent.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 16),
          Text(
            trForLang('media_gps_limited_library_need_full_title', languageCode),
            textAlign: TextAlign.center,
            style: AppFonts.bold(17, color: titleColor),
          ),
          const SizedBox(height: 12),
          Text(
            trForLang('media_gps_limited_library_need_full_body', languageCode),
            textAlign: TextAlign.center,
            style: AppFonts.medium(15, color: muted).copyWith(height: 1.35),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            style: TrackUploadBottomBar.uploadButtonStyle(isDark, accent),
            onPressed: onOpenSettings,
            child: Text(
              trForLang('label_open_settings', languageCode),
              style: TrackUploadBottomBar.uploadButtonTextStyle(accent),
            ),
          ),
        ],
      ),
    );
  }
}
