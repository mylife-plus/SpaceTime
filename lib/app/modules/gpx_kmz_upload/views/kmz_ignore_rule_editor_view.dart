import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/models/kmz_ignore_rule.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_inspector.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';

class KmzIgnoreRuleEditorView extends StatefulWidget {
  const KmzIgnoreRuleEditorView({super.key, required this.inspect});

  final KmzFileInspect inspect;

  @override
  State<KmzIgnoreRuleEditorView> createState() => _KmzIgnoreRuleEditorViewState();
}

class _KmzIgnoreRuleEditorViewState extends State<KmzIgnoreRuleEditorView> {
  TextStyle _valueStyle(Color valueColor) {
    return AppFonts.regular(16, color: valueColor).copyWith(height: 1.2);
  }

  late String _selectedTagId;
  String _valueFromList = '';
  final List<String> _selectedValues = <String>[];
  final Map<String, List<String>> _tagValues = <String, List<String>>{};

  List<String> get _currentTextValues => _tagValues[_selectedTagId] ?? const <String>[];

  @override
  void initState() {
    super.initState();
    final entries = widget.inspect.tagValues.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    for (final e in entries) {
      if (KmzIgnoreRule.isExcludedDateTimeTagKey(e.key)) continue;
      final vals = e.value.where((v) => v.trim().isNotEmpty).toList();
      if (vals.isNotEmpty) _tagValues[e.key] = vals;
    }
    final tagIds = _availableTagIds();
    _selectedTagId = tagIds.isNotEmpty ? tagIds.first : '';
    _valueFromList = _currentTextValues.isNotEmpty ? _currentTextValues.first : '';
  }

  List<String> _availableTagIds() {
    final ids = _tagValues.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ids;
  }

  void _onTagChanged(String? id) {
    if (id == null) return;
    setState(() {
      _selectedTagId = id;
      _selectedValues.clear();
      _valueFromList = _currentTextValues.isNotEmpty ? _currentTextValues.first : '';
    });
  }

  Widget _buildRowField({
    required bool isDark,
    required String label,
    required Widget child,
    VoidCallback? onTap,
    bool absorbChildPointers = false,
    EdgeInsets contentPadding = const EdgeInsets.fromLTRB(12, 6, 12, 6),
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = isDark ? Colors.white54 : Colors.black12;
    final outerTap = onTap;
    final fullAreaTap = absorbChildPointers && outerTap != null;

    Widget valueChild = child;
    if (fullAreaTap) {
      valueChild = IgnorePointer(child: child);
    }

    final decorated = Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: contentPadding,
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppFonts.medium(12, color: labelColor)),
          const SizedBox(height: 4),
          valueChild,
        ],
      ),
    );

    if (outerTap == null) return decorated;
    return GestureDetector(
      behavior:
          fullAreaTap ? HitTestBehavior.opaque : HitTestBehavior.translucent,
      onTap: outerTap,
      child: decorated,
    );
  }

  String _effectiveValue() {
    final vals = <String>{..._selectedValues};
    if (vals.isNotEmpty) return vals.join('\n');
    if (_valueFromList.trim().isNotEmpty) return _valueFromList.trim();
    return '';
  }

  void _save() {
    final v = _effectiveValue();
    if (v.isEmpty || _selectedTagId.isEmpty) return;
    Get.back(
      result: KmzIgnoreRule(
        tag: KmzIgnoreTagKey.dynamicTag,
        tagKey: _selectedTagId,
        value: v,
        condition: KmzIgnoreCondition.textEquals,
      ),
    );
  }

  static Color _kmlAbgrToColor(String hex) {
    final h = hex.trim().toLowerCase();
    if (h.length != 8) return Colors.grey;
    final aa = int.parse(h.substring(0, 2), radix: 16);
    final bb = int.parse(h.substring(2, 4), radix: 16);
    final gg = int.parse(h.substring(4, 6), radix: 16);
    final rr = int.parse(h.substring(6, 8), radix: 16);
    return Color.fromARGB(aa, rr, gg, bb);
  }

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      final pageBg = isDark ? Colors.black : ui.getLightModeBackgroundColor(ui.mainColor.value);
      final valueColor = isDark ? Colors.white : Colors.black87;
      final accent = ui.currentMainColor;
      final tagIds = _availableTagIds();
      final hasTags = tagIds.isNotEmpty;
      final selectedTagValue = tagIds.contains(_selectedTagId)
          ? _selectedTagId
          : (tagIds.isNotEmpty ? tagIds.first : null);

      final bg = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white;
      const saveFg = Colors.blue;
      final saveStyle = ElevatedButton.styleFrom(
        minimumSize: const Size(120, 44),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: bg,
        side: BorderSide.none,
        foregroundColor: saveFg,
        disabledForegroundColor: saveFg.withValues(alpha: 0.38),
      );

      return Scaffold(
        backgroundColor: pageBg,
        appBar: CustomAppBar(
          title: 'gpx_ignore_rule_editor_title'.tr,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            if (!hasTags)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'gpx_ignore_no_tags_available'.tr,
                  style: _valueStyle(valueColor),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              _buildRowField(
                isDark: isDark,
                label: 'gpx_ignore_tag_label'.tr,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    itemHeight: null,
                    value: selectedTagValue,
                    icon: const SizedBox.shrink(),
                    dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    style: _valueStyle(valueColor),
                    items: tagIds
                        .map(
                          (id) => DropdownMenuItem(
                            value: id,
                            child: Text(
                              id,
                              overflow: TextOverflow.ellipsis,
                              style: _valueStyle(valueColor),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _onTagChanged,
                  ),
                ),
              ),
              _buildRowField(
                isDark: isDark,
                label: 'gpx_ignore_value_label'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildValuePickers(isDark, valueColor, accent),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
              child: Center(
                child: ElevatedButton(
                  style: saveStyle,
                  onPressed: hasTags && _effectiveValue().isNotEmpty ? _save : null,
                  child: Text(
                    'gpx_ignore_save_rule'.tr,
                    style: GoogleFonts.kumbhSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: saveFg,
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

  List<Widget> _buildValuePickers(bool isDark, Color valueColor, Color accent) {
    final list = _currentTextValues;
    final out = <Widget>[];
    if (list.isNotEmpty) {
      var current = _valueFromList;
      if (!list.contains(current)) current = list.first;
      out.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  itemHeight: null,
                  value: current,
                  icon: const SizedBox.shrink(),
                  dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  style: _valueStyle(valueColor),
                  items: list
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: (_selectedTagId == 'lineOrIconColor' &&
                                  RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(e))
                              ? Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: _kmlAbgrToColor(e),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        e,
                                        overflow: TextOverflow.ellipsis,
                                        style: _valueStyle(valueColor),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  e,
                                  overflow: TextOverflow.ellipsis,
                                  style: _valueStyle(valueColor),
                                ),
                        ),
                      )
                      .toList(),
                  onChanged: (s) {
                    if (s == null) return;
                    setState(() {
                      _valueFromList = s;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_selectedValues.isNotEmpty) {
      out.add(const SizedBox(height: 8));
      out.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _selectedValues.length; i++)
              InputChip(
                label: Text(
                  _selectedValues[i],
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.medium(13, color: valueColor),
                ),
                deleteIcon: Icon(Icons.close, size: 18, color: accent),
                onDeleted: () {
                  setState(() {
                    _selectedValues.removeAt(i);
                  });
                },
                backgroundColor:
                    isDark ? Colors.grey[900] : Colors.grey.shade200,
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
              ),
          ],
        ),
      );
    }
    return out;
  }
}
