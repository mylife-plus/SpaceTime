import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/track_cluster_field_config.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/kmz_past_uploads_view.dart';
import 'package:spacetime/app/modules/media_gps_upload/controllers/media_gps_upload_controller.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/mini_widgets/media_gps_limited_library_hint.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/right_nav_trailing_icon.dart';
import 'package:spacetime/app/widgets/track_field_info_dialog.dart';
import 'package:spacetime/app/widgets/track_upload_bottom_bar.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

class MediaGpsUploadView extends StatefulWidget {
  const MediaGpsUploadView({super.key});

  @override
  State<MediaGpsUploadView> createState() => _MediaGpsUploadViewState();
}

class _MediaGpsUploadViewState extends State<MediaGpsUploadView>
    with WidgetsBindingObserver {
  late final MediaGpsUploadController controller;
  Timer? _resumeGalleryRefreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = Get.find<MediaGpsUploadController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(controller.refreshPastUploadCount());
      unawaited(controller.reloadDedupeFromDatabase());
    });
  }

  @override
  void dispose() {
    _resumeGalleryRefreshDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeGalleryRefreshDebounce?.cancel();
      _resumeGalleryRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        unawaited(controller.onAppResumedRefreshGallery());
      });
    }
  }

  TextStyle _valueStyle(Color valueColor) {
    return AppFonts.regular(16, color: valueColor).copyWith(height: 1.2);
  }

  Widget _buildRowField({
    required bool isDark,
    required String label,
    required Widget child,
    FocusNode? focusNode,
    bool focused = false,
    Color? accentBorder,
    VoidCallback? onTap,
    bool absorbChildPointers = false,
    EdgeInsets contentPadding = const EdgeInsets.fromLTRB(12, 6, 12, 6),
    EdgeInsets fieldMargin =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    VoidCallback? onInfoTap,
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = focused && accentBorder != null
        ? accentBorder
        : (isDark ? Colors.white54 : Colors.black12);
    final width = focused && accentBorder != null ? 2.0 : 1.0;
    final outerTap = onTap ?? (focusNode == null ? null : () => focusNode.requestFocus());
    final fullAreaTap = absorbChildPointers && outerTap != null;

    Widget valueChild = child;
    if (fullAreaTap) {
      valueChild = IgnorePointer(child: child);
    }

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppFonts.medium(12, color: labelColor)),
        const SizedBox(height: 2),
        valueChild,
      ],
    );

    if (onInfoTap != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: content),
          GestureDetector(
            onTap: onInfoTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Image.asset(
                  'assets/images/ic_info.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      behavior: fullAreaTap ? HitTestBehavior.opaque : HitTestBehavior.translucent,
      onTap: outerTap,
      child: Container(
        width: double.infinity,
        margin: fieldMargin,
        padding: contentPadding,
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          border: Border.all(color: borderColor, width: width),
          borderRadius: BorderRadius.circular(4),
        ),
        child: content,
      ),
    );
  }

  Widget _pastUploadsCard({
    required bool isDark,
    required Color valueColor,
    required UiController ui,
    required int count,
  }) {
    return InkWell(
      onTap: () async {
        await Get.to<void>(
          () => const KmzPastUploadsView(
            importSource: DatabaseHelper.trackImportSourceMediaGps,
          ),
        );
        if (mounted) await controller.refreshPastUploadCount();
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            trackUploadRefreshListIcon(
              ui.darkMode.value ? Colors.white70 : Colors.blueGrey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'gpx_past_uploads'.tr,
                style: AppFonts.regular(18, color: valueColor),
              ),
            ),
            Text('$count', style: AppFonts.regular(18, color: valueColor)),
            const SizedBox(width: 4),
            RightNavTrailingIcon(
              size: 18,
              color: isDark ? Colors.white54 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadFilesRow({
    required bool isDark,
    required Color valueColor,
    required bool busy,
  }) {
    return InkWell(
      onTap: busy ? null : controller.openGalleryPicker,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Opacity(
          opacity: busy ? 0.45 : 1,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Image.asset(
                  isDark
                      ? AppImages.uploadFilesWhite
                      : AppImages.uploadFilesBlack,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'media_gps_upload_files_label'.tr,
                  style: AppFonts.regular(18, color: valueColor),
                ),
              ),
              Obx(
                () => Text(
                  '${controller.selectedAssetIds.length}',
                  style: AppFonts.regular(18, color: valueColor),
                ),
              ),
              const SizedBox(width: 8),
              RightNavTrailingIcon(
                size: 18,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String key, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(key.tr, style: AppFonts.regular(18, color: color)),
    );
  }

  Widget _buildDropdownField({
    required bool isDark,
    required String label,
    required List<String> optionKeys,
    required RxString selectedKey,
    required Color valueColor,
    required void Function(String key) onPicked,
    String Function(String key)? formatOption,
    EdgeInsets fieldMargin =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    VoidCallback? onInfoTap,
  }) {
    return Obx(() {
      final ui = Get.find<UiController>();
      final lang = ui.selectedLanguage.value;
      final value = optionKeys.contains(selectedKey.value)
          ? selectedKey.value
          : optionKeys.first;
      return _buildRowField(
        isDark: isDark,
        label: label,
        // Same default contentPadding as the date fields so this container's
        // height matches them (with isDense the dropdown hugs its text line
        // instead of the 48px interactive minimum).
        fieldMargin: fieldMargin,
        onInfoTap: onInfoTap,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            // isDense removes the outer 48px interactive floor; itemHeight: null
            // stops the *selected* value from being wrapped in a 48px box, so the
            // closed field hugs its single text line and matches the date fields.
            isDense: true,
            itemHeight: null,
            value: value,
            icon: const SizedBox.shrink(),
            dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            style: _valueStyle(valueColor),
            selectedItemBuilder: (context) => optionKeys
                .map(
                  (k) => Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      formatOption?.call(k) ?? trForLang(k, lang),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: _valueStyle(valueColor),
                    ),
                  ),
                )
                .toList(),
            items: optionKeys
                .map(
                  (k) => DropdownMenuItem<String>(
                    value: k,
                    child: Text(
                      formatOption?.call(k) ?? trForLang(k, lang),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (k) {
              if (k != null) {
                selectedKey.value = k;
                onPicked(k);
              }
            },
          ),
        ),
      );
    });
  }

  Widget _statsBlock(bool isDark) {
    final normal = isDark ? Colors.white : Colors.black87;
    final red = Colors.red.shade700;
    return Obx(() {
      final raw = controller.rawFileCount.value;
      final noGps = controller.noGpsCount.value;
      final dup = controller.duplicateHintCount.value;
      final usable = controller.totalUsableSelected;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              trKey('media_gps_stats_raw_files', [raw]),
              style: AppFonts.regular(16, color: normal),
              textAlign: TextAlign.center,
            ),
            if (noGps > 0) ...[
              const SizedBox(height: 4),
              Text(
                trKey('media_gps_stats_without_gps', [noGps]),
                style: AppFonts.regular(16, color: Colors.orange.shade800),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              trKey('media_gps_stats_duplicate_files', [dup]),
              style: AppFonts.regular(16, color: red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              trKey('media_gps_stats_total_usable', [usable]),
              style: AppFonts.bold(16, color: normal),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    });
  }

  Widget _newMemoriesSummaryLine(Color memoryAccent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Obx(() {
        final mem = controller.newMemoriesCount.value;
        return Text(
          trKey('gpx_summary_new_memories', [mem]),
          style: AppFonts.bold(18, color: memoryAccent),
          textAlign: TextAlign.center,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final _ = ui.selectedLanguage.value;
      final busy = controller.isBusy.value;
      final prepPreview = controller.isPreparingPreviewLocations.value;
      final isDark = ui.darkMode.value;
      final pageBg = isDark
          ? Colors.black
          : ui.getLightModeBackgroundColor(ui.mainColor.value);
      final valueColor = isDark ? Colors.white : Colors.black;
      final accent = ui.currentMainColor;

      return Scaffold(
        backgroundColor: pageBg,
        appBar: CustomAppBar(
          title: 'apptexts_upload_media_with_gps'.tr,
        ),
        body: Stack(
          children: [
            ListView(
              children: [
                Obx(
                  () => _pastUploadsCard(
                  isDark: isDark,
                  valueColor: valueColor,
                  ui: ui,
                  count: controller.pastUploadLogCount.value,
                ),
                ),
                _sectionTitle(
                  'gpx_new_memory_upload',
                  color: isDark ? Colors.white : Colors.black87,
                ),
                _uploadFilesRow(
                  isDark: isDark,
                  valueColor: valueColor,
                  busy: busy || prepPreview,
                ),
                Obx(() {
                  if (!controller.photoLibraryLimitedAccess.value ||
                      controller.galleryAssets.isNotEmpty ||
                      controller.galleryLoading.value) {
                    return const SizedBox.shrink();
                  }
                  final lang = ui.selectedLanguage.value;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.orange.shade700
                            .withValues(alpha: isDark ? 0.65 : 0.55),
                      ),
                    ),
                    child: MediaGpsLimitedLibraryHint(
                      isDark: isDark,
                      accent: accent,
                      languageCode: lang,
                      contentPadding: EdgeInsets.zero,
                      onOpenSettings: () => unawaited(
                        controller.openSystemPhotoLibrarySettings(),
                      ),
                    ),
                  );
                }),
                _statsBlock(isDark),
                _sectionTitle(
                  'gpx_section_memory_creation_setting',
                  color: isDark ? Colors.white : Colors.black87,
                ),
                Padding(
                  padding: TrackClusterFieldConfig.pairRowPadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDropdownField(
                          isDark: isDark,
                          label: trForLang(
                            TrackClusterFieldConfig.l10nKeyMaxTimeApart,
                            ui.selectedLanguage.value,
                          ),
                          optionKeys:
                              TrackClusterFieldConfig.maxTimeApartOptionKeys,
                          selectedKey: controller.selectedMaxTimeApartKey,
                          valueColor: valueColor,
                          onPicked: (_) => controller.recomputeStats(),
                          fieldMargin:
                              TrackClusterFieldConfig.pairedFieldMarginStart,
                          onInfoTap: () => showTrackFieldInfoDialog(
                            'gpx_help_max_time_apart_title',
                            'gpx_help_max_time_apart_body',
                          ),
                        ),
                      ),
                      SizedBox(width: TrackClusterFieldConfig.pairGap),
                      Expanded(
                        child: _buildDropdownField(
                          isDark: isDark,
                          label: trForLang(
                            TrackClusterFieldConfig.l10nKeyMaxMeterApart,
                            ui.selectedLanguage.value,
                          ),
                          optionKeys:
                              TrackClusterFieldConfig.maxMeterApartOptionKeys,
                          selectedKey: controller.selectedMaxMeterApartKey,
                          valueColor: valueColor,
                          onPicked: (_) => controller.recomputeStats(),
                          fieldMargin:
                              TrackClusterFieldConfig.pairedFieldMarginEnd,
                          onInfoTap: () => showTrackFieldInfoDialog(
                            'gpx_help_max_meter_apart_title',
                            'gpx_help_max_meter_apart_body',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: TrackClusterFieldConfig.pairRowPadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Obx(() {
                          final key = controller.selectedStartDateKey.value;
                          final label = key.isEmpty
                              ? '-'
                              : controller.formatDateKeyForUi(key);
                          return _buildRowField(
                            isDark: isDark,
                            label: 'gpx_label_date_from'.tr,
                            contentPadding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            fieldMargin:
                                TrackClusterFieldConfig.pairedFieldMarginStart,
                            onTap: () => controller.pickStartDate(context),
                            onInfoTap: () => showTrackFieldInfoDialog(
                              'gpx_help_memory_start_date_title',
                              'gpx_help_memory_start_date_body',
                            ),
                            child: Text(
                              label,
                              style: _valueStyle(valueColor),
                            ),
                          );
                        }),
                      ),
                      SizedBox(width: TrackClusterFieldConfig.pairGap),
                      Expanded(
                        child: Obx(() {
                          final key = controller.selectedEndDateKey.value;
                          final label = key.isEmpty
                              ? '-'
                              : controller.formatDateKeyForUi(key);
                          return _buildRowField(
                            isDark: isDark,
                            label: 'gpx_label_date_to'.tr,
                            contentPadding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            fieldMargin:
                                TrackClusterFieldConfig.pairedFieldMarginEnd,
                            onTap: () => controller.pickEndDate(context),
                            onInfoTap: () => showTrackFieldInfoDialog(
                              'gpx_help_memory_end_date_title',
                              'gpx_help_memory_end_date_body',
                            ),
                            child: Text(
                              label,
                              style: _valueStyle(valueColor),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                _newMemoriesSummaryLine(accent),
                TrackUploadBottomBar(
                  isDark: isDark,
                  busy: busy || prepPreview,
                  onPreview: controller.onPreviewTap,
                  onUpload: controller.commitUpload,
                ),
              ],
            ),
            if (prepPreview)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'text_preparing_your_map'.tr,
                            textAlign: TextAlign.center,
                            style: AppFonts.medium(16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
