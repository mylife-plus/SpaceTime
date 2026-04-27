import 'package:get/get.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/data/services/full_backup_service.dart';
import 'package:flutter/material.dart';

class DataController extends GetxController {
  final RxBool isBusy = false.obs;

  Future<void> exportFullData() async {
    if (isBusy.value) return;
    isBusy.value = true;
    try {
      final res = await FullBackupService.exportFullBackup();
      showTrSnackbar(
        res.message + (res.filePath == null ? '' : '\n${res.filePath}'),
        backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> importFullData() async {
    if (isBusy.value) return;
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Import Backup'),
        content: const Text(
          'This will replace current app data with backup data. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          TextButton(onPressed: () => Get.back(result: true), child: const Text('Import')),
        ],
      ),
    );
    if (confirm != true) return;

    isBusy.value = true;
    try {
      final res = await FullBackupService.importFullBackup();
      showTrSnackbar(
        res.message,
        backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } finally {
      isBusy.value = false;
    }
  }
}
