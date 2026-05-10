import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/models/kmz_ignore_rule.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_inspector.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/track_cluster_field_config.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/app_date_time_pickers.dart';

class KmzIgnoreRuleEditorView extends StatefulWidget {
  const KmzIgnoreRuleEditorView({super.key, required this.inspect});

  final KmzFileInspect inspect;

  @override
  State<KmzIgnoreRuleEditorView> createState() => _KmzIgnoreRuleEditorViewState();
}

class _KmzIgnoreRuleEditorViewState extends State<KmzIgnoreRuleEditorView> {
  static const String _timeTagId = '__track_point_time__';

  TextStyle _valueStyle(Color valueColor) {
    return AppFonts.regular(16, color: valueColor).copyWith(height: 1.2);
  }

  late String _selectedTagId;
  late KmzIgnoreCondition _condition;
  String _valueFromList = '';
  final List<String> _selectedValues = <String>[];
  DateTime? _pickedDateTime;
  String? _selectedTimeIsoFromKmz;
  final Map<String, List<String>> _tagValues = <String, List<String>>{};

  static Color _kmlAbgrToColor(String hex) {
    final h = hex.trim().toLowerCase();
    if (h.length != 8) return Colors.grey;
    final aa = int.parse(h.substring(0, 2), radix: 16);
    final bb = int.parse(h.substring(2, 4), radix: 16);
    final gg = int.parse(h.substring(4, 6), radix: 16);
    final rr = int.parse(h.substring(6, 8), radix: 16);
    return Color.fromARGB(aa, rr, gg, bb);
  }

  bool get _isTimeTag => _selectedTagId == _timeTagId;
  KmzIgnoreTagKey get _resolvedTag =>
      _isTimeTag ? KmzIgnoreTagKey.trackPointTime : KmzIgnoreTagKey.dynamicTag;
  List<String> get _currentTextValues => _tagValues[_selectedTagId] ?? const <String>[];

  @override
  void initState() {
    super.initState();
    final entries = widget.inspect.tagValues.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    for (final e in entries) {
      final vals = e.value.where((v) => v.trim().isNotEmpty).toList();
      if (vals.isNotEmpty) _tagValues[e.key] = vals;
    }
    final tagIds = _availableTagIds();
    _selectedTagId = tagIds.isNotEmpty ? tagIds.first : _timeTagId;
    _condition = _isTimeTag
        ? KmzIgnoreCondition.dateIgnoreAfter
        : KmzIgnoreCondition.textEquals;
    _valueFromList = _currentTextValues.isNotEmpty ? _currentTextValues.first : '';
    _pickedDateTime = widget.inspect.maxWhen?.toLocal() ??
        widget.inspect.minWhen?.toLocal() ??
        DateTime.now();
    _selectedTimeIsoFromKmz = widget.inspect.trackWhenValuesIso.isNotEmpty
        ? widget.inspect.trackWhenValuesIso.first
        : null;
    _syncConditionDefault();
  }

  List<String> _availableTagIds() {
    final ids = _tagValues.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (widget.inspect.trackWhenValuesIso.isNotEmpty ||
        widget.inspect.minWhen != null ||
        widget.inspect.maxWhen != null) {
      ids.add(_timeTagId);
    }
    return ids;
  }

  void _syncConditionDefault() {
    final opts = KmzIgnoreRule.conditionsForTag(_resolvedTag);
    if (!opts.contains(_condition)) {
      _condition = opts.first;
    }
  }

  void _onTagChanged(String? id) {
    if (id == null) return;
    setState(() {
      _selectedTagId = id;
      _selectedValues.clear();
      if (_isTimeTag) {
        _pickedDateTime = widget.inspect.maxWhen?.toLocal() ??
            widget.inspect.minWhen?.toLocal() ??
            DateTime.now();
        _selectedTimeIsoFromKmz = widget.inspect.trackWhenValuesIso.isNotEmpty
            ? widget.inspect.trackWhenValuesIso.first
            : null;
      } else {
        _valueFromList = _currentTextValues.isNotEmpty ? _currentTextValues.first : '';
      }
      _syncConditionDefault();
    });
  }

  String _tagLabel(String id) {
    if (id == _timeTagId) return 'gpx_tag_track_point_time'.tr;
    return id;
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
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
          const SizedBox(height: 2),
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

  String _conditionLabel(KmzIgnoreCondition c) {
    switch (c) {
      case KmzIgnoreCondition.textContains:
        return 'gpx_cond_text_contains'.tr;
      case KmzIgnoreCondition.textEquals:
        return 'gpx_cond_text_equals'.tr;
      case KmzIgnoreCondition.textStartsWith:
        return 'gpx_cond_text_starts_with'.tr;
      case KmzIgnoreCondition.dateIgnoreAfter:
        return 'gpx_cond_date_ignore_after'.tr;
      case KmzIgnoreCondition.dateIgnoreBefore:
        return 'gpx_cond_date_ignore_before'.tr;
      case KmzIgnoreCondition.dateIgnoreOnOrAfter:
        return 'gpx_cond_date_ignore_on_or_after'.tr;
      case KmzIgnoreCondition.dateIgnoreOnOrBefore:
        return 'gpx_cond_date_ignore_on_or_before'.tr;
    }
  }

  String _effectiveValue() {
    if (_isTimeTag) {
      if (_selectedTimeIsoFromKmz != null && _selectedTimeIsoFromKmz!.isNotEmpty) {
        return _selectedTimeIsoFromKmz!;
      }
      final d = _pickedDateTime ?? DateTime.now();
      return d.toUtc().toIso8601String();
    }
    final vals = <String>{..._selectedValues};
    if (vals.isNotEmpty) return vals.join('\n');
    if (_valueFromList.trim().isNotEmpty) return _valueFromList.trim();
    return '';
  }

  Future<void> _pickDateTime() async {
    final ctx = context;
    final now = DateTime.now();
    final d0 = _pickedDateTime ?? now;
    final d = await showAppDatePicker(
      context: ctx,
      initialDate: DateTime(d0.year, d0.month, d0.day),
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 2),
    );
    if (!ctx.mounted || d == null) return;
    final t = await showAppTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: d0.hour, minute: d0.minute),
    );
    if (!ctx.mounted || t == null) return;
    setState(() {
      _pickedDateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  void _save() {
    final v = _effectiveValue();
    if (v.isEmpty) return;
    final tag = _resolvedTag;
    final condition = _isTimeTag
        ? _condition
        : KmzIgnoreCondition.textEquals;
    Get.back(
      result: KmzIgnoreRule(
        tag: tag,
        tagKey: tag == KmzIgnoreTagKey.dynamicTag ? _selectedTagId : null,
        value: v,
        condition: condition,
      ),
    );
  }

  void _addSelectedValue() {
    final v = _valueFromList.trim();
    if (v.isEmpty) return;
    setState(() {
      if (!_selectedValues.contains(v)) _selectedValues.add(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      final pageBg = isDark ? Colors.black : ui.getLightModeBackgroundColor(ui.mainColor.value);
      final valueColor = isDark ? Colors.white : Colors.black87;
      final accent = ui.currentMainColor;
      final condOptions = KmzIgnoreRule.conditionsForTag(_resolvedTag);
      final tagIds = _availableTagIds();
      final selectedTagValue = tagIds.contains(_selectedTagId)
          ? _selectedTagId
          : (tagIds.isNotEmpty ? tagIds.first : _timeTagId);

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
          icon: const Icon(Icons.route, color: Colors.white, size: 22),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _buildRowField(
              isDark: isDark,
              label: 'gpx_ignore_tag_label'.tr,
              contentPadding: TrackClusterFieldConfig.dropdownContentPadding,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedTagValue,
                  icon: const SizedBox.shrink(),
                  dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  style: _valueStyle(valueColor),
                  items: tagIds
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text(
                            _tagLabel(id),
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
            if (_isTimeTag) ...[
              if (widget.inspect.trackWhenValuesIso.isNotEmpty)
                _buildRowField(
                  isDark: isDark,
                  label: 'gpx_ignore_value_label'.tr,
                  contentPadding: TrackClusterFieldConfig.dropdownContentPadding,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedTimeIsoFromKmz,
                      icon: const SizedBox.shrink(),
                      dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      style: _valueStyle(valueColor),
                      items: widget.inspect.trackWhenValuesIso
                          .map(
                            (iso) => DropdownMenuItem<String>(
                              value: iso,
                              child: Text(
                                iso,
                                overflow: TextOverflow.ellipsis,
                                style: _valueStyle(valueColor),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedTimeIsoFromKmz = v;
                        });
                      },
                    ),
                  ),
                ),
              if (widget.inspect.trackWhenValuesIso.isEmpty)
                _buildRowField(
                  isDark: isDark,
                  label: 'gpx_ignore_value_label'.tr,
                  onTap: _pickDateTime,
                  child: Text(
                    _pickedDateTime?.toLocal().toString() ?? '—',
                    style: _valueStyle(valueColor),
                  ),
                ),
              if (widget.inspect.trackWhenValuesIso.isNotEmpty)
                _buildRowField(
                  isDark: isDark,
                  label: 'gpx_ignore_pick_date_time'.tr,
                  onTap: () async {
                    await _pickDateTime();
                    if (!mounted) return;
                    setState(() {
                      _selectedTimeIsoFromKmz = null;
                    });
                  },
                  child: Text(
                    _pickedDateTime?.toLocal().toString() ?? '—',
                    style: _valueStyle(valueColor),
                  ),
                ),
            ] else ...[
              _buildRowField(
                isDark: isDark,
                label: 'gpx_ignore_value_label'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildValuePickers(isDark, valueColor, accent),
                ),
              ),
            ],
            if (_isTimeTag) ...[
              _buildRowField(
                isDark: isDark,
                label: 'gpx_ignore_condition_label'.tr,
                contentPadding: TrackClusterFieldConfig.dropdownContentPadding,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<KmzIgnoreCondition>(
                    isExpanded: true,
                    value: condOptions.contains(_condition)
                        ? _condition
                        : condOptions.first,
                    icon: const SizedBox.shrink(),
                    dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    style: _valueStyle(valueColor),
                    items: condOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              _conditionLabel(c),
                              overflow: TextOverflow.ellipsis,
                              style: _valueStyle(valueColor),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (c) {
                      if (c != null) setState(() => _condition = c);
                    },
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
              child: Center(
                child: ElevatedButton(
                  style: saveStyle,
                  onPressed: _save,
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
            IconButton(
              onPressed: _addSelectedValue,
              icon: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  isDark ? Colors.white : accent,
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'assets/images/ic_add.png',
                  width: 25,
                  height: 25,
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
