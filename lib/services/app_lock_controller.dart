import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/shared/widgets/restart_widget.dart';

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

  /// True while [authenticate] is in flight (prevents overlapping system dialogs).
  bool _authInProgress = false;

  /// Cold-start unlock is scheduled after the first frame — not during [onInit].
  bool _coldStartUnlockScheduled = false;

  /// Next resume after opening system Settings (e.g. permission flow) skips lock once.
  bool _skipLockOnceAfterExternalSettings = false;

  /// When true, the next app resume triggers a full app restart (used after
  /// permission-settings round-trips when app lock is active to avoid hangs).
  bool _restartOnNextResume = false;

  /// True while an in-app flow has intentionally launched an external OS picker
  /// (e.g. the file/document picker). While active, app resume does NOT trigger
  /// the lock. Unlike [scheduleRestartOnNextResume] this does not restart, so the
  /// picker's awaited result survives the round-trip.
  bool _externalPickerActive = false;

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
        if (await _wasRecentlyAuthenticated()) {
          debugPrint('[AppLockController] bootstrap: skipping lock — authenticated within 10 min');
          isLocked.value = false;
          return;
        }
        isLocked.value = true;
        _scheduleColdStartAuthentication();
      }
    } catch (e) {
      debugPrint('[AppLockController] bootstrap: $e');
    } finally {
      _bootstrapDone = true;
    }
  }

  Future<void> _saveLastAuthTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _prefsKeyLastAuthAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[AppLockController] save last auth timestamp: $e');
    }
  }

  Future<bool> _wasRecentlyAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefsKeyLastAuthAt);
      if (ms == null) return false;
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
      return elapsed < _lockAfterBackgroundDuration;
    } catch (e) {
      debugPrint('[AppLockController] check recent auth: $e');
      return false;
    }
  }

  /// iOS can hang if [LocalAuthentication.authenticate] runs before the first frame
  /// (e.g. right after enabling PIN, on cold start, when Face ID permission appears).
  void _scheduleColdStartAuthentication() {
    if (_coldStartUnlockScheduled) return;
    _coldStartUnlockScheduled = true;

    void runAfterUiReady() {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!isLocked.value || _authInProgress) return;
        unawaited(authenticate(isColdStart: true));
      });
    }

    final binding = WidgetsBinding.instance;
    if (binding.platformDispatcher.views.isNotEmpty) {
      binding.addPostFrameCallback((_) => runAfterUiReady());
    } else {
      Future<void>.delayed(const Duration(milliseconds: 300), runAfterUiReady);
    }
  }

  static const _prefsKey = 'app_lock_enabled';
  /// Set after the user completes [authenticate] once (Face ID permission granted).
  static const biometricReadyPrefsKey = 'app_lock_biometric_ready';
  static const _prefsBiometricReadyKey = biometricReadyPrefsKey;
  static const _prefsKeyLastAuthAt = 'app_lock_last_auth_at';

  static const Duration _authenticateTimeout = Duration(seconds: 90);

  /// Call immediately before [openAppSettings] from permission flows so returning
  /// from Settings does not require unlock unless the 10‑minute rule applies later.
  void skipLockOnNextResumeFromSettings() {
    _skipLockOnceAfterExternalSettings = true;
  }

  /// Call before [openAppSettings] from permission flows when app lock is active.
  /// On the next resume the app restarts cleanly instead of hanging.
  void scheduleRestartOnNextResume() {
    _skipLockOnceAfterExternalSettings = true;
    _restartOnNextResume = true;
  }

  /// Call immediately BEFORE launching an external OS picker that returns a
  /// result to the app (e.g. the file/document picker), then [endExternalPickerSession]
  /// when it closes. While the session is active the lock is suppressed on resume,
  /// and the one-shot flag covers the case where resume fires after the session ends.
  void beginExternalPickerSession() {
    _externalPickerActive = true;
    _skipLockOnceAfterExternalSettings = true;
  }

  /// Re-arms the lock after an external picker opened via [beginExternalPickerSession]
  /// has closed.
  void endExternalPickerSession() {
    _externalPickerActive = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
      _lastPausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_restartOnNextResume) {
        _restartOnNextResume = false;
        unawaited(_saveLastAuthTimestamp());
        _performScheduledRestart();
        return;
      }
      unawaited(_onAppResumed());
      _recoverFromStuckAuthentication();
    }
  }

  /// iOS hangs if [Restart.restartApp] runs synchronously inside the resume
  /// transition (same "before the first frame" failure mode as cold-start
  /// auth). Defer to after the next frame + a short settle delay so the app is
  /// fully foregrounded before the view controller is torn down and rebuilt.
  void _performScheduledRestart() {
    void run() {
      Future<void>.delayed(const Duration(milliseconds: 300), () async {
        try {
          if (Platform.isIOS) {
            // `Restart.restartApp()` is unreliable on iOS (Apple forbids true
            // programmatic restarts) and leaves the app stuck on the same page.
            // Soft-restart by rebuilding the widget tree from the initial route.
            RestartWidget.restartApp();
          } else {
            await Restart.restartApp();
          }
        } catch (e) {
          debugPrint('[AppLockController] scheduled restart failed: $e');
        }
      });
    }

    final binding = WidgetsBinding.instance;
    if (binding.platformDispatcher.views.isNotEmpty) {
      binding.addPostFrameCallback((_) => run());
    } else {
      Future<void>.delayed(const Duration(milliseconds: 300), run);
    }
  }

  /// iOS can leave [authenticate] pending after the Face ID permission sheet.
  void _recoverFromStuckAuthentication() {
    if (!_authInProgress || !isLocked.value) return;
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!_authInProgress || !isLocked.value) return;
      debugPrint(
        '[AppLockController] clearing stuck auth after resume — tap Unlock to retry',
      );
      _authInProgress = false;
      authError.value = 'app_lock_error_unlock_cancelled';
    });
  }

  Future<bool> _biometricReadyForAutoUnlock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsBiometricReadyKey) != true) return false;
      if (!await _localAuth.isDeviceSupported()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;
      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (e) {
      debugPrint('[AppLockController] biometric ready check: $e');
      return false;
    }
  }

  Future<void> _markBiometricReady() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsBiometricReadyKey, true);
    } catch (e) {
      debugPrint('[AppLockController] mark biometric ready: $e');
    }
  }

  static Future<void> _clearBiometricReady() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsBiometricReadyKey);
    } catch (e) {
      debugPrint('[AppLockController] clear biometric ready: $e');
    }
  }

  Future<void> _onAppResumed() async {
    if (!_bootstrapDone) return;
    if (_authInProgress) return;
    if (_appLockDisabledOnAndroid) return;

    // An external picker (file/document picker) is/was open — don't lock on its
    // return. Consume the one-shot flag too so it can't skip an unrelated resume.
    if (_externalPickerActive) {
      _skipLockOnceAfterExternalSettings = false;
      _wentToBackground = false;
      _lastPausedAt = null;
      return;
    }

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

  /// Call when user taps Unlock on the overlay (or after cold-start UI is ready).
  Future<void> authenticate({bool isColdStart = false}) async {
    if (_authInProgress) return;

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

    _authInProgress = true;
    try {
      // Ensure a mounted view exists before presenting the system sheet.
      if (isColdStart) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      final supported = await _localAuth.isDeviceSupported();
      if (!supported) {
        authError.value = 'app_lock_error_device_not_supported';
        return;
      }

      final ok = await _localAuth
          .authenticate(
            localizedReason: 'app_lock_localized_reason'.tr,
            options: const AuthenticationOptions(
              biometricOnly: false,
              stickyAuth: true,
              sensitiveTransaction: false,
            ),
          )
          .timeout(_authenticateTimeout, onTimeout: () => false);

      if (ok) {
        isLocked.value = false;
        authError.value = null;
        await _markBiometricReady();
        unawaited(_saveLastAuthTimestamp());
      } else {
        authError.value = 'app_lock_error_unlock_cancelled';
      }
    } on TimeoutException {
      debugPrint('[AppLockController] authenticate timed out');
      authError.value = 'app_lock_error_generic';
    } catch (e) {
      debugPrint('[AppLockController] authenticate: $e');
      authError.value = 'app_lock_error_generic';
    } finally {
      _authInProgress = false;
    }
  }

  void clearLockIfDisabled() {
    isLocked.value = false;
    authError.value = null;
    unawaited(_clearBiometricReady());
  }
}
