import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_cluster_candidate.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

import 'package:spacetime/app/modules/gpx_kmz_upload/views/mini_widgets/track_preview_summary_card.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_asset_pages.dart';

Widget _trackPagerIndicator(int length, int currentIndex) {
  const maxDots = 18;
  if (length <= maxDots) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        length,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: SizedBox(
            width: 7,
            height: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: currentIndex == index ? Colors.white : Colors.white54,
              ),
            ),
          ),
        ),
      ),
    );
  }
  return Text(
    '${currentIndex + 1} / $length',
    style: const TextStyle(color: Colors.white, fontSize: 13),
  );
}

/// Preview after upload screen has finished reverse-geocoding all clusters.
class MediaGpsPreviewView extends StatelessWidget {
  const MediaGpsPreviewView({
    super.key,
    required this.candidates,
    required this.locationLines,
  });

  final List<MediaGpsClusterCandidate> candidates;
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

  Widget _buildCard({
    required MediaGpsClusterCandidate candidate,
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
          _MediaPager(items: candidate.items),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
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
                primaryLabel:
                    trKey('gpx_summary_new_memories', [candidates.length]),
                valueLine: range,
              );
            }
            final i = index - 1;
            return RepaintBoundary(
              child: _buildCard(
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

class _MediaPager extends StatefulWidget {
  const _MediaPager({required this.items});

  final List<MediaGpsPickedAsset> items;

  @override
  State<_MediaPager> createState() => _MediaPagerState();
}

class _MediaPagerState extends State<_MediaPager> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Stack(
        children: [
          ClipRect(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final picked = widget.items[index];
                final entity = picked.entity;
                if (entity.type == AssetType.video) {
                  return GalleryVideoPage(
                    entity: entity,
                    isActive: index == _currentIndex,
                  );
                }
                if (entity.type == AssetType.audio) {
                  return GalleryAudioPage(
                    entity: entity,
                    isActive: index == _currentIndex,
                    title: picked.fileTitle,
                  );
                }
                return GalleryStillPage(entity: entity);
              },
            ),
          ),
          if (widget.items.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: _trackPagerIndicator(
                    widget.items.length,
                    _currentIndex,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
