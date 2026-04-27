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
  static const String _timeTagId = '__track_point_time__';

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
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = isDark ? Colors.white54 : Colors.black12;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppFonts.medium(12, color: labelColor)),
          const SizedBox(height: 2),
          child,
        ],
      ),
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
    final d = await showDatePicker(
      context: ctx,
      initialDate: DateTime(d0.year, d0.month, d0.day),
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 2),
    );
    if (!ctx.mounted || d == null) return;
    final t = await showTimePicker(
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

      return Scaffold(
        backgroundColor: pageBg,
        appBar: CustomAppBar(
          title: 'gpx_ignore_rule_editor_title'.tr,
          icon: const Icon(Icons.filter_alt_outlined, color: Colors.white, size: 22),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildRowField(
              isDark: isDark,
              label: 'gpx_ignore_tag_label'.tr,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedTagValue,
                  dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  style: AppFonts.medium(15, color: valueColor),
                  items: tagIds
                      .map((id) => DropdownMenuItem(value: id, child: Text(_tagLabel(id))))
                      .toList(),
                  onChanged: _onTagChanged,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isTimeTag) ...[
              if (widget.inspect.trackWhenValuesIso.isNotEmpty)
                _buildRowField(
                  isDark: isDark,
                  label: 'gpx_ignore_value_label'.tr,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedTimeIsoFromKmz,
                      dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      style: AppFonts.medium(14, color: valueColor),
                      items: widget.inspect.trackWhenValuesIso
                          .map(
                            (iso) => DropdownMenuItem<String>(
                              value: iso,
                              child: Text(
                                iso,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.medium(14, color: valueColor),
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
                  child: Text(
                    _pickedDateTime?.toLocal().toString() ?? '—',
                    style: AppFonts.medium(15, color: valueColor),
                  ),
                ),
              if (widget.inspect.trackWhenValuesIso.isNotEmpty)
                const SizedBox(height: 4),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: Text(
                  _pickedDateTime?.toLocal().toString() ?? '—',
                  style: AppFonts.medium(15, color: valueColor),
                ),
                trailing: Icon(Icons.event, color: accent),
                onTap: _pickDateTime,
              ),
              TextButton.icon(
                onPressed: () async {
                  await _pickDateTime();
                  if (!mounted) return;
                  setState(() {
                    _selectedTimeIsoFromKmz = null;
                  });
                },
                icon: const Icon(Icons.schedule),
                label: Text('gpx_ignore_pick_date_time'.tr),
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
              const SizedBox(height: 20),
              _buildRowField(
                isDark: isDark,
                label: 'gpx_ignore_condition_label'.tr,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<KmzIgnoreCondition>(
                    isExpanded: true,
                    value: condOptions.contains(_condition) ? _condition : condOptions.first,
                    dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    style: AppFonts.medium(14, color: valueColor),
                    items: condOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(_conditionLabel(c), overflow: TextOverflow.ellipsis),
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
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(120, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor:
                    isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                side: const BorderSide(color: Colors.blue),
              ),
              child: Text(
                'gpx_ignore_save_rule'.tr,
                style: GoogleFonts.kumbhSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue,
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
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: accent.withValues(alpha: 0.4)),
    );
    final out = <Widget>[];
    if (list.isNotEmpty) {
      var current = _valueFromList;
      if (!list.contains(current)) current = list.first;
      out.add(
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: current,
                dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                style: AppFonts.medium(14, color: valueColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark ? Colors.black : Colors.white,
                  border: border,
                ),
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
                                  Expanded(child: Text(e, overflow: TextOverflow.ellipsis)),
                                ],
                              )
                            : Text(e, overflow: TextOverflow.ellipsis),
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
            const SizedBox(width: 8),
            IconButton(
              onPressed: _addSelectedValue,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      );
      out.add(const SizedBox(height: 8));
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
                ),
                onDeleted: () {
                  setState(() {
                    _selectedValues.removeAt(i);
                  });
                },
              ),
          ],
        ),
      );
    }
    return out;
  }
}
