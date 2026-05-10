import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/modules/data/services/full_backup_service.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/bindings/gpx_kmz_upload_binding.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/gpx_kmz_upload_view.dart';
import 'package:spacetime/app/modules/media_gps_upload/bindings/media_gps_upload_binding.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_upload_view.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/services/memory_db.dart';

class DataController extends GetxController {
  final RxBool isBusy = false.obs;

  Future<bool?> _showThemedConfirmDialog({
    required String title,
    required String body,
    required String cancelLabel,
    required String confirmLabel,
  }) {
    return Get.dialog<bool>(
      Obx(() {
        final ui = Get.find<UiController>();
        final isDark = ui.darkMode.value;
        final accent =
            isDark ? ui.currentMainColor : (ui.primaryColor ?? Colors.blue);
        final titleColor = isDark ? Colors.white : Colors.black87;
        final bodyColor = isDark ? Colors.white70 : Colors.black87;
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey.shade800 : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            title,
            style: AppFonts.bold(18, color: titleColor),
          ),
          content: Text(
            body,
            style: AppFonts.medium(15, color: bodyColor).copyWith(height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              style: TextButton.styleFrom(foregroundColor: accent),
              child: Text(
                cancelLabel,
                style: AppFonts.medium(16, color: accent),
              ),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              style: TextButton.styleFrom(foregroundColor: accent),
              child: Text(
                confirmLabel,
                style: AppFonts.medium(16, color: accent),
              ),
            ),
          ],
        );
      }),
    );
  }

  Future<void> exportFullData() async {
    if (isBusy.value) return;
    isBusy.value = true;
    try {
      final res = await FullBackupService.exportFullBackup();
      if (!res.ok) {
        showTrSnackbar(
          res.messageKey,
          args: res.messageArgs,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
        return;
      }
      if (kIsWeb) {
        showTrSnackbar(
          res.messageKey,
          args: res.messageArgs,
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
        return;
      }
      final path = res.filePath;
      if (path != null && path.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
        await _showBackupExportSheet(
          path: path,
          captionKey: res.messageKey,
          captionArgs: res.messageArgs,
        );
      } else {
        showTrSnackbar(
          res.messageKey,
          args: res.messageArgs,
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e, st) {
      debugPrint('[DataController] exportFullData: $e\n$st');
      showTrSnackbar(
        'backup_err_export_failed',
        args: [e],
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> _showBackupExportSheet({
    required String path,
    required String captionKey,
    List<Object?> captionArgs = const [],
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      showTrSnackbar(
        'backup_snackbar_file_missing',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
      return;
    }

    await Get.bottomSheet<void>(
      Obx(() {
        final ui = Get.find<UiController>();
        final _ = ui.selectedLanguage.value;
        final isDark = ui.darkMode.value;
        final sheetBg = isDark ? Colors.grey.shade800 : Colors.white;
        final accent = ui.currentMainColor;
        final closeAccent =
            isDark ? accent : (ui.primaryColor ?? accent);
        final titleColor = isDark ? Colors.white : Colors.black87;
        final bodyColor = isDark ? Colors.white70 : Colors.black87;
        final muted = isDark ? Colors.white54 : Colors.grey.shade600;
        final hintMuted = isDark ? Colors.white38 : Colors.grey.shade700;

        return Material(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: SafeArea(bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'backup_sheet_title_ready'.tr,
                    style: AppFonts.bold(18, color: titleColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trKey(captionKey, captionArgs),
                    style: AppFonts.medium(15, color: bodyColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    path,
                    style: AppFonts.medium(12, color: muted),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (Platform.isIOS || Platform.isAndroid) ...[
                    const SizedBox(height: 6),
                    Text(
                      'backup_sheet_share_hint'.tr,
                      style: AppFonts.medium(12, color: hintMuted),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Builder(
                    builder: (btnContext) {
                      return FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Rect? shareOrigin;
                          final box = btnContext.findRenderObject() as RenderBox?;
                          if (box != null && box.hasSize) {
                            shareOrigin = box.localToGlobal(Offset.zero) & box.size;
                          }
                          final zipPath = path;
                          Get.back<void>();
                          Future<void>(() async {
                            await _invokeShareBackup(zipPath, shareOrigin);
                          });
                        },
                        icon: const Icon(Icons.share),
                        label: Text(
                          'backup_sheet_share_button'.tr,
                          style: AppFonts.medium(16, color: Colors.white),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Get.back<void>(),
                    style: TextButton.styleFrom(foregroundColor: closeAccent),
                    child: Text(
                      'text_close'.tr,
                      style: AppFonts.medium(16, color: closeAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
  }

  /// Close bottom sheet first, then share (popover cannot present over it).
  /// [shareOrigin] from the button’s [RenderBox] so iPad popover is valid.
  Future<void> _invokeShareBackup(String zipPath, Rect? shareOrigin) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final file = File(zipPath);
    if (!await file.exists()) {
      showTrSnackbar(
        'backup_snackbar_share_missing_file',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
      return;
    }

    final origin = (shareOrigin != null &&
            shareOrigin.width >= 1 &&
            shareOrigin.height >= 1)
        ? shareOrigin
        : const Rect.fromLTWH(0, 0, 1, 1);

    try {
      await Share.shareXFiles(
        [
          XFile(
            zipPath,
            name: p.basename(zipPath),
            mimeType: 'application/zip',
          ),
        ],
        subject: 'backup_share_subject'.tr,
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      debugPrint('[DataController] Share backup: $e\n$st');
      showTrSnackbar(
        'backup_snackbar_share_error',
        args: ['$e'],
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    }
  }

  Future<void> importFullData() async {
    if (isBusy.value) return;
    final confirm = await _showThemedConfirmDialog(
      title: 'backup_dialog_import_title'.tr,
      body: 'backup_dialog_import_body'.tr,
      cancelLabel: 'text_cancel'.tr,
      confirmLabel: 'backup_confirm_import'.tr,
    );
    if (confirm != true) return;

    isBusy.value = true;
    try {
      final res = await FullBackupService.importFullBackup();
      if (res.ok) {
        if (Get.isRegistered<FilterController>()) {
          Get.find<FilterController>().resetFilters();
        }
        if (Get.isRegistered<AddMemoriesController>()) {
          await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
        }
        if (Get.isRegistered<MapControllerNew>() && Get.isRegistered<FilterController>()) {
          final map = Get.find<MapControllerNew>();
          final fc = Get.find<FilterController>();
          await map.loadMemoriesFromDB(fc.filteredMemories.toList());
          map.showLoadedDataOnMap();
        }
      }
      showTrSnackbar(
        res.messageKey,
        args: res.messageArgs,
        backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } finally {
      isBusy.value = false;
    }
  }

  void openKmzGpxUpload() {
    Get.to(
      () => const GpxKmzUploadView(),
      binding: GpxKmzUploadBinding(),
    );
  }

  void openMediaGpsUpload() {
    Get.to(
      () => const MediaGpsUploadView(),
      binding: MediaGpsUploadBinding(),
    );
  }

  Future<void> eraseAllMemories() async {
    if (isBusy.value) return;
    final confirm = await _showThemedConfirmDialog(
      title: 'backup_dialog_erase_title'.tr,
      body: 'backup_dialog_erase_body'.tr,
      cancelLabel: 'text_cancel'.tr,
      confirmLabel: 'backup_confirm_erase'.tr,
    );
    if (confirm != true) return;

    isBusy.value = true;
    try {
      await DatabaseHelper.instance.clearAllMemories();

      if (Get.isRegistered<FilterController>()) {
        Get.find<FilterController>().resetFilters();
      }
      if (Get.isRegistered<AddMemoriesController>()) {
        await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
      }
      if (Get.isRegistered<MapControllerNew>() && Get.isRegistered<FilterController>()) {
        final map = Get.find<MapControllerNew>();
        final fc = Get.find<FilterController>();
        await map.loadMemoriesFromDB(fc.filteredMemories.toList());
        map.showLoadedDataOnMap();
      }

      showTrSnackbar(
        'backup_snackbar_erase_success',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
      );
    } catch (e) {
      showTrSnackbar(
        'backup_snackbar_erase_failed',
        args: [e],
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      isBusy.value = false;
    }
  }
}
