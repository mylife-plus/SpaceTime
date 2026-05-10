import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/track_import_deletion_refresh.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/kmz_past_upload_preview_view.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/app/widgets/track_past_upload_delete_confirm_dialog.dart';
import 'package:spacetime/app/widgets/track_upload_refresh_icon.dart';

class KmzPastUploadsView extends StatefulWidget {
  const KmzPastUploadsView({
    super.key,
    this.importSource = DatabaseHelper.trackImportSourceGpxKmz,
  });

  /// [DatabaseHelper.trackImportSourceGpxKmz] or [DatabaseHelper.trackImportSourceMediaGps].
  final String importSource;

  @override
  State<KmzPastUploadsView> createState() => _KmzPastUploadsViewState();
}

class _KmzPastUploadsViewState extends State<KmzPastUploadsView> {
  late Future<List<Map<String, dynamic>>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = DatabaseHelper.instance.queryTrackImportLogs(
      importSource: widget.importSource,
    );
  }

  Future<void> _reloadLogs() async {
    setState(() {
      _logsFuture = DatabaseHelper.instance.queryTrackImportLogs(
        importSource: widget.importSource,
      );
    });
    await _logsFuture;
  }

  Future<void> _deleteLog(Map<String, dynamic> row) async {
    final id = (row[DatabaseHelper.columnTrackLogId] as num?)?.toInt();
    if (id == null) return;
    final ok = await showTrackPastUploadDeleteConfirmDialog();
    if (ok != true) return;
    await DatabaseHelper.instance.deleteTrackImportLogAndMemories(id);
    await refreshConsumersAfterTrackImportDeletion(logTag: 'PastUploads');
    await _reloadLogs();
  }

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
      final pageBg =
          isDark ? ui.darkBackgroundColor : Colors.white;
      return Scaffold(
        backgroundColor: pageBg,
        appBar: CustomAppBar(
          title: 'gpx_past_uploads'.tr,
          icon: trackUploadRefreshAppBarIcon(),
        ),
        body: RefreshIndicator(
          onRefresh: _reloadLogs,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _logsFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                if (snap.hasError) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.3,
                        child: Center(
                          child: Text(
                            '${snap.error}',
                            style: TextStyle(
                              color:
                                  isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.35,
                      child: Center(
                        child: Text(
                          'No past uploads yet',
                          style: AppFonts.regular(
                            16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final added =
                      (r[DatabaseHelper.columnTrackLogNewCount] ?? 0) as int;
                  final createdIso =
                      r[DatabaseHelper.columnTrackLogCreatedAt] as String?;
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: DatabaseHelper.instance.queryTrackImportLogItems(
                      (r[DatabaseHelper.columnTrackLogId] ?? 0) as int,
                    ),
                    builder: (context, itemsSnap) {
                      final items =
                          itemsSnap.data ?? const <Map<String, dynamic>>[];
                      final parsed = items
                          .map(
                            (e) => DateTime.tryParse(
                              (e[DatabaseHelper.columnTrackLogItemWhen] ?? '')
                                  .toString(),
                            )?.toLocal(),
                          )
                          .whereType<DateTime>()
                          .toList()
                        ..sort();
                      final from = parsed.isEmpty ? null : parsed.first;
                      final to = parsed.isEmpty ? null : parsed.last;
                      final range = (from == null || to == null)
                          ? '-'
                          : '${_dateLabel(from)} – ${_dateLabel(to)}';
                      return InkWell(
                        onTap: () async {
                          await Get.to<void>(
                            () => KmzPastUploadPreviewView(
                              logRow: r,
                              items: items,
                            ),
                          );
                          if (mounted) await _reloadLogs();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? ui.darkSurfaceColor
                                : const Color(0xFFF3F3F3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trKey('gpx_past_upload_memories_line', [
                                        added,
                                      ]),
                                      style: AppFonts.regular(
                                        16,
                                        color: ui.currentMainColor,
                                      ),
                                    ),
                                    Text(
                                      range,
                                      style: AppFonts.regular(
                                        18,
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.87)
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _ago(createdIso),
                                style: AppFonts.regular(
                                  16,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade600,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteLog(r),
                                icon: Image.asset(
                                  'assets/images/trash.png',
                                  width: 22,
                                  height: 22,
                                ),
                              ),
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
        ),
      );
    });
  }
}
