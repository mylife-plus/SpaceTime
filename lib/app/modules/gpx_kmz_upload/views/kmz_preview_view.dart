import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_import_pipeline.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';

class KmzPreviewView extends StatefulWidget {
  const KmzPreviewView({super.key, required this.candidates});

  final List<KmzMemoryCandidate> candidates;

  @override
  State<KmzPreviewView> createState() => _KmzPreviewViewState();
}

class _KmzPreviewViewState extends State<KmzPreviewView> {
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
    final sorted = [...widget.candidates]..sort((a, b) => a.when.compareTo(b.when));
    // Prevent massive concurrent reverse-geocoding calls on large GPX previews.
    const batchSize = 12;
    for (var start = 0; start < sorted.length; start += batchSize) {
      final end = (start + batchSize > sorted.length)
          ? sorted.length
          : start + batchSize;
      final tasks = <Future<void>>[];
      for (var i = start; i < end; i++) {
        tasks.add(_resolveAndStoreLocation(i, sorted[i]));
      }
      await Future.wait(tasks);
    }
    if (!mounted) return;
    setState(() {
      _isResolvingAll = false;
    });
  }

  Future<void> _resolveAndStoreLocation(int index, KmzMemoryCandidate c) async {
    final geo = await _resolveLocation(c).timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
    _resolvedLocations[index] = _composeResolvedLocation(geo);
  }

  String _monthShort(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  String _dateLabel(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.candidates]..sort((a, b) => a.when.compareTo(b.when));
    final from = sorted.isEmpty ? null : sorted.first.when.toLocal();
    final to = sorted.isEmpty ? null : sorted.last.when.toLocal();
    final range = (from == null || to == null) ? '-' : '${_dateLabel(from)} – ${_dateLabel(to)}';
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
                Text('${sorted.length} new Memories', style: AppFonts.medium(18, color: Colors.blue.shade700)),
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
            for (var i = 0; i < sorted.length; i++)
              _buildReadOnlyMemoryStyleCard(
                ui: _ui,
                candidate: sorted[i],
                locationText: _resolvedLocations[i] ?? 'Region',
              ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyMemoryStyleCard({
    required UiController ui,
    required KmzMemoryCandidate candidate,
    required String locationText,
  }) {
    final dt = candidate.when.toLocal();
    final hh = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final dayMon = '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
    final yr = '${dt.year}';

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
                  Text(hh, style: AppFonts.bold(16, color: headerText)),
                  Row(
                    children: [
                      Text(dayMon, style: AppFonts.bold(16, color: headerText)),
                      Text(
                        ' $yr',
                        style: AppFonts.bold(16, color: headerText.withValues(alpha: 0.6)),
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
                  Text(_extractFlagPrefix(locationText), style: AppFonts.medium(22, color: bodyText)),
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

  Future<Map<String, dynamic>?> _resolveLocation(KmzMemoryCandidate c) async {
    if (_memoryController == null) return null;
    return _memoryController!.reverseGeocodeCoordinates(c.latitude, c.longitude);
  }

  String _composeResolvedLocation(Map<String, dynamic>? geo) {
    final flag = (geo?['flag'] as String? ?? '').trim();
    final name = (geo?['name'] as String? ?? '').trim();
    final city = (geo?['city'] as String? ?? '').trim();
    final country = (geo?['country'] as String? ?? '').trim();

    var primary = name;
    if (primary.isEmpty) primary = city;
    if (primary.isEmpty) primary = country;
    if (primary.isEmpty) primary = 'Region';
    return flag.isEmpty ? primary : '$flag $primary';
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
