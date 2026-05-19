import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/controllers/gpx_kmz_upload_controller.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/track_cluster_field_config.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_field_info_dialog.dart';
import 'package:spacetime/app/widgets/right_nav_trailing_icon.dart';
import 'package:spacetime/app/widgets/track_upload_bottom_bar.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

class GpxKmzUploadView extends GetView<GpxKmzUploadController> {
  const GpxKmzUploadView({super.key});

  static const InputDecoration _valueDecoration = InputDecoration(
    isDense: true,
    border: InputBorder.none,
    contentPadding: EdgeInsets.zero,
  );

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
    VoidCallback? onTrashTap,
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

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppFonts.medium(12, color: labelColor)),
        const SizedBox(height: 2),
        valueChild,
      ],
    );

    if (onInfoTap != null || onTrashTap != null) {
      final trailing = <Widget>[];
      if (onInfoTap != null) {
        trailing.add(
          GestureDetector(
            onTap: onInfoTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(left: trailing.isEmpty ? 4 : 2),
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
        );
      }
      if (onTrashTap != null) {
        trailing.add(
          GestureDetector(
            onTap: onTrashTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(left: trailing.isEmpty ? 4 : 2),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Image.asset(
                  'assets/images/trash.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      }
      // Outer tap only on the expanded field so info/trash taps are not swallowed.
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: outerTap != null
                ? GestureDetector(
                    behavior: fullAreaTap
                        ? HitTestBehavior.opaque
                        : HitTestBehavior.translucent,
                    onTap: outerTap,
                    child: body,
                  )
                : body,
          ),
          ...trailing,
        ],
      );
    }

    final filled = Container(
      width: double.infinity,
      margin: fieldMargin,
      padding: contentPadding,
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border.all(color: borderColor, width: width),
        borderRadius: BorderRadius.circular(4),
      ),
      child: body,
    );

    if (outerTap != null && onInfoTap == null && onTrashTap == null) {
      return GestureDetector(
        behavior:
            fullAreaTap ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onTap: outerTap,
        child: filled,
      );
    }
    return filled;
  }

  Widget _pastUploadsCard({
    required bool isDark,
    required Color valueColor,
    required UiController ui,
  }) {
    return Obx(() {
      final count = controller.pastUploadCount.value;
      return InkWell(
        onTap: controller.onPastUploadsTap,
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
              Text(
                '$count',
                style: AppFonts.regular(18, color: valueColor),
              ),
              const SizedBox(width: 4),
              RightNavTrailingIcon(
                size: 18,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _sectionTitle(String key, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        key.tr,
        style: AppFonts.regular(18, color: color),
      ),
    );
  }

  Widget _buildDropdownField({
    required bool isDark,
    required String label,
    required List<String> optionKeys,
    required RxString selectedKey,
    required Color valueColor,
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
        contentPadding: TrackClusterFieldConfig.dropdownContentPadding,
        fieldMargin: fieldMargin,
        onInfoTap: onInfoTap,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            icon: const SizedBox.shrink(),
            dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            style: _valueStyle(valueColor),
            selectedItemBuilder: (context) => optionKeys
                .map(
                  (k) => Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      trForLang(k, lang),
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
                      trForLang(k, lang),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (k) {
              if (k != null) {
                selectedKey.value = k;
                controller.runPreview();
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
      final raw = controller.rawEntryCount.value;
      final ign = controller.ignoredEntryCount.value;
      final dup = controller.duplicateEntryCount.value;
      final tot = controller.totalEntryCount.value;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              trKey('gpx_entries_line', [raw]),
              style: AppFonts.regular(16, color: normal),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              trKey('gpx_ignored_entries_line', [ign]),
              style: AppFonts.regular(16, color: red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              trKey('gpx_duplicate_entries_line', [dup]),
              style: AppFonts.regular(16, color: red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              trKey('gpx_total_entries_line', [tot]),
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
      final __busy = controller.isBusy.value;
      final isDark = ui.darkMode.value;
      final pageBg = isDark
          ? Colors.black
          : ui.getLightModeBackgroundColor(ui.mainColor.value);
      final valueColor = isDark ? Colors.white : Colors.black;
      final accent = ui.currentMainColor;

      return Scaffold(
        backgroundColor: pageBg,
        appBar: CustomAppBar(
          title: 'title_gpx_kmz_upload'.tr,
          icon: Icon(
            Icons.route,
            color: Colors.white,
            size: 22,
          ),
        ),
        body: Stack(
          children: [
            ListView(
              children: [
            _pastUploadsCard(isDark: isDark, valueColor: valueColor, ui: ui),
            _sectionTitle(
              'gpx_new_memory_upload',
              color: isDark ? Colors.white : Colors.black87,
            ),
            _buildRowField(
              isDark: isDark,
              label: 'gpx_label_file_upload'.tr,
              absorbChildPointers: true,
              onTap: () => controller.pickKmzFile(),
              onTrashTap: () => controller.clearImportedFileAndResetView(),
              child: TextField(
                controller: controller.filePathController,
                readOnly: true,
                canRequestFocus: false,
                enableInteractiveSelection: false,
                decoration: GpxKmzUploadView._valueDecoration,
                style: _valueStyle(valueColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'gpx_section_ignore_entries'.tr,
                      style: AppFonts.regular(18, color: Colors.red.shade700),
                    ),
                  ),
                 
                  IconButton(
                    onPressed: () => controller.onAddIgnoreRuleTap(),
                    icon: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        isDark ? Colors.white : ui.currentMainColor,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/images/ic_add.png',
                        width: 25,
                        height: 25,
                      ),
                    ),
                    tooltip: 'gpx_add_ignore_rule'.tr,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Obx(() {
                final rules = controller.ignoreRules;
                if (rules.isEmpty) return const SizedBox.shrink();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < rules.length; i++)
                      InputChip(
                        label: Text(
                          rules[i].summaryLabel(),
                          style: AppFonts.medium(13, color: valueColor),
                        ),
                        deleteIcon: Icon(Icons.close, size: 18, color: accent),
                        onDeleted: () => controller.removeIgnoreRuleAt(i),
                        backgroundColor:
                            isDark ? Colors.grey[900] : Colors.grey.shade200,
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.grey.shade400,
                        ),
                      ),
                  ],
                );
              }),
            ),
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
                      optionKeys: TrackClusterFieldConfig.maxTimeApartOptionKeys,
                      selectedKey: controller.selectedMaxTimeApartKey,
                      valueColor: valueColor,
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
                      optionKeys: TrackClusterFieldConfig.maxMeterApartOptionKeys,
                      selectedKey: controller.selectedMaxMeterApartKey,
                      valueColor: valueColor,
                      fieldMargin: TrackClusterFieldConfig.pairedFieldMarginEnd,
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
              busy: __busy,
              showPreviewButton: false,
              onUpload: controller.commitUploadToDatabase,
            ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
