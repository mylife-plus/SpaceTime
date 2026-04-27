import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/widgets/appbar.dart';

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

class _KmzPastUploadPreviewViewState extends State<KmzPastUploadPreviewView> {
  late final UiController _ui;
  MemoryController? _memoryController;
  final Map<int, String> _resolvedLocations = <int, String>{};
  bool _isResolvingAll = true;

  @override
  void initState() {
    super.initState();
    _ui = Get.find<UiController>();
    _memoryController = Get.isRegistered<MemoryController>()
        ? Get.find<MemoryController>()
        : null;
    _preloadAllLocations();
  }

  Future<void> _preloadAllLocations() async {
    const batchSize = 12;
    for (var start = 0; start < widget.items.length; start += batchSize) {
      final end = (start + batchSize > widget.items.length)
          ? widget.items.length
          : start + batchSize;
      final tasks = <Future<void>>[];
      for (var i = start; i < end; i++) {
        tasks.add(_resolveAndStoreLocation(i, widget.items[i]));
      }
      await Future.wait(tasks);
    }
    if (!mounted) return;
    setState(() {
      _isResolvingAll = false;
    });
  }

  Future<void> _resolveAndStoreLocation(int index, Map<String, dynamic> item) async {
    final geo = await _resolveLocation(_memoryController, item).timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
    final fallback =
        (item[DatabaseHelper.columnTrackLogItemLocation] ?? 'Region').toString();
    _resolvedLocations[index] = _composeResolvedLocation(geo, fallback);
  }

  String _dateLabel(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final count =
        (widget.logRow[DatabaseHelper.columnTrackLogNewCount] ?? 0) as int;
    final parsed = widget.items
        .map((e) => DateTime.tryParse((e[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString())?.toLocal())
        .whereType<DateTime>()
        .toList()
      ..sort();
    final from = parsed.isEmpty ? null : parsed.first;
    final to = parsed.isEmpty ? null : parsed.last;
    final range = (from == null || to == null)
        ? '-'
        : '${_dateLabel(from)} – ${_dateLabel(to)}';

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Preview',
        icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
      ),
      backgroundColor: const Color(0xFFD7E4F5),
      body: ListView(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count Memories', style: AppFonts.medium(18, color: Colors.blue.shade700)),
                Text(range, style: AppFonts.medium(22, color: Colors.black87)),
              ],
            ),
          ),
          if (_isResolvingAll)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (var i = 0; i < widget.items.length; i++)
              _buildReadOnlyMemoryStyleCard(
                ui: _ui,
                item: widget.items[i],
                locationText: _resolvedLocations[i] ?? 'Region',
              ),
        ],
      ),
    );
  }

  String _monthShort(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  Widget _buildReadOnlyMemoryStyleCard({
    required UiController ui,
    required Map<String, dynamic> item,
    required String locationText,
  }) {
    final dt = DateTime.tryParse(
      (item[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString(),
    )?.toLocal();
    final hh = dt == null
        ? '--:--'
        : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dayMon = dt == null
        ? '-'
        : '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
    final yr = dt == null ? '' : '${dt.year}';

    return Obx(() {
      final isDark = ui.darkMode.value;
      final headerBg = isDark
          ? (ui.mainColor.value == 'blue' ? const Color(0xFF002E68) : ui.primaryColor)
          : (ui.secondaryColor ?? const Color(0xFFDEEDFF));
      final headerText = isDark ? Colors.white : ui.currentMainColor;
      final bodyText = isDark ? Colors.white : Colors.black87;
      final bodyBg = isDark ? Colors.black : Colors.white;

      return Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    hh,
                    style: AppFonts.bold(16, color: headerText),
                  ),
                  Row(
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
    if (primary.isEmpty) primary = fallbackLocation.trim().isEmpty ? 'Region' : fallbackLocation.trim();

    return flag.isEmpty ? primary : '$flag $primary';
  }

  Future<Map<String, dynamic>?> _resolveLocation(
    MemoryController? memoryController,
    Map<String, dynamic> item,
  ) async {
    if (memoryController == null) return null;
    final lat = (item[DatabaseHelper.columnTrackLogItemLat] as num?)?.toDouble();
    final lng = (item[DatabaseHelper.columnTrackLogItemLng] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return memoryController.reverseGeocodeCoordinates(lat, lng);
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
}
