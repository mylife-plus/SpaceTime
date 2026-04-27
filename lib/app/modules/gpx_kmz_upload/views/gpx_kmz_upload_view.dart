import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/controllers/gpx_kmz_upload_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';

class GpxKmzUploadView extends GetView<GpxKmzUploadController> {
  const GpxKmzUploadView({super.key});

  static const InputDecoration _valueDecoration = InputDecoration(
    isDense: true,
    border: InputBorder.none,
    contentPadding: EdgeInsets.zero,
  );

  TextStyle _valueStyle(Color valueColor) {
    return AppFonts.medium(15, color: valueColor).copyWith(height: 1.2);
  }

  Widget _buildRowField({
    required bool isDark,
    required String label,
    required Widget child,
    FocusNode? focusNode,
    bool focused = false,
    Color? accentBorder,
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = focused && accentBorder != null
        ? accentBorder
        : (isDark ? Colors.white54 : Colors.black12);
    final width = focused && accentBorder != null ? 2.0 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => focusNode?.requestFocus(),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          border: Border.all(color: borderColor, width: width),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppFonts.medium(12, color: labelColor)),
            const SizedBox(height: 2),
            child,
          ],
        ),
      ),
    );
  }

  Widget _pastUploadsCard({
    required bool isDark,
    required Color valueColor,
    required UiController ui,
  }) {
    final borderColor = isDark ? Colors.white54 : Colors.black12;
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
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 22,
                color: ui.darkMode.value ? Colors.white70 : Colors.blueGrey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'gpx_past_uploads'.tr,
                  style: AppFonts.medium(16, color: valueColor),
                ),
              ),
              Text(
                '$count',
                style: AppFonts.medium(16, color: valueColor),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
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
        style: AppFonts.bold(16, color: color),
      ),
    );
  }

  Widget _buildDropdownField({
    required bool isDark,
    required String label,
    required List<String> optionKeys,
    required RxString selectedKey,
    required Color valueColor,
  }) {
    final iconColor = isDark ? Colors.white54 : Colors.grey;
    return Obx(() {
      final value = optionKeys.contains(selectedKey.value)
          ? selectedKey.value
          : optionKeys.first;
      return _buildRowField(
        isDark: isDark,
        label: label,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            icon: Icon(Icons.arrow_drop_down, color: iconColor),
            dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            style: _valueStyle(valueColor),
            items: optionKeys
                .map(
                  (k) => DropdownMenuItem<String>(
                    value: k,
                    child: Text(
                      k.tr,
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
      final mem = controller.newMemoriesCount.value;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              trKey('gpx_entries_line', [raw]),
              style: AppFonts.medium(15, color: normal),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              trKey('gpx_ignored_entries_line', [ign]),
              style: AppFonts.medium(15, color: red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              trKey('gpx_duplicate_entries_line', [dup]),
              style: AppFonts.medium(15, color: red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              trKey('gpx_total_entries_line', [tot]),
              style: AppFonts.bold(16, color: normal),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              trKey('gpx_summary_new_memories', [mem]),
              style: AppFonts.bold(17, color: Colors.blue.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    });
  }

  Widget _bottomButtons(bool isDark, Color accent, bool busy) {
    final bg = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white;
    final buttonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(120, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      backgroundColor: bg,
      side: const BorderSide(color: Colors.blue),
    );
    final labelStyle = GoogleFonts.kumbhSans(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: Colors.blue,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: busy ? null : controller.onPreviewTap,
              style: buttonStyle,
              child: Text('gpx_button_preview'.tr, style: labelStyle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: busy ? null : controller.commitUploadToDatabase,
              style: buttonStyle,
              child: Text('gpx_button_upload'.tr, style: labelStyle),
            ),
          ),
        ],
      ),
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
        body: ListView(
          children: [
            _pastUploadsCard(isDark: isDark, valueColor: valueColor, ui: ui),
            _sectionTitle(
              'gpx_new_memory_upload',
              color: isDark ? Colors.white : Colors.black87,
            ),
            _buildRowField(
              isDark: isDark,
              label: 'gpx_label_file_upload'.tr,
              child: TextField(
                controller: controller.filePathController,
                readOnly: true,
                onTap: () => controller.pickKmzFile(),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
                      style: AppFonts.bold(16, color: Colors.red.shade700),
                    ),
                  ),
                  IconButton(
                    onPressed: controller.onIgnoreHelpTap,
                    icon: Icon(
                      Icons.help_outline,
                      color: accent,
                      size: 22,
                    ),
                    tooltip: 'gpx_ignore_help_tooltip'.tr,
                  ),
                  IconButton(
                    onPressed: () => controller.onAddIgnoreRuleTap(),
                    icon: Icon(
                      Icons.add,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 28,
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rules: ${rules.length}',
                      style: AppFonts.medium(
                        12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (rules.isNotEmpty)
                      Wrap(
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
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildDropdownField(
                      isDark: isDark,
                      label: 'gpx_label_max_time_apart'.tr,
                      optionKeys: GpxKmzUploadController.maxTimeApartOptionKeys,
                      selectedKey: controller.selectedMaxTimeApartKey,
                      valueColor: valueColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDropdownField(
                      isDark: isDark,
                      label: 'gpx_label_max_meter_apart'.tr,
                      optionKeys: GpxKmzUploadController.maxMeterApartOptionKeys,
                      selectedKey: controller.selectedMaxMeterApartKey,
                      valueColor: valueColor,
                    ),
                  ),
                ],
              ),
            ),
            _bottomButtons(isDark, accent, __busy),
          ],
        ),
      );
    });
  }
}
