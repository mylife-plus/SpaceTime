import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_import_pipeline.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

import 'mini_widgets/track_preview_summary_card.dart';

/// Preview after upload screen has finished reverse-geocoding all candidates.
class KmzPreviewView extends StatelessWidget {
  const KmzPreviewView({
    super.key,
    required this.candidates,
    required this.locationLines,
  });

  final List<KmzMemoryCandidate> candidates;
  /// Same order as [candidates] (typically sorted by time).
  final List<String> locationLines;

  String _monthShort(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  String _dateLabel(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _extractFlagPrefix(String value) {
    final t = value.trimLeft();
    if (t.isEmpty) return '';
    final m = RegExp(r'^([\u{1F1E6}-\u{1F1FF}]{2})', unicode: true).firstMatch(t);
    return m?.group(1) ?? '';
  }

  String _stripFlagPrefix(String value) {
    final t = value.trimLeft();
    final flag = _extractFlagPrefix(t);
    if (flag.isEmpty) return t;
    return t.substring(flag.length).trimLeft();
  }

  Widget _card({
    required KmzMemoryCandidate candidate,
    required String locationText,
    required Color headerBg,
    required Color headerText,
    required Color bodyText,
    required Color bodyBg,
  }) {
    final dt = candidate.when.toLocal();
    final hh =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dayMon = '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
    final yr = '${dt.year}';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      decoration: BoxDecoration(
        color: bodyBg,
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 36,
            color: headerBg,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(hh, style: AppFonts.bold(16, color: headerText)),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(dayMon, style: AppFonts.bold(16, color: headerText)),
                    Text(
                      ' $yr',
                      style: AppFonts.bold(
                        16,
                        color: headerText.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Text(
                  _extractFlagPrefix(locationText),
                  style: AppFonts.medium(22, color: bodyText),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _stripFlagPrefix(locationText),
                    style: AppFonts.medium(16, color: bodyText),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      candidates.length == locationLines.length,
      'locationLines must align with candidates',
    );
    final from = candidates.isEmpty ? null : candidates.first.when.toLocal();
    final to = candidates.isEmpty ? null : candidates.last.when.toLocal();
    final range = (from == null || to == null)
        ? '-'
        : '${_dateLabel(from)} – ${_dateLabel(to)}';

    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      final pageBg = isDark ? ui.darkBackgroundColor : Colors.white;
      final headerBg = isDark
          ? (ui.mainColor.value == 'blue'
              ? const Color(0xFF002E68)
              : (ui.primaryColor ?? ui.currentMainColor))
          : (ui.secondaryColor ?? const Color(0xFFDEEDFF));
      final headerText = isDark ? Colors.white : ui.currentMainColor;
      final bodyText = isDark ? Colors.white : Colors.black87;
      final bodyBg = isDark ? Colors.black : Colors.white;

      return Scaffold(
        appBar: CustomAppBar(
          title: 'gpx_screen_preview_title'.tr,
          icon: trackUploadRefreshAppBarIcon(),
        ),
        backgroundColor: pageBg,
        body: ListView.builder(
          itemCount: 1 + candidates.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          cacheExtent: 400,
          itemBuilder: (context, index) {
            if (index == 0) {
              return TrackPreviewSummaryCard(
                primaryLabel: trKey('gpx_summary_new_memories', [candidates.length]),
                valueLine: range,
              );
            }
            final i = index - 1;
            return RepaintBoundary(
              child: _card(
                candidate: candidates[i],
                locationText: locationLines[i],
                headerBg: headerBg,
                headerText: headerText,
                bodyText: bodyText,
                bodyBg: bodyBg,
              ),
            );
          },
        ),
      );
    });
  }
}
