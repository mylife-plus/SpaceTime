import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locks the app with device biometrics / PIN when enabled in Security settings.
/// Persists [app_lock_enabled] (same key as [UiController.phoneVerificationEnabled]).
///
/// **Android:** PIN/biometric app lock is disabled (no overlay, no [LocalAuthentication]).
///
/// After a cold start, requires auth immediately if lock is enabled.
/// After [paused] → [resumed], requires auth only if the app was in background
/// for at least [_lockAfterBackgroundDuration].
class AppLockController extends GetxController with WidgetsBindingObserver {
  final isLocked = false.obs;
  final authError = RxnString();

  bool _wentToBackground = false;
  DateTime? _lastPausedAt;
  bool _bootstrapDone = false;

  /// Next resume after opening system Settings (e.g. permission flow) skips lock once.
  bool _skipLockOnceAfterExternalSettings = false;

  static const Duration _lockAfterBackgroundDuration = Duration(minutes: 10);

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool get _appLockDisabledOnAndroid => Platform.isAndroid;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  Future<void> _bootstrap() async {
    try {
      if (_appLockDisabledOnAndroid) {
        isLocked.value = false;
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_prefsKey) ?? false;
      if (enabled) {
        isLocked.value = true;
        await authenticate(isColdStart: true);
      }
    } catch (e) {
      debugPrint('[AppLockController] bootstrap: $e');
    } finally {
      _bootstrapDone = true;
    }
  }

  static const _prefsKey = 'app_lock_enabled';

  /// Call immediately before [openAppSettings] from permission flows so returning
  /// from Settings does not require unlock unless the 10‑minute rule applies later.
  void skipLockOnNextResumeFromSettings() {
    _skipLockOnceAfterExternalSettings = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
      _lastPausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    if (!_bootstrapDone) return;
    if (_appLockDisabledOnAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    if (!enabled) {
      _wentToBackground = false;
      _lastPausedAt = null;
      return;
    }

    if (!_wentToBackground) return;

    _wentToBackground = false;

    if (_skipLockOnceAfterExternalSettings) {
      _skipLockOnceAfterExternalSettings = false;
      _lastPausedAt = null;
      return;
    }

    final pausedAt = _lastPausedAt;
    _lastPausedAt = null;

    if (pausedAt == null) return;

    final inBackground = DateTime.now().difference(pausedAt);
    if (inBackground < _lockAfterBackgroundDuration) {
      debugPrint(
        '[AppLockController] resume after ${inBackground.inSeconds}s — skip lock (< 10 min)',
      );
      return;
    }

    debugPrint(
      '[AppLockController] resume after ${inBackground.inMinutes}m — showing lock',
    );
    isLocked.value = true;
    unawaited(authenticate(isColdStart: false));
  }

  /// Call when user taps Unlock on the overlay.
  Future<void> authenticate({bool isColdStart = false}) async {
    authError.value = null;

    if (_appLockDisabledOnAndroid) {
      isLocked.value = false;
      authError.value = null;
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      isLocked.value = false;
      return;
    }

    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) {
        authError.value = 'This device does not support secure unlock.';
        return;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock SpaceTime',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          sensitiveTransaction: false,
        ),
      );

      if (ok) {
        isLocked.value = false;
        authError.value = null;
      } else {
        authError.value = 'Unlock was cancelled.';
      }
    } catch (e) {
      debugPrint('[AppLockController] authenticate: $e');
      authError.value = 'Could not unlock. Try again.';
    }
  }

  void clearLockIfDisabled() {
    isLocked.value = false;
    authError.value = null;
  }
}
