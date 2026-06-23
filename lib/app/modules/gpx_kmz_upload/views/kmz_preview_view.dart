import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/controllers/gpx_kmz_upload_controller.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_import_pipeline.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/utils/memory_sort.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

import 'mini_widgets/track_preview_summary_card.dart';

/// Preview after upload screen has finished reverse-geocoding all candidates.
class KmzPreviewView extends StatefulWidget {
  const KmzPreviewView({
    super.key,
    required this.candidates,
    required this.locationLines,
  });

  final List<KmzMemoryCandidate> candidates;
  /// Same order as [candidates] (typically sorted by time).
  final List<String> locationLines;

  @override
  State<KmzPreviewView> createState() => _KmzPreviewViewState();
}

class _KmzPreviewViewState extends State<KmzPreviewView> {
  // Local mutable copies so a previewed memory can be removed from the list
  // (and excluded from the upload) without rebuilding the source data.
  late final List<KmzMemoryCandidate> candidates = [...widget.candidates];
  late final List<String> locationLines = [...widget.locationLines];

  /// Delete a previewed memory: drop it from the list and exclude it from the
  /// upload so the counts on the previous screen update. Pops when empty.
  void _deleteCandidateAt(int i) {
    if (i < 0 || i >= candidates.length) return;
    final candidate = candidates[i];
    if (Get.isRegistered<GpxKmzUploadController>()) {
      Get.find<GpxKmzUploadController>().excludeCandidateFromUpload(candidate);
    }
    setState(() {
      candidates.removeAt(i);
      locationLines.removeAt(i);
    });
    if (candidates.isEmpty) {
      Get.back<void>();
    }
  }

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
    required VoidCallback onDelete,
  }) {
    final dt = candidate.when.toLocal();
    final hh =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dayMon = '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
    final yr = '${dt.year}';

    return Container(
      decoration: BoxDecoration(
        color: bodyBg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 36,
            color: headerBg,
            padding: const EdgeInsets.only(left: 12, right: 4),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDelete,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Image.asset(
                        'assets/images/trash.png',
                        width: 20,
                        height: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
    final rangeDates = MemorySort.whenRange(
      candidates.map((c) => c.when.toLocal()),
    );
    final from = rangeDates.from;
    final to = rangeDates.to;
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
              key: ValueKey(candidates[i].fingerprint),
              child: _card(
                candidate: candidates[i],
                locationText: locationLines[i],
                headerBg: headerBg,
                headerText: headerText,
                bodyText: bodyText,
                bodyBg: bodyBg,
                onDelete: () => _deleteCandidateAt(i),
              ),
            );
          },
        ),
      );
    });
  }
}
