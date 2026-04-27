import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/kmz_past_upload_preview_view.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/widgets/appbar.dart';

class KmzPastUploadsView extends StatelessWidget {
  const KmzPastUploadsView({super.key});

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

  String _dateLabel(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    return Obx(() {
      final isDark = ui.darkMode.value;
      return Scaffold(
        backgroundColor: const Color(0xFFD7E4F5),
        appBar: CustomAppBar(
          title: 'gpx_past_uploads'.tr,
          icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseHelper.instance.queryTrackImportLogs(),
          builder: (context, snap) {
            if (!snap.hasData) {
              if (snap.hasError) {
                return Center(child: Text('${snap.error}'));
              }
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data!;
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  'No past uploads yet',
                  style: AppFonts.medium(14, color: isDark ? Colors.white70 : Colors.black54),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final added = (r[DatabaseHelper.columnTrackLogNewCount] ?? 0) as int;
                final createdIso = r[DatabaseHelper.columnTrackLogCreatedAt] as String?;
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: DatabaseHelper.instance.queryTrackImportLogItems(
                    (r[DatabaseHelper.columnTrackLogId] ?? 0) as int,
                  ),
                  builder: (context, itemsSnap) {
                    final items = itemsSnap.data ?? const <Map<String, dynamic>>[];
                    final parsed = items
                        .map((e) => DateTime.tryParse((e[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString())?.toLocal())
                        .whereType<DateTime>()
                        .toList()
                      ..sort();
                    final from = parsed.isEmpty ? null : parsed.first;
                    final to = parsed.isEmpty ? null : parsed.last;
                    final range = (from == null || to == null)
                        ? '-'
                        : '${_dateLabel(from)} – ${_dateLabel(to)}';
                    return InkWell(
                      onTap: () {
                        Get.to(() => KmzPastUploadPreviewView(logRow: r, items: items));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F3F3),
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$added Memories', style: AppFonts.medium(14, color: Colors.blue.shade700)),
                                  Text(range, style: AppFonts.medium(18, color: Colors.black87)),
                                ],
                              ),
                            ),
                            Text(_ago(createdIso), style: AppFonts.medium(16, color: Colors.grey.shade600)),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right, color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      );
    });
  }
}
