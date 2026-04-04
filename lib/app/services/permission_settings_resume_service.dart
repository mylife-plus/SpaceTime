import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/routes/app_pages.dart';

/// When the user opens system Settings from a permission dialog, iOS may terminate
/// the app if they change a privacy toggle. We persist the intent to return to
/// [MemoryView] and re-push it after the app cold-starts onto the map.
class PermissionSettingsResumeService {
  PermissionSettingsResumeService._();

  static const _prefsKey = 'pending_restore_memory_view_after_settings';

  static Future<void> markPendingRestoreMemoryView() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsKey, true);
    debugPrint('[PermissionSettingsResume] marked pending MemoryView restore');
  }

  /// Process was not killed — user returned to the same [MemoryView].
  static Future<void> clearPendingRestoreMemoryView() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }

  /// Call right after [Get.offAllNamed]([Routes.MAP_NEW]) (cold start / restart).
  static void scheduleOpenMemoryViewIfPending() {
    unawaited(_openMemoryWhenOnMap());
  }

  static Future<void> _openMemoryWhenOnMap() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_prefsKey) != true) return;

    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final route = Get.currentRoute;
      if (route == Routes.MEMORIES) {
        await p.remove(_prefsKey);
        debugPrint('[PermissionSettingsResume] already on MemoryView, cleared pending');
        return;
      }
      if (route == Routes.MAP_NEW) {
        await p.remove(_prefsKey);
        debugPrint('[PermissionSettingsResume] pushing MemoryView after map ready');
        Get.toNamed(Routes.MEMORIES);
        return;
      }
    }

    debugPrint(
      '[PermissionSettingsResume] timed out waiting for MAP_NEW (route=${Get.currentRoute}), clearing pending',
    );
    await p.remove(_prefsKey);
  }
}
