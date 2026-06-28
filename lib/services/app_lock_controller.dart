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
/// After a cold start, requires auth immediately if lock is enabled (unless
/// authenticated within [_lockAfterBackgroundDuration]).
/// After [paused] → [resumed], requires auth only if the app was in background
/// for at least [_lockAfterBackgroundDuration].
class AppLockController extends GetxController with WidgetsBindingObserver {
  static const _tag = '[AppLockController]';

  void _log(String fn, String step, [Object? detail]) {
    final suffix = detail == null ? '' : ' | $detail';
    debugPrint('$_tag.$fn $step$suffix');
  }

  final isLocked = false.obs;
  final authError = RxnString();

  bool _wentToBackground = false;
  DateTime? _lastPausedAt;
  bool _bootstrapDone = false;

  /// True while [authenticate] is in flight (prevents overlapping system dialogs).
  bool _authInProgress = false;
  final authInProgress = false.obs;

  /// Cold-start lock session — manual Unlock must use the same UI-settle path as auto auth.
  bool _coldStartLockActive = false;
  Timer? _coldStartAuthTimer;
  DateTime? _authStartedAt;

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

  static const Duration _lockAfterBackgroundDuration = Duration(minutes: 5);

  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void onInit() {
    _log('onInit', 'enter');
    super.onInit();
    _log('onInit', 'after super.onInit');
    WidgetsBinding.instance.addObserver(this);
    _log('onInit', 'after addObserver');
    unawaited(_bootstrap());
    _log('onInit', 'exit', '_bootstrap scheduled');
  }

  @override
  void onClose() {
    _log('onClose', 'enter');
    _coldStartAuthTimer?.cancel();
    _coldStartAuthTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _log('onClose', 'after removeObserver');
    super.onClose();
    _log('onClose', 'exit');
  }

  Future<void> _bootstrap() async {
    _log('_bootstrap', 'enter');
    try {
      _log('_bootstrap', 'before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      _log('_bootstrap', 'after SharedPreferences.getInstance');
      final enabled = prefs.getBool(_prefsKey) ?? false;
      _log('_bootstrap', 'after read prefs', 'enabled=$enabled');
      if (enabled) {
        _log('_bootstrap', 'before _wasRecentlyAuthenticated');
        final recent = await _wasRecentlyAuthenticated();
        _log('_bootstrap', 'after _wasRecentlyAuthenticated', 'recent=$recent');
        if (recent) {
          _log('_bootstrap', 'skipping lock — authenticated within 5 min');
          isLocked.value = false;
          _log('_bootstrap', 'exit early', 'isLocked=${isLocked.value}');
          return;
        }
        _log('_bootstrap', 'setting isLocked=true');
        isLocked.value = true;
        _coldStartLockActive = true;
        _log('_bootstrap', 'before _scheduleColdStartAuthentication');
        _scheduleColdStartAuthentication();
        _log('_bootstrap', 'after _scheduleColdStartAuthentication');
      }
    } catch (e) {
      _log('_bootstrap', 'catch', e);
    } finally {
      _bootstrapDone = true;
      _log('_bootstrap', 'finally', '_bootstrapDone=true');
    }
    _log('_bootstrap', 'exit', 'isLocked=${isLocked.value}');
  }

  Future<void> _saveLastAuthTimestamp() async {
    _log('_saveLastAuthTimestamp', 'enter');
    try {
      _log('_saveLastAuthTimestamp', 'before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      _log('_saveLastAuthTimestamp', 'after SharedPreferences.getInstance');
      final now = DateTime.now().millisecondsSinceEpoch;
      _log('_saveLastAuthTimestamp', 'before setInt', 'ms=$now');
      await prefs.setInt(_prefsKeyLastAuthAt, now);
      _log('_saveLastAuthTimestamp', 'after setInt');
    } catch (e) {
      _log('_saveLastAuthTimestamp', 'catch', e);
    }
    _log('_saveLastAuthTimestamp', 'exit');
  }

  Future<bool> _wasRecentlyAuthenticated() async {
    _log('_wasRecentlyAuthenticated', 'enter');
    try {
      _log('_wasRecentlyAuthenticated', 'before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      _log('_wasRecentlyAuthenticated', 'after SharedPreferences.getInstance');
      final ms = prefs.getInt(_prefsKeyLastAuthAt);
      _log('_wasRecentlyAuthenticated', 'after getInt', 'ms=$ms');
      if (ms == null) {
        _log('_wasRecentlyAuthenticated', 'exit', 'result=false (no timestamp)');
        return false;
      }
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
      _log('_wasRecentlyAuthenticated', 'elapsed computed', 'elapsed=${elapsed.inSeconds}s');
      final result = elapsed < _lockAfterBackgroundDuration;
      _log('_wasRecentlyAuthenticated', 'exit', 'result=$result');
      return result;
    } catch (e) {
      _log('_wasRecentlyAuthenticated', 'catch', e);
      _log('_wasRecentlyAuthenticated', 'exit', 'result=false');
      return false;
    }
  }

  /// iOS can hang if [LocalAuthentication.authenticate] runs before the first frame
  /// (e.g. right after enabling PIN, on cold start, when Face ID permission appears).
  void _scheduleColdStartAuthentication() {
    _log('_scheduleColdStartAuthentication', 'enter', '_coldStartUnlockScheduled=$_coldStartUnlockScheduled');
    if (_coldStartUnlockScheduled) {
      _log('_scheduleColdStartAuthentication', 'exit early', 'already scheduled');
      return;
    }
    _coldStartUnlockScheduled = true;
    _log('_scheduleColdStartAuthentication', 'after _coldStartUnlockScheduled=true');

    void runAfterUiReady() {
      _log('_scheduleColdStartAuthentication.runAfterUiReady', 'enter');
      _coldStartAuthTimer?.cancel();
      _coldStartAuthTimer = Timer(const Duration(milliseconds: 800), () {
        _coldStartAuthTimer = null;
        _log('_scheduleColdStartAuthentication.runAfterUiReady', 'delayed callback', 'isLocked=${isLocked.value} _authInProgress=$_authInProgress');
        if (!isLocked.value || _authInProgress) {
          _log('_scheduleColdStartAuthentication.runAfterUiReady', 'skip authenticate');
          return;
        }
        _log('_scheduleColdStartAuthentication.runAfterUiReady', 'calling authenticate(isColdStart: true)');
        unawaited(authenticate(isColdStart: true));
      });
      _log('_scheduleColdStartAuthentication.runAfterUiReady', 'exit', 'delay scheduled');
    }

    final binding = WidgetsBinding.instance;
    _log('_scheduleColdStartAuthentication', 'views.isNotEmpty=${binding.platformDispatcher.views.isNotEmpty}');
    if (binding.platformDispatcher.views.isNotEmpty) {
      binding.addPostFrameCallback((_) {
        _log('_scheduleColdStartAuthentication', 'postFrameCallback fired');
        runAfterUiReady();
      });
      _log('_scheduleColdStartAuthentication', 'exit', 'postFrameCallback registered');
    } else {
      Future<void>.delayed(const Duration(milliseconds: 300), runAfterUiReady);
      _log('_scheduleColdStartAuthentication', 'exit', '300ms delay scheduled (no views)');
    }
  }

  static const _prefsKey = 'app_lock_enabled';
  /// Set after the user completes [authenticate] once (Face ID permission granted).
  static const biometricReadyPrefsKey = 'app_lock_biometric_ready';
  static const lastAuthAtPrefsKey = 'app_lock_last_auth_at';
  static const _prefsBiometricReadyKey = biometricReadyPrefsKey;
  static const _prefsKeyLastAuthAt = lastAuthAtPrefsKey;

  static const Duration _authenticateTimeout = Duration(seconds: 90);

  /// Call immediately before [openAppSettings] from permission flows so returning
  /// from Settings does not require unlock unless the 5‑minute rule applies later.
  void skipLockOnNextResumeFromSettings() {
    _log('skipLockOnNextResumeFromSettings', 'enter', '_skipLockOnceAfterExternalSettings=$_skipLockOnceAfterExternalSettings');
    _skipLockOnceAfterExternalSettings = true;
    _log('skipLockOnNextResumeFromSettings', 'exit', '_skipLockOnceAfterExternalSettings=true');
  }

  /// Call before [openAppSettings] from permission flows when app lock is active.
  /// On the next resume the app restarts cleanly instead of hanging.
  void scheduleRestartOnNextResume() {
    _log('scheduleRestartOnNextResume', 'enter');
    _skipLockOnceAfterExternalSettings = true;
    _log('scheduleRestartOnNextResume', 'after _skipLockOnceAfterExternalSettings=true');
    _restartOnNextResume = true;
    _log('scheduleRestartOnNextResume', 'exit', '_restartOnNextResume=true');
  }

  /// Call immediately BEFORE launching an external OS picker that returns a
  /// result to the app (e.g. the file/document picker), then [endExternalPickerSession]
  /// when it closes. While the session is active the lock is suppressed on resume,
  /// and the one-shot flag covers the case where resume fires after the session ends.
  void beginExternalPickerSession() {
    _log('beginExternalPickerSession', 'enter');
    _externalPickerActive = true;
    _log('beginExternalPickerSession', 'after _externalPickerActive=true');
    _skipLockOnceAfterExternalSettings = true;
    _log('beginExternalPickerSession', 'exit', '_skipLockOnceAfterExternalSettings=true');
  }

  /// Re-arms the lock after an external picker opened via [beginExternalPickerSession]
  /// has closed.
  void endExternalPickerSession() {
    _log('endExternalPickerSession', 'enter', '_externalPickerActive=$_externalPickerActive');
    _externalPickerActive = false;
    _log('endExternalPickerSession', 'exit', '_externalPickerActive=false');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('didChangeAppLifecycleState', 'enter', 'state=$state');
    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
      _log('didChangeAppLifecycleState', 'after _wentToBackground=true');
      _lastPausedAt = DateTime.now();
      _log('didChangeAppLifecycleState', 'exit', 'paused at $_lastPausedAt');
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _log('didChangeAppLifecycleState', 'resumed branch', '_restartOnNextResume=$_restartOnNextResume');
      if (_restartOnNextResume) {
        _restartOnNextResume = false;
        _log('didChangeAppLifecycleState', 'after _restartOnNextResume=false');
        unawaited(_saveLastAuthTimestamp());
        _log('didChangeAppLifecycleState', 'after _saveLastAuthTimestamp scheduled');
        _performScheduledRestart();
        _log('didChangeAppLifecycleState', 'exit', 'scheduled restart');
        return;
      }
      unawaited(_onAppResumed());
      _log('didChangeAppLifecycleState', 'after _onAppResumed scheduled');
      _recoverFromStuckAuthentication();
      _log('didChangeAppLifecycleState', 'exit', 'resume handled');
    }
    _log('didChangeAppLifecycleState', 'exit', 'no action for state=$state');
  }

  /// iOS hangs if [Restart.restartApp] runs synchronously inside the resume
  /// transition (same "before the first frame" failure mode as cold-start
  /// auth). Defer to after the next frame + a short settle delay so the app is
  /// fully foregrounded before the view controller is torn down and rebuilt.
  void _performScheduledRestart() {
    _log('_performScheduledRestart', 'enter');

    void run() {
      _log('_performScheduledRestart.run', 'enter');
      Future<void>.delayed(const Duration(milliseconds: 300), () async {
        _log('_performScheduledRestart.run', 'delayed callback enter', 'platform=${Platform.operatingSystem}');
        try {
          if (Platform.isIOS) {
            _log('_performScheduledRestart.run', 'calling RestartWidget.restartApp');
            RestartWidget.restartApp();
            _log('_performScheduledRestart.run', 'after RestartWidget.restartApp');
          } else {
            _log('_performScheduledRestart.run', 'calling Restart.restartApp');
            await Restart.restartApp();
            _log('_performScheduledRestart.run', 'after Restart.restartApp');
          }
        } catch (e) {
          _log('_performScheduledRestart.run', 'catch', e);
        }
        _log('_performScheduledRestart.run', 'exit');
      });
      _log('_performScheduledRestart.run', 'exit', '300ms delay scheduled');
    }

    final binding = WidgetsBinding.instance;
    _log('_performScheduledRestart', 'views.isNotEmpty=${binding.platformDispatcher.views.isNotEmpty}');
    if (binding.platformDispatcher.views.isNotEmpty) {
      binding.addPostFrameCallback((_) {
        _log('_performScheduledRestart', 'postFrameCallback fired');
        run();
      });
      _log('_performScheduledRestart', 'exit', 'postFrameCallback registered');
    } else {
      Future<void>.delayed(const Duration(milliseconds: 300), run);
      _log('_performScheduledRestart', 'exit', '300ms delay scheduled (no views)');
    }
  }

  /// iOS can leave [authenticate] pending after the Face ID permission sheet.
  void _recoverFromStuckAuthentication() {
    _log('_recoverFromStuckAuthentication', 'enter', '_authInProgress=$_authInProgress isLocked=${isLocked.value}');
    if (!_authInProgress || !isLocked.value) {
      _log('_recoverFromStuckAuthentication', 'exit early', 'no recovery needed');
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      _log('_recoverFromStuckAuthentication', 'delayed callback', '_authInProgress=$_authInProgress isLocked=${isLocked.value}');
      if (!_authInProgress || !isLocked.value) {
        _log('_recoverFromStuckAuthentication', 'delayed exit early');
        return;
      }
      final startedAt = _authStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) <
              const Duration(seconds: 3)) {
        _log('_recoverFromStuckAuthentication', 'skip — auth still presenting');
        return;
      }
      _log('_recoverFromStuckAuthentication', 'clearing stuck auth');
      _setAuthInProgress(false);
      authError.value = 'app_lock_error_unlock_cancelled';
      _log('_recoverFromStuckAuthentication', 'after authError set');
    });
    _log('_recoverFromStuckAuthentication', 'exit', '400ms delay scheduled');
  }

  void _setAuthInProgress(bool value) {
    _authInProgress = value;
    authInProgress.value = value;
  }

  void _cancelScheduledColdStartAuth() {
    _coldStartAuthTimer?.cancel();
    _coldStartAuthTimer = null;
  }

  Future<bool> _biometricReadyForAutoUnlock() async {
    _log('_biometricReadyForAutoUnlock', 'enter');
    try {
      _log('_biometricReadyForAutoUnlock', 'before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      _log('_biometricReadyForAutoUnlock', 'after SharedPreferences.getInstance');
      final readyFlag = prefs.getBool(_prefsBiometricReadyKey);
      _log('_biometricReadyForAutoUnlock', 'biometricReadyFlag=$readyFlag');
      if (readyFlag != true) {
        _log('_biometricReadyForAutoUnlock', 'exit', 'result=false (flag not set)');
        return false;
      }
      _log('_biometricReadyForAutoUnlock', 'before isDeviceSupported');
      final supported = await _localAuth.isDeviceSupported();
      _log('_biometricReadyForAutoUnlock', 'after isDeviceSupported', 'supported=$supported');
      if (!supported) {
        _log('_biometricReadyForAutoUnlock', 'exit', 'result=false (not supported)');
        return false;
      }
      _log('_biometricReadyForAutoUnlock', 'before canCheckBiometrics');
      final canCheck = await _localAuth.canCheckBiometrics;
      _log('_biometricReadyForAutoUnlock', 'after canCheckBiometrics', 'canCheck=$canCheck');
      if (!canCheck) {
        _log('_biometricReadyForAutoUnlock', 'exit', 'result=false (cannot check)');
        return false;
      }
      _log('_biometricReadyForAutoUnlock', 'before getAvailableBiometrics');
      final types = await _localAuth.getAvailableBiometrics();
      _log('_biometricReadyForAutoUnlock', 'after getAvailableBiometrics', 'types=$types');
      final result = types.isNotEmpty;
      _log('_biometricReadyForAutoUnlock', 'exit', 'result=$result');
      return result;
    } catch (e) {
      _log('_biometricReadyForAutoUnlock', 'catch', e);
      _log('_biometricReadyForAutoUnlock', 'exit', 'result=false');
      return false;
    }
  }

  Future<void> _markBiometricReady() async {
    _log('_markBiometricReady', 'enter');
    try {
      _log('_markBiometricReady', 'before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      _log('_markBiometricReady', 'after SharedPreferences.getInstance');
      await prefs.setBool(_prefsBiometricReadyKey, true);
      _log('_markBiometricReady', 'after setBool biometric ready');
    } catch (e) {
      _log('_markBiometricReady', 'catch', e);
    }
    _log('_markBiometricReady', 'exit');
  }

  static Future<void> _clearBiometricReady() async {
    debugPrint('$_tag._clearBiometricReady enter');
    try {
      debugPrint('$_tag._clearBiometricReady before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      debugPrint('$_tag._clearBiometricReady after SharedPreferences.getInstance');
      await prefs.remove(_prefsBiometricReadyKey);
      debugPrint('$_tag._clearBiometricReady after remove biometric ready key');
    } catch (e) {
      debugPrint('$_tag._clearBiometricReady catch | $e');
    }
    debugPrint('$_tag._clearBiometricReady exit');
  }

  Future<void> _onAppResumed() async {
    _log('_onAppResumed', 'enter', '_bootstrapDone=$_bootstrapDone _authInProgress=$_authInProgress');
    if (!_bootstrapDone) {
      _log('_onAppResumed', 'exit early', 'bootstrap not done');
      return;
    }
    if (_authInProgress) {
      _log('_onAppResumed', 'exit early', 'auth in progress');
      return;
    }

    // An external picker (file/document picker) is/was open — don't lock on its
    // return. Consume the one-shot flag too so it can't skip an unrelated resume.
    if (_externalPickerActive) {
      _log('_onAppResumed', 'external picker active — skipping lock');
      _skipLockOnceAfterExternalSettings = false;
      _log('_onAppResumed', 'after _skipLockOnceAfterExternalSettings=false');
      _wentToBackground = false;
      _log('_onAppResumed', 'after _wentToBackground=false');
      _lastPausedAt = null;
      _log('_onAppResumed', 'exit', 'picker session');
      return;
    }

    _log('_onAppResumed', 'before SharedPreferences.getInstance');
    final prefs = await SharedPreferences.getInstance();
    _log('_onAppResumed', 'after SharedPreferences.getInstance');
    final enabled = prefs.getBool(_prefsKey) ?? false;
    _log('_onAppResumed', 'enabled=$enabled');
    if (!enabled) {
      _wentToBackground = false;
      _log('_onAppResumed', 'after _wentToBackground=false');
      _lastPausedAt = null;
      _log('_onAppResumed', 'exit', 'lock disabled');
      return;
    }

    if (!_wentToBackground) {
      _log('_onAppResumed', 'exit early', '_wentToBackground=false');
      return;
    }

    _wentToBackground = false;
    _log('_onAppResumed', 'after _wentToBackground=false');

    if (_skipLockOnceAfterExternalSettings) {
      _log('_onAppResumed', 'skip lock once after external settings');
      _skipLockOnceAfterExternalSettings = false;
      _log('_onAppResumed', 'after _skipLockOnceAfterExternalSettings=false');
      _lastPausedAt = null;
      _log('_onAppResumed', 'exit', 'skip once');
      return;
    }

    final pausedAt = _lastPausedAt;
    _log('_onAppResumed', 'pausedAt=$pausedAt');
    _lastPausedAt = null;
    _log('_onAppResumed', 'after _lastPausedAt=null');

    if (pausedAt == null) {
      _log('_onAppResumed', 'exit early', 'pausedAt was null');
      return;
    }

    final inBackground = DateTime.now().difference(pausedAt);
    _log('_onAppResumed', 'inBackground=${inBackground.inSeconds}s');
    if (inBackground < _lockAfterBackgroundDuration) {
      _log('_onAppResumed', 'exit', 'skip lock (< 5 min)');
      return;
    }

    _log('_onAppResumed', 'showing lock after ${inBackground.inMinutes}m background');
    isLocked.value = true;
    _log('_onAppResumed', 'after isLocked=true');
    unawaited(authenticate(isColdStart: false));
    _log('_onAppResumed', 'exit', 'authenticate scheduled');
  }

  /// Call when user taps Unlock on the overlay (or after cold-start UI is ready).
  Future<void> authenticate({bool isColdStart = false}) async {
    _log('authenticate', 'enter', 'isColdStart=$isColdStart _authInProgress=$_authInProgress _coldStartLockActive=$_coldStartLockActive');
    if (_authInProgress) {
      _log('authenticate', 'exit early', 'auth already in progress');
      return;
    }

    _cancelScheduledColdStartAuth();
    authError.value = null;
    _log('authenticate', 'after authError cleared');

    if (!Platform.isAndroid && !Platform.isIOS) {
      _log('authenticate', 'unsupported platform — unlocking');
      isLocked.value = false;
      _coldStartLockActive = false;
      _log('authenticate', 'exit', 'unsupported platform');
      return;
    }

    _setAuthInProgress(true);
    _authStartedAt = DateTime.now();
    _log('authenticate', 'after _authInProgress=true');
    try {
      // iOS hangs if authenticate runs before the lock overlay has settled.
      final needsUiSettle = isColdStart || _coldStartLockActive;
      if (needsUiSettle) {
        _log('authenticate', 'UI settle — delaying 100ms');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        _log('authenticate', 'after UI settle delay');
      }

      _log('authenticate', 'before isDeviceSupported');
      final supported = await _localAuth.isDeviceSupported();
      _log('authenticate', 'after isDeviceSupported', 'supported=$supported');
      if (!supported) {
        authError.value = 'app_lock_error_device_not_supported';
        _log('authenticate', 'exit early', 'device not supported');
        return;
      }

      _log('authenticate', 'before LocalAuthentication.authenticate');
      
      final ok = await _localAuth
          .authenticate(
            localizedReason: 'app_lock_localized_reason'.tr,
            options: const AuthenticationOptions(
              biometricOnly: false,
              stickyAuth: true,
              sensitiveTransaction: false,
            ),
          )
          .timeout(_authenticateTimeout, onTimeout: () {
            _log('authenticate', 'authenticate timeout fired');
            return false;
          });
      _log('authenticate', 'after LocalAuthentication.authenticate', 'ok=$ok');

      if (ok) {
        _log('authenticate', 'success branch');
        isLocked.value = false;
        _coldStartLockActive = false;
        _log('authenticate', 'after isLocked=false');
        authError.value = null;
        _log('authenticate', 'after authError cleared');
        await _markBiometricReady();
        _log('authenticate', 'after _markBiometricReady');
        unawaited(_saveLastAuthTimestamp());
        _log('authenticate', 'after _saveLastAuthTimestamp scheduled');
      } else {
        _log('authenticate', 'failure/cancel branch');
        authError.value = 'app_lock_error_unlock_cancelled';
        _log('authenticate', 'after authError=cancelled');
      }
    } on TimeoutException {
      _log('authenticate', 'TimeoutException');
      authError.value = 'app_lock_error_generic';
      _log('authenticate', 'after authError=generic (timeout)');
    } catch (e) {
      _log('authenticate', 'catch', e);
      authError.value = 'app_lock_error_generic';
      _log('authenticate', 'after authError=generic');
    } finally {
      _setAuthInProgress(false);
      _authStartedAt = null;
      _log('authenticate', 'finally', '_authInProgress=false isLocked=${isLocked.value}');
    }
    _log('authenticate', 'exit', 'authError=${authError.value}');
  }

  /// User tapped Unlock — use cold-start settle when the app just launched locked.
  Future<void> authenticateFromUserTap() async {
    await authenticate(isColdStart: _coldStartLockActive);
  }

  /// Opens system Settings without restarting the app; skips lock once on return.
  Future<void> openExternalSettings(Future<Object?> Function() openSettings) async {
    _log('openExternalSettings', 'enter');
    skipLockOnNextResumeFromSettings();
    _log('openExternalSettings', 'after skipLockOnNextResumeFromSettings');
    await openSettings();
    _log('openExternalSettings', 'exit', 'openSettings completed');
  }

  /// User enabled app lock in Security settings — show lock, require manual unlock.
  Future<void> onAppLockEnabledInSettings() async {
    _log('onAppLockEnabledInSettings', 'enter');
    try {
      _log('onAppLockEnabledInSettings', 'before SharedPreferences.getInstance');
      final prefs = await SharedPreferences.getInstance();
      _log('onAppLockEnabledInSettings', 'after SharedPreferences.getInstance');
      await prefs.remove(_prefsKeyLastAuthAt);
      _log('onAppLockEnabledInSettings', 'after remove last auth timestamp');
    } catch (e) {
      _log('onAppLockEnabledInSettings', 'catch', e);
    }
    authError.value = null;
    _log('onAppLockEnabledInSettings', 'after authError cleared');
    isLocked.value = true;
    _log('onAppLockEnabledInSettings', 'exit', 'isLocked=true');
  }

  void clearLockIfDisabled() {
    _log('clearLockIfDisabled', 'enter', 'isLocked=${isLocked.value}');
    _cancelScheduledColdStartAuth();
    _coldStartLockActive = false;
    isLocked.value = false;
    _log('clearLockIfDisabled', 'after isLocked=false');
    authError.value = null;
    _log('clearLockIfDisabled', 'after authError cleared');
    unawaited(_clearBiometricReady());
    _log('clearLockIfDisabled', 'exit', '_clearBiometricReady scheduled');
  }
}
