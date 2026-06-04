import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_asset_pages.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/media_gps_upload/controllers/media_gps_upload_controller.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_fullscreen_preview.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/mini_widgets/media_gps_limited_library_hint.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_upload_bottom_bar.dart';

/// Page background matches [MediaGpsUploadView].
/// App resume → gallery reload is handled by [MediaGpsUploadView] (route stays underneath).
class MediaGpsGalleryPickerView extends GetView<MediaGpsUploadController> {
  const MediaGpsGalleryPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final _ = ui.selectedLanguage.value;
      final loading = controller.galleryLoading.value;
      final assets = controller.galleryAssets;
      final limited = controller.photoLibraryLimitedAccess.value;
      final selected = controller.selectedAssetIds.length;
      final isDark = ui.darkMode.value;
      final accent = ui.currentMainColor;
      final pageBg = isDark
          ? Colors.black
          : ui.getLightModeBackgroundColor(ui.mainColor.value);
      final centerLabelColor = isDark ? Colors.white : Colors.black87;
      final unselectLabelColor = ui.trackUploadPreviewLabelColor(isDark);

      return Scaffold(
        backgroundColor: pageBg,
        appBar: CustomAppBar(
          title: 'media_gps_upload_files_label'.tr,
          icon: Image.asset(
            AppImages.uploadFilesWhite,
            fit: BoxFit.contain,
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: controller.unselectAllInGallery,
                      style: TextButton.styleFrom(
                        foregroundColor: unselectLabelColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        'media_gps_gallery_unselect_all'.tr.toLowerCase(),
                        style:
                            AppFonts.regular(14, color: unselectLabelColor),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        trKey(
                          'media_gps_gallery_selected_of_total',
                          [selected, assets.length],
                        ),
                        textAlign: TextAlign.center,
                        style: AppFonts.bold(15, color: centerLabelColor),
                      ),
                    ),
                    TextButton(
                      onPressed: controller.selectAllInGallery,
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        'media_gps_gallery_select_all'.tr.toLowerCase(),
                        style: AppFonts.regular(14, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (assets.isEmpty && limited)
              Expanded(
                child: MediaGpsLimitedLibraryHint(
                  isDark: isDark,
                  accent: accent,
                  languageCode: ui.selectedLanguage.value,
                  contentPadding: EdgeInsets.zero,
                  onOpenSettings: () => unawaited(
                    controller.openSystemPhotoLibrarySettings(),
                  ),
                ),
              )
            else if (assets.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'media_gps_gallery_empty'.tr,
                      textAlign: TextAlign.center,
                      style: AppFonts.medium(
                        16,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: _GalleryBulkDragGrid(
                  controller: controller,
                  accent: accent,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
              child: Obx(() {
                final importing = controller.filesImporting.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: importing
                          ? null
                          : () => unawaited(controller.pickFilesFromDevice()),
                      icon: importing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accent,
                              ),
                            )
                          : Icon(Icons.folder_open, color: accent, size: 20),
                      label: Text(
                        importing
                            ? 'media_gps_add_from_files_loading'.tr
                            : 'media_gps_add_from_files'.tr,
                        style: AppFonts.regular(15, color: accent),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          style: TrackUploadBottomBar.uploadButtonStyle(
                            isDark,
                            accent,
                          ),
                          onPressed: () => Get.back<void>(),
                          child: Text(
                            'text_done'.tr,
                            style:
                                TrackUploadBottomBar.uploadButtonTextStyle(accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      );
    });
  }
}

/// Long-press (~420ms) then drag across tiles to bulk select/deselect (Photos-style).
class _GalleryBulkDragGrid extends StatefulWidget {
  const _GalleryBulkDragGrid({
    required this.controller,
    required this.accent,
  });

  final MediaGpsUploadController controller;
  final Color accent;

  @override
  State<_GalleryBulkDragGrid> createState() => _GalleryBulkDragGridState();
}

class _GalleryBulkDragGridState extends State<_GalleryBulkDragGrid> {
  static const double _gridPadding = 1;
  static const double _spacing = 2;
  static const int _cols = 3;
  static const double _aspectRatio = 1;

  final GlobalKey _gridKey = GlobalKey();
  late final ScrollController _scrollController;

  Timer? _longPressTimer;
  Offset? _downGlobal;
  Offset _moveGlobal = Offset.zero;
  bool _fingerBrushActive = false;

  static const Duration _longPressDuration = Duration(milliseconds: 420);
  static const double _scrollCancelSlop = 26;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  int? _hitIndexAt(Offset global) {
    final ctx = _gridKey.currentContext;
    if (ctx == null || !_scrollController.hasClients) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;

    final local = ro.globalToLocal(global);
    final innerW = ro.size.width - 2 * _gridPadding;
    if (innerW <= 1) return null;
    final cellW = (innerW - _spacing * (_cols - 1)) / _cols;
    final cellH = cellW / _aspectRatio;

    final dx = local.dx - _gridPadding;
    final dy = local.dy + _scrollController.offset - _gridPadding;

    if (dx < 0 || dy < 0 || dx > innerW) return null;

    final row = (dy / (cellH + _spacing)).floor();
    final col = (dx / (cellW + _spacing)).floor().clamp(0, _cols - 1);
    final n = widget.controller.galleryAssets.length;
    final idx = row * _cols + col;
    if (idx < 0 || idx >= n) return null;
    return idx;
  }

  void _onPointerDown(PointerDownEvent e) {
    _downGlobal = e.position;
    _moveGlobal = e.position;
    _fingerBrushActive = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (!mounted) return;
      final idx = _hitIndexAt(_moveGlobal);
      if (idx == null) return;
      _fingerBrushActive = true;
      widget.controller.beginBulkDragSelection(idx);
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    _moveGlobal = e.position;
    if (_fingerBrushActive) {
      final idx = _hitIndexAt(e.position);
      if (idx != null) {
        widget.controller.bulkDragSelectionMoveTo(idx);
      }
      return;
    }
    if (_longPressTimer?.isActive == true &&
        _downGlobal != null &&
        (e.position - _downGlobal!).distance > _scrollCancelSlop) {
      _longPressTimer?.cancel();
    }
  }

  void _onPointerEnd() {
    _longPressTimer?.cancel();
    if (_fingerBrushActive) {
      widget.controller.endBulkDragSelection();
    }
    _fingerBrushActive = false;
    _downGlobal = null;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Obx(() {
      final assets = widget.controller.galleryAssets;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: (_) => _onPointerEnd(),
        onPointerCancel: (_) => _onPointerEnd(),
        child: GridView.builder(
          key: _gridKey,
          controller: _scrollController,
          padding: const EdgeInsets.all(_gridPadding),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _cols,
            crossAxisSpacing: _spacing,
            mainAxisSpacing: _spacing,
            childAspectRatio: _aspectRatio,
          ),
          itemCount: assets.length,
          itemBuilder: (context, i) {
            return Obx(() {
              final a = widget.controller.galleryAssets[i];
              final sel = widget.controller.isSelected(a.id);
              final focused =
                  widget.controller.galleryFocusCellIndex.value == i;
              return GestureDetector(
                onTap: () {
                  if (widget.controller.suppressGalleryCellTap) return;
                  widget.controller.setGalleryFocusCell(i);
                  Get.to<void>(
                    () => MediaGpsGalleryFullscreenPreview(
                      initialIndex: i,
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(0),
                    border: focused
                        ? Border.all(color: accent, width: 2)
                        : Border.all(color: Colors.transparent, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaGpsThumbTile(picked: a),
                        Positioned(
                          left: 4,
                          right: 40,
                          bottom: 28,
                          child: IgnorePointer(
                            child: Text(
                              a.libraryMetadataSubtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.medium(9, color: Colors.white)
                                  .copyWith(
                                shadows: const [
                                  Shadow(
                                    offset: Offset(0, 1),
                                    blurRadius: 3,
                                    color: Colors.black87,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (a.isFromFile)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () =>
                                  widget.controller.removeFileAsset(a.id),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade700
                                      .withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        if (!a.hasGps)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade700
                                      .withValues(alpha: 0.82),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'media_gps_no_gps_badge'.tr,
                                  style: AppFonts.bold(9, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () =>
                                  widget.controller.toggleAssetSelection(a.id),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.black26,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: sel
                                    ? Image.asset(
                                        'assets/images/ic_tick.png',
                                        width: 18,
                                        height: 18,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            });
          },
        ),
      );
    });
  }
}

