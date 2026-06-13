import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/routes/app_pages.dart';
import 'package:spacetime/app/shared/widgets/restart_widget.dart';

/// Locks the app with device biometrics / PIN when enabled in Security settings.
/// Persists [app_lock_enabled] (same key as [UiController.phoneVerificationEnabled]).
///
/// **Android:** PIN/biometric app lock is disabled (no overlay, no [LocalAuthentication]).
///
/// After a cold start, requires auth immediately if lock is enabled.
/// After leaving the app (Settings / background), iOS may SIGKILL on permission
/// changes — a persisted settings round-trip flag triggers recovery before lock UI.
class AppLockController extends GetxController with WidgetsBindingObserver {
  final isLocked = false.obs;
  final authError = RxnString();

  DateTime? _lastPausedAt;
  DateTime? _lastExternalAbsenceAt;
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

  /// True while a soft restart is scheduled or in progress — suppresses lock/auth
  /// during the resume transition and widget rebuild.
  bool _softRestartPending = false;

  Timer? _softRestartWatchdog;

  static const Duration _settingsResumeRestartThreshold = Duration(seconds: 2);
  static const Duration _settingsRoundTripMaxAge = Duration(minutes: 15);
  static const Duration _softRestartWatchdogDelay = Duration(seconds: 3);

  /// True while an in-app flow has intentionally launched an external OS picker
  /// (e.g. the file/document picker). While active, app resume does NOT trigger
  /// the lock. Unlike [scheduleRestartOnNextResume] this does not restart, so the
  /// picker's awaited result survives the round-trip.
  bool _externalPickerActive = false;

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
    _softRestartWatchdog?.cancel();
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
      if (!enabled) {
        isLocked.value = false;
        return;
      }

      // iOS SIGKILL on permission change wipes in-memory flags — recover from
      // persisted settings round-trip before showing the lock overlay.
      if (Platform.isIOS && await _consumeSettingsRoundTrip()) {
        debugPrint(
          '[AppLockController] bootstrap: post-settings cold launch — recovering',
        );
        isLocked.value = false;
        _authInProgress = false;
        authError.value = null;
        _skipLockOnceAfterExternalSettings = true;
        _runSoftRestart(relockAfter: true);
        return;
      }

      isLocked.value = true;
      _scheduleColdStartAuthentication();
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

  /// iOS can hang if [LocalAuthentication.authenticate] runs before the first frame
  /// (e.g. right after enabling PIN, on cold start, when Face ID permission appears).
  void _scheduleColdStartAuthentication() {
    if (_coldStartUnlockScheduled) return;
    _coldStartUnlockScheduled = true;

    void runAfterUiReady() {
      Future<void>.delayed(const Duration(milliseconds: 800), () async {
        if (_softRestartPending) return;
        if (!isLocked.value || _authInProgress) return;
        if (await _biometricReadyForAutoUnlock()) {
          unawaited(authenticate(isColdStart: true));
        }
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
  static const _prefsKeySettingsRoundTrip = 'app_lock_settings_round_trip_ms';
  /// Set after the user completes [authenticate] once (Face ID permission granted).
  static const biometricReadyPrefsKey = 'app_lock_biometric_ready';
  static const lastAuthAtPrefsKey = 'app_lock_last_auth_at';
  static const _prefsBiometricReadyKey = biometricReadyPrefsKey;
  static const _prefsKeyLastAuthAt = lastAuthAtPrefsKey;

  static const Duration _authenticateTimeout = Duration(seconds: 90);

  Future<void> _persistSettingsRoundTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _prefsKeySettingsRoundTrip,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[AppLockController] persist settings round-trip: $e');
    }
  }

  Future<bool> _consumeSettingsRoundTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefsKeySettingsRoundTrip);
      await prefs.remove(_prefsKeySettingsRoundTrip);
      if (ms == null) return false;
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
      return elapsed <= _settingsRoundTripMaxAge;
    } catch (e) {
      debugPrint('[AppLockController] consume settings round-trip: $e');
      return false;
    }
  }

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
    _softRestartPending = true;
    unawaited(_persistSettingsRoundTrip());
  }

  Future<bool> _isAppLockEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (e) {
      debugPrint('[AppLockController] isAppLockEnabled: $e');
      return false;
    }
  }

  /// Opens system Settings and schedules a soft restart on resume when app lock is on.
  Future<void> openExternalSettings(Future<Object?> Function() openSettings) async {
    if (!_appLockDisabledOnAndroid && await _isAppLockEnabled()) {
      scheduleRestartOnNextResume();
    }
    await openSettings();
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

  void _noteExternalAbsenceStarted() {
    _lastExternalAbsenceAt ??= DateTime.now();
  }

  void _clearExternalAbsenceMarkers() {
    _lastPausedAt = null;
    _lastExternalAbsenceAt = null;
  }

  DateTime? _externalAbsenceStartedAt() {
    final paused = _lastPausedAt;
    final inactive = _lastExternalAbsenceAt;
    if (paused == null) return inactive;
    if (inactive == null) return paused;
    return paused.isAfter(inactive) ? paused : inactive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isIOS &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden)) {
      _noteExternalAbsenceStarted();
    }
    if (state == AppLifecycleState.paused) {
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
      if (_softRestartPending) return;
      unawaited(_onAppResumed());
      _recoverFromStuckAuthentication();
    }
  }

  void _performScheduledRestart() {
    _runSoftRestart(relockAfter: false);
  }

  void _finishSoftRestart({required bool relockAfter}) {
    _softRestartWatchdog?.cancel();
    _softRestartWatchdog = null;
    _softRestartPending = false;
    _clearExternalAbsenceMarkers();

    if (!relockAfter || _appLockDisabledOnAndroid) return;

    unawaited(() async {
      if (!await _isAppLockEnabled()) return;
      isLocked.value = true;
      _coldStartUnlockScheduled = false;
      _scheduleColdStartAuthentication();
    }());
  }

  void _armSoftRestartWatchdog({required bool relockAfter}) {
    _softRestartWatchdog?.cancel();
    _softRestartWatchdog = Timer(_softRestartWatchdogDelay, () {
      if (!_softRestartPending) return;
      debugPrint(
        '[AppLockController] soft restart watchdog — retrying recovery',
      );
      _runSoftRestart(relockAfter: relockAfter, isRetry: true);
    });
  }

  /// iOS hangs if restart runs synchronously inside the resume transition.
  /// Defer to after the next frame + settle delay so the app is foregrounded first.
  void _runSoftRestart({required bool relockAfter, bool isRetry = false}) {
    if (!isRetry) {
      _softRestartPending = true;
      _authInProgress = false;
      isLocked.value = false;
      authError.value = null;
      _skipLockOnceAfterExternalSettings = true;
    }

    _armSoftRestartWatchdog(relockAfter: relockAfter);

    void run() {
      final settleMs = Platform.isIOS ? 600 : 300;
      Future<void>.delayed(Duration(milliseconds: settleMs), () async {
        try {
          if (Platform.isIOS) {
            RestartWidget.restartApp();
            Future<void>.delayed(const Duration(milliseconds: 500), () {
              try {
                Get.offAllNamed(AppPages.INITIAL);
              } catch (e) {
                debugPrint('[AppLockController] route reset after restart: $e');
              } finally {
                _finishSoftRestart(relockAfter: relockAfter);
              }
            });
          } else {
            await Restart.restartApp();
            _finishSoftRestart(relockAfter: relockAfter);
          }
        } catch (e) {
          debugPrint('[AppLockController] soft restart failed: $e');
          _finishSoftRestart(relockAfter: relockAfter);
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
    if (_softRestartPending) return;
    if (!_authInProgress || !isLocked.value) return;
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (_softRestartPending) return;
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
    if (_softRestartPending) return;
    if (_authInProgress) return;
    if (_appLockDisabledOnAndroid) return;

    if (_externalPickerActive) {
      _skipLockOnceAfterExternalSettings = false;
      _clearExternalAbsenceMarkers();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    if (!enabled) {
      _clearExternalAbsenceMarkers();
      return;
    }

    final absenceStarted = _externalAbsenceStartedAt();
    if (absenceStarted == null) return;

    final inBackground = DateTime.now().difference(absenceStarted);
    _clearExternalAbsenceMarkers();

    if (inBackground >= _settingsResumeRestartThreshold) {
      debugPrint(
        '[AppLockController] resume after ${inBackground.inSeconds}s with lock on — soft restart',
      );
      unawaited(_persistSettingsRoundTrip());
      unawaited(_saveLastAuthTimestamp());
      _performScheduledRestart();
      return;
    }

    if (_skipLockOnceAfterExternalSettings) {
      _skipLockOnceAfterExternalSettings = false;
      return;
    }

    debugPrint(
      '[AppLockController] resume after ${inBackground.inSeconds}s — skip lock (< 2s)',
    );
  }

  /// Call when user taps Unlock on the overlay (or after cold-start UI is ready).
  Future<void> authenticate({bool isColdStart = false}) async {
    if (_softRestartPending) return;
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
    unawaited(_clearLastAuthTimestamp());
  }

  /// Called when the user turns app lock on in Security settings.
  Future<void> onAppLockEnabledInSettings() async {
    if (_appLockDisabledOnAndroid) return;
    await _clearLastAuthTimestamp();
    authError.value = null;
    isLocked.value = true;
  }

  static Future<void> _clearLastAuthTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyLastAuthAt);
    } catch (e) {
      debugPrint('[AppLockController] clear last auth timestamp: $e');
    }
  }
}
