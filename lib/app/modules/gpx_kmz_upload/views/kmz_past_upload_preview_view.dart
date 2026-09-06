import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/track_import_deletion_refresh.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/track_preview_geocode.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/utils/memory_sort.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_past_upload_delete_confirm_dialog.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

import 'package:spacetime/app/utils/memory_media_image_cache.dart';
import 'package:spacetime/app/utils/video_thumbnail_cache_manager.dart';
import 'package:spacetime/app/widgets/keep_alive_page.dart';
import 'mini_widgets/track_preview_summary_card.dart';

String _formatInlineVideoDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

Widget _pastPagerIndicator(int length, int currentIndex) {
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

class KmzPastUploadPreviewView extends StatefulWidget {
  const KmzPastUploadPreviewView({
    super.key,
    required this.logRow,
    required this.items,
  });

  final Map<String, dynamic> logRow;
  final List<Map<String, dynamic>> items;

  @override
  State<KmzPastUploadPreviewView> createState() =>
      _KmzPastUploadPreviewViewState();
}

class _PastPreviewThumb {
  _PastPreviewThumb._({
    required this.kind,
    this.filePath,
    this.bytes,
    this.thumbPath,
  });

  /// 0 = image file, 1 = image bytes (base64), 2 = video
  final int kind;
  final String? filePath;
  final Uint8List? bytes;
  final String? thumbPath;

  factory _PastPreviewThumb.file(String p) =>
      _PastPreviewThumb._(kind: 0, filePath: p);
  factory _PastPreviewThumb.bytes(Uint8List b) =>
      _PastPreviewThumb._(kind: 1, bytes: b);
  factory _PastPreviewThumb.video(String videoPath, String? thumb) =>
      _PastPreviewThumb._(kind: 2, filePath: videoPath, thumbPath: thumb);
}

class _KmzPastUploadPreviewViewState extends State<KmzPastUploadPreviewView> {
  late final UiController _ui;
  late final List<Map<String, dynamic>> items;
  final Map<int, String> _resolvedLocations = <int, String>{};
  final Map<int, List<_PastPreviewThumb>> _mediaByMemoryId =
      <int, List<_PastPreviewThumb>>{};

  String _ago(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    final d = DateTime.now().difference(dt);
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    if (d.inMinutes > 0) return '${d.inMinutes}m ago';
    return 'now';
  }

  bool _isDeleting = false;

  Future<void> _deleteCurrentLog() async {
    if (_isDeleting) return;
    final id =
        (widget.logRow[DatabaseHelper.columnTrackLogId] as num?)?.toInt();
    if (id == null) return;
    final ok = await showTrackPastUploadDeleteConfirmDialog();
    if (ok != true) return;

    setState(() => _isDeleting = true);
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 32));

    try {
      await DatabaseHelper.instance.deleteTrackImportLogAndMemories(id);
      await refreshConsumersAfterTrackImportDeletion(
        logTag: 'PastUploadPreview',
      );
      if (mounted) Get.back<void>();
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _ui = Get.find<UiController>();
    items = MemorySort.trackLogItemsNewestFirst(widget.items);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final locations = _preloadLocationsProgressive();
    await _preloadAllMedia();
    if (!mounted) return;
    setState(() {});
    await locations;
  }

  Future<void> _preloadLocationsProgressive() async {
    const batchSize = 12;
    for (var start = 0; start < items.length; start += batchSize) {
      final end =
          (start + batchSize > items.length) ? items.length : start + batchSize;
      final tasks = <Future<void>>[];
      for (var i = start; i < end; i++) {
        tasks.add(_resolveAndStoreLocation(i, items[i]));
      }
      await Future.wait(tasks);
      if (mounted) setState(() {});
    }
  }

  int? _memoryIdFrom(Map<String, dynamic> item) {
    final v = item[DatabaseHelper.columnTrackLogItemMemoryId];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  bool _isFilePathLike(String str) {
    return str.startsWith('/') ||
        str.contains(r'\') ||
        str.contains('.jpg') ||
        str.contains('.jpeg') ||
        str.contains('.png') ||
        str.contains('.gif') ||
        str.contains('.webp') ||
        str.startsWith('memory_images/') ||
        str.startsWith('memory_videos/');
  }

  Future<void> _preloadAllMedia() async {
    final appDir = await getApplicationDocumentsDirectory();
    final root = appDir.path;
    final db = DatabaseHelper.instance;
    final ids = <int>{};
    for (final item in items) {
      final mid = _memoryIdFrom(item);
      if (mid != null) ids.add(mid);
    }
    for (final id in ids) {
      final imgs = await db.getMemoryImagesWithOrder(id);
      final vids = await db.getMemoryVideosWithOrder(id);
      final thumbs = <_PastPreviewThumb>[];
      for (final r in imgs) {
        final data = (r[DatabaseHelper.columnImageData] ?? '').toString();
        if (data.isEmpty) continue;
        if (_isFilePathLike(data)) {
          final p = data.startsWith('/') ? data : '$root/$data';
          thumbs.add(_PastPreviewThumb.file(p));
        } else {
          try {
            thumbs.add(_PastPreviewThumb.bytes(base64Decode(data)));
          } catch (_) {}
        }
      }
      for (final r in vids) {
        var vp = (r[DatabaseHelper.columnVideoFilePath] ?? '').toString();
        if (vp.isEmpty) continue;
        vp = vp.startsWith('/') ? vp : '$root/$vp';
        var tp = (r[DatabaseHelper.columnVideoThumbnailPath] ?? '').toString();
        if (tp.isNotEmpty) {
          tp = tp.startsWith('/') ? tp : '$root/$tp';
        } else {
          tp = '';
        }
        thumbs.add(_PastPreviewThumb.video(vp, tp.isEmpty ? null : tp));
      }
      _mediaByMemoryId[id] = thumbs;
    }
  }

  Future<void> _resolveAndStoreLocation(
    int index,
    Map<String, dynamic> item,
  ) async {
    final geo = await _resolveLocation(
      item,
    ).timeout(const Duration(seconds: 8), onTimeout: () => null);
    final fallback =
        (item[DatabaseHelper.columnTrackLogItemLocation] ?? 'Region')
            .toString();
    _resolvedLocations[index] = _composeResolvedLocation(geo, fallback);
  }

  String _dateLabel(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final count =
        (widget.logRow[DatabaseHelper.columnTrackLogNewCount] ?? 0) as int;
    final rangeDates = MemorySort.whenRange(
      items
          .map(
            (e) =>
                DateTime.tryParse(
                  (e[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString(),
                )?.toLocal(),
          )
          .whereType<DateTime>(),
    );
    final from = rangeDates.from;
    final to = rangeDates.to;
    final range =
        (from == null || to == null)
            ? '-'
            : '${_dateLabel(from)} – ${_dateLabel(to)}';
    final createdIso =
        widget.logRow[DatabaseHelper.columnTrackLogCreatedAt] as String?;

    return Obx(() {
      final pageBg =
          _ui.darkMode.value ? _ui.darkBackgroundColor : Colors.white;
      return Scaffold(
        appBar: CustomAppBar(
          title: 'gpx_past_uploads'.tr,
          icon: trackUploadRefreshAppBarIcon(),
        ),
        backgroundColor: pageBg,
        body: Stack(
          children: [
            ListView.builder(
              itemCount: 1 + items.length,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return TrackPreviewSummaryCard(
                    primaryLabel: trKey('gpx_past_upload_memories_line', [
                      count,
                    ]),
                    valueLine: range,
                    uploadedAgoLabel: _ago(createdIso),
                    onDelete: _isDeleting ? null : _deleteCurrentLog,
                  );
                }
                final i = index - 1;
                return _buildReadOnlyMemoryStyleCard(
                  ui: _ui,
                  item: items[i],
                  locationText: _resolvedLocations[i] ?? 'Region',
                  memoryId: _memoryIdFrom(items[i]),
                );
              },
            ),
            if (_isDeleting)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: _ui.currentMainColor,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  String _monthShort(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  Widget _buildReadOnlyMemoryStyleCard({
    required UiController ui,
    required Map<String, dynamic> item,
    required String locationText,
    int? memoryId,
  }) {
    final dt =
        DateTime.tryParse(
          (item[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString(),
        )?.toLocal();
    final hh =
        dt == null
            ? '--:--'
            : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dayMon =
        dt == null
            ? '-'
            : '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
    final yr = dt == null ? '' : '${dt.year}';

    return Obx(() {
      final isDark = ui.darkMode.value;
      final headerBg =
          isDark
              ? (ui.mainColor.value == 'blue'
                  ? const Color(0xFF002E68)
                  : ui.primaryColor)
              : (ui.secondaryColor ?? const Color(0xFFDEEDFF));
      final headerText = isDark ? Colors.white : ui.currentMainColor;
      final bodyText = isDark ? Colors.white : Colors.black87;
      final bodyBg = isDark ? Colors.black : Colors.white;

      return Container(
        decoration: BoxDecoration(color: bodyBg),
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
                    child: Text(
                      hh,
                      style: AppFonts.bold(16, color: headerText),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(dayMon, style: AppFonts.bold(16, color: headerText)),
                      if (yr.isNotEmpty)
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
            if (memoryId != null &&
                (_mediaByMemoryId[memoryId]?.isNotEmpty ?? false))
              _PastMediaPager(
                thumbs: _mediaByMemoryId[memoryId]!,
                bodyText: bodyText,
              ),
          ],
        ),
      );
    });
  }

  String _composeResolvedLocation(
    Map<String, dynamic>? geo,
    String fallbackLocation,
  ) {
    final flag = (geo?['flag'] as String? ?? '').trim();
    final name = (geo?['name'] as String? ?? '').trim();
    final city = (geo?['city'] as String? ?? '').trim();
    final country = (geo?['country'] as String? ?? '').trim();

    var primary = name;
    if (primary.isEmpty) primary = city;
    if (primary.isEmpty) primary = country;
    if (primary.isEmpty)
      primary =
          fallbackLocation.trim().isEmpty ? 'Region' : fallbackLocation.trim();

    return flag.isEmpty ? primary : '$flag $primary';
  }

  Future<Map<String, dynamic>?> _resolveLocation(
    Map<String, dynamic> item,
  ) async {
    final lat =
        (item[DatabaseHelper.columnTrackLogItemLat] as num?)?.toDouble();
    final lng =
        (item[DatabaseHelper.columnTrackLogItemLng] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return reverseGeocodeTrackPreview(lat, lng);
  }

  String _extractFlagPrefix(String value) {
    final t = value.trimLeft();
    if (t.isEmpty) return '';
    final m = RegExp(
      r'^([\u{1F1E6}-\u{1F1FF}]{2})',
      unicode: true,
    ).firstMatch(t);
    return m?.group(1) ?? '';
  }

  String _stripFlagPrefix(String value) {
    final t = value.trimLeft();
    final flag = _extractFlagPrefix(t);
    if (flag.isEmpty) return t;
    return t.substring(flag.length).trimLeft();
  }
}

class _PastVideoPage extends StatefulWidget {
  const _PastVideoPage({
    required this.videoPath,
    required this.bodyText,
    required this.isActive,
    this.thumbPath,
  });

  final String videoPath;
  final String? thumbPath;
  final Color bodyText;
  final bool isActive;

  @override
  State<_PastVideoPage> createState() => _PastVideoPageState();
}

class _PastVideoPageState extends State<_PastVideoPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  String? _generatedThumbPath;

  @override
  void initState() {
    super.initState();
    _open();
    _ensurePosterThumb();
  }

  Future<void> _ensurePosterThumb() async {
    final tp = widget.thumbPath;
    if (tp != null && tp.isNotEmpty && File(tp).existsSync()) return;
    final path = await VideoThumbnailCacheManager.getOrGenerateThumbnail(
      videoPath: widget.videoPath,
      existingDbThumbnail: widget.thumbPath,
      maxEdge: 720,
      quality: VideoThumbnailCacheManager.defaultQuality,
    );
    if (!mounted || path == null || path.isEmpty) return;
    setState(() => _generatedThumbPath = path);
  }

  @override
  void didUpdateWidget(_PastVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }

  Future<void> _open() async {
    final f = File(widget.videoPath);
    if (!f.existsSync()) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final vc = VideoPlayerController.file(f);
      _controller = vc;
      await vc.initialize();
      vc.addListener(_onTick);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      c.dispose();
    }
    super.dispose();
  }

  void _togglePlay() {
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) return;
    setState(() {
      vc.value.isPlaying ? vc.pause() : vc.play();
    });
  }

  Widget _poster() {
    final candidates = <String?>[
      widget.thumbPath,
      _generatedThumbPath,
    ];
    for (final tp in candidates) {
      if (tp == null || tp.isEmpty) continue;
      final tf = File(tp);
      if (tf.existsSync()) {
        return Image.file(
          tf,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      }
    }
    return ColoredBox(
      color: Colors.black,
      child: Icon(Icons.videocam, color: widget.bodyText, size: 46),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ColoredBox(
        color: Colors.black26,
        child: Icon(Icons.videocam_off, color: widget.bodyText, size: 46),
      );
    }
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _poster(),
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }
    final ui = Get.find<UiController>();
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: vc.value.size.width,
              height: vc.value.size.height,
              child: VideoPlayer(vc),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: vc.value.isPlaying ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: IconButton(
            iconSize: 64,
            onPressed: _togglePlay,
            icon: const Icon(
              Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  vc,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: ui.currentMainColor,
                    bufferedColor: Colors.white.withValues(alpha: 0.3),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        vc.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatInlineVideoDuration(vc.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    Text(
                      'text'.tr,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _formatInlineVideoDuration(vc.value.duration),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PastMediaPager extends StatefulWidget {
  const _PastMediaPager({required this.thumbs, required this.bodyText});

  final List<_PastPreviewThumb> thumbs;
  final Color bodyText;

  @override
  State<_PastMediaPager> createState() => _PastMediaPagerState();
}

class _PastMediaPagerState extends State<_PastMediaPager> {
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

  Widget _pageChild(BuildContext context, _PastPreviewThumb t) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW = (220 * dpr).round().clamp(320, 2048);
    switch (t.kind) {
      case 0:
        return MemoryMediaImageProviderCache.instance.buildImage(
          context: context,
          imageData: t.filePath!,
          fit: BoxFit.cover,
          cacheWidth: decodeW,
          errorChild: Icon(Icons.broken_image, color: widget.bodyText),
        );
      case 1:
        return Image.memory(
          t.bytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: decodeW,
          errorBuilder:
              (_, __, ___) => Icon(Icons.broken_image, color: widget.bodyText),
        );
      default:
        return ColoredBox(
          color: Colors.black26,
          child: Center(
            child: Icon(Icons.videocam, color: widget.bodyText, size: 46),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thumbs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Stack(
        children: [
          ClipRect(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.thumbs.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final t = widget.thumbs[index];
                return KeepAlivePage(
                  child:
                      t.kind == 2 && t.filePath != null
                          ? _PastVideoPage(
                            videoPath: t.filePath!,
                            thumbPath: t.thumbPath,
                            bodyText: widget.bodyText,
                            isActive: index == _currentIndex,
                          )
                          : Stack(
                            fit: StackFit.expand,
                            children: [_pageChild(context, t)],
                          ),
                );
              },
            ),
          ),
          if (widget.thumbs.length > 1)
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
                  child: _pastPagerIndicator(
                    widget.thumbs.length,
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
