import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locks the app with device biometrics / PIN when enabled in Security settings.
/// Persists [app_lock_enabled] (same key as [UiController.phoneVerificationEnabled]).
class AppLockController extends GetxController with WidgetsBindingObserver {
  final isLocked = false.obs;
  final authError = RxnString();

  bool _wentToBackground = false;
  bool _bootstrapDone = false;

  /// When true, the next resume after background will not show the lock (e.g. user opened
  /// system Settings from a permission dialog and is returning to the same screen).
  bool _skipLockOnceAfterExternalSettings = false;

  final LocalAuthentication _localAuth = LocalAuthentication();

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

  /// Call immediately before [openAppSettings] so returning from Settings does not
  /// treat the trip as a generic background and force unlock / lose context.
  void skipLockOnNextResumeFromSettings() {
    _skipLockOnceAfterExternalSettings = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    if (!_bootstrapDone) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    if (!enabled) {
      _wentToBackground = false;
      return;
    }
    if (_wentToBackground) {
      _wentToBackground = false;
      if (_skipLockOnceAfterExternalSettings) {
        _skipLockOnceAfterExternalSettings = false;
        return;
      }
      isLocked.value = true;
      unawaited(authenticate(isColdStart: false));
    }
  }

  /// Call when user taps Unlock on the overlay.
  Future<void> authenticate({bool isColdStart = false}) async {
    authError.value = null;

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
        localizedReason: 'Unlock SpaceTime to continue',
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
      authError.value = 'Could not unlock. Try again or check device security settings.';
    }
  }

  void clearLockIfDisabled() {
    isLocked.value = false;
    authError.value = null;
  }
}
