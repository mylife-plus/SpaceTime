import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:restart_app/restart_app.dart';
import 'package:spacetime/app/theme/app_system_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/platform/android_application_locale.dart';

import '../../../config/app_locale.dart';
import '../../../config/supported_languages.dart';
import '../../../../services/app_lock_controller.dart';

class UiController extends GetxController {
  RxBool darkMode = false.obs;
  RxBool togglePlayPause = false.obs;
  RxBool isPlaying = false.obs;
  RxString selectedLanguage = 'en'.obs;
  RxString mainColor = 'blue'.obs;

  var phoneVerificationEnabled = false.obs;

  bool isTagMode = true; // Default to tag mode

  void setTagMode(bool tagMode) {
    isTagMode = tagMode;
  }

  Future<void> setMainColor(String color) async {
    mainColor.value = color;
    await _saveMainColor(color);
    _restartAppIfMobile();
  }

  Future<void> setLanguage(String code, {bool restartAfterApply = false}) async {
    final normalized =
        kSupportedLanguages.any((l) => l.code == code) ? code : 'en';
    selectedLanguage.value = normalized;
    Get.updateLocale(appLocaleFromLanguageCode(normalized));
    await AndroidApplicationLocale.sync(normalized);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_language', normalized);
    } catch (e) {
      debugPrint('[UiController] Error saving language: $e');
    }
    if (restartAfterApply) {
      _restartAppIfMobile();
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    darkMode.value = isDark;
    await _saveDarkMode(isDark);
    AppSystemUi.syncTheme(isDark);
    _restartAppIfMobile();
  }

  void _restartAppIfMobile() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    unawaited(_restartAppOnce());
  }

  Future<void> _restartAppOnce() async {
    try {
      await Restart.restartApp();
    } catch (e) {
      debugPrint('[UiController] Restart failed: $e');
    }
  }

  /// App lock (biometrics / device PIN). Synced with [AppLockController].
  Future<void> setAppLockEnabled(bool value) async {
    phoneVerificationEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_lock_enabled', value);
      if (value) {
        // First unlock is manual so Face ID permission is not requested during
        // cold-start auto-auth (iOS can freeze).
        await prefs.remove(AppLockController.biometricReadyPrefsKey);
        await prefs.remove(AppLockController.lastAuthAtPrefsKey);
      }
      debugPrint('[UiController] App lock saved: $value');
    } catch (e) {
      debugPrint('[UiController] Error saving app lock: $e');
    }
    if (Get.isRegistered<AppLockController>()) {
      if (value) {
        unawaited(Get.find<AppLockController>().onAppLockEnabledInSettings());
      } else {
        Get.find<AppLockController>().clearLockIfDisabled();
      }
    }
  }

  // Save dark mode preference
  Future<void> _saveDarkMode(bool isDark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dark_mode', isDark);
      debugPrint('[UiController] Dark mode saved: $isDark');
    } catch (e) {
      debugPrint('[UiController] Error saving dark mode: $e');
    }
  }

  // Save main color preference
  Future<void> _saveMainColor(String color) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('main_color', color);
      debugPrint('[UiController] Main color saved: $color');
    } catch (e) {
      debugPrint('[UiController] Error saving main color: $e');
    }
  }

  // Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load dark mode (default: false)
      final savedDarkMode = prefs.getBool('dark_mode') ?? false;
      darkMode.value = savedDarkMode;

      // Load main color (default: 'blue')
      final savedMainColor = prefs.getString('main_color') ?? 'blue';
      mainColor.value = savedMainColor;

      final savedAppLock = prefs.getBool('app_lock_enabled') ?? false;
      phoneVerificationEnabled.value = savedAppLock;

      final savedLang = prefs.getString('selected_language') ?? 'en';
      if (kSupportedLanguages.any((l) => l.code == savedLang)) {
        selectedLanguage.value = savedLang;
      } else {
        selectedLanguage.value = 'en';
      }
      Get.updateLocale(appLocaleFromLanguageCode(selectedLanguage.value));
      await AndroidApplicationLocale.sync(selectedLanguage.value);

      debugPrint('[UiController] Preferences loaded - Dark mode: $savedDarkMode, Main color: $savedMainColor');
      AppSystemUi.syncTheme(darkMode.value);
    } catch (e) {
      debugPrint('[UiController] Error loading preferences: $e');
      // Use defaults if loading fails
      darkMode.value = false;
      mainColor.value = 'blue';
      AppSystemUi.syncTheme(false);
    }
  }

  Color get currentMainColor {
    switch (mainColor.value) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'purple':
        return Colors.purple;
      case 'blue':
      default:
        return Colors.blue;
    }
  }
  

  Color get currentEditIconColor {
    switch (mainColor.value) {
      case 'red':
        return Colors.red[300]!;
      case 'green':
        return Colors.green[300]!;
      case 'purple':
        return Colors.purple[300]!;
      case 'blue':
      default:
        return Colors.blue[300]!;
    }
  }

  Color get currentIconColor {
    switch (mainColor.value) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'purple':
        return Colors.purple;
      case 'blue':
      default:
        return Colors.blue;
    }
  }

  Color getLightModeBackgroundColor(String mainColor) {
    switch (mainColor.toLowerCase()) {
      case 'blue':
        return const Color(0xFFF6FAFF);
      case 'red':
        return const Color(0xFFFAE7E7);
      case 'green':
        return const Color(0xFFE8FBE8);
      case 'purple':
        return const Color(0xFFF3E9FF);
      default:
        return const Color(0xFFF6FAFF);
    }
  }

  /// Centralized dark palette (used across the app for uniformity).
  Color get darkBackgroundColor => Colors.black;

  /// Full-screen filter overlay surface (matches [MemoriesFilterOverlay]).
  /// Light mode uses fully opaque colors for every accent (blue uses a fixed
  /// hex; others use [secondaryColor], which alpha-blends to an opaque tint).
  Color get filterOverlayBackgroundColor {
    final isDark = darkMode.value;
    switch (mainColor.value) {
      case 'blue':
        return isDark
            ? const Color(0xFF001937)
            : const Color(0xFF92C3FF);
      case 'red':
      case 'green':
      case 'purple':
        if (isDark) {
          return iconColor2 ?? curentHomeIconColorsDark;
        }
        return secondaryColor ?? currentMainColor;
      default:
        return isDark
            ? const Color(0xFF001937)
            : const Color(0xFF92C3FF);
    }
  }

  /// Search overlay bar + suggestions surface (matches [SearchOverlay]).
  Color get searchOverlayBackgroundColor =>
      darkMode.value ? darkBackgroundColor : Colors.white;

  /// Base "surface" used for cards/tiles in dark mode.
  Color get darkSurfaceColor => Colors.grey[850]!;

  /// Track-upload **Preview** label: black-based in light mode, contrasting light in dark.
  Color trackUploadPreviewLabelColor(bool isDark) =>
      isDark ? Colors.white : Colors.black87;

  /// Semi-transparent overlay used for modals/overlays.
  Color get darkOverlayColor => Colors.black.withOpacity(0.5);

  ColorFilter? get rectangleColorFilter {
    if (mainColor.value == 'blue') return null;

    return ColorFilter.mode(
      currentMainColor.withOpacity(0.9),
      BlendMode.srcATop,
    );
  }

  Color? get iconColor {
    if (mainColor.value == 'blue') return null;
    return Color.alphaBlend(Colors.black.withOpacity(0.3), currentMainColor);
  }

  Color? get iconColor2 {
    if (mainColor.value == 'blue') return null;
    return Color.alphaBlend(Colors.black.withOpacity(0.5), currentMainColor);
  }

  Color? get primaryColor {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.7);
  }

  Color? get primaryColorDark {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.3);
  }

  Color? get secondaryColor {
    if (mainColor.value == 'blue') return null;
        return Color.alphaBlend(Colors.white.withOpacity(0.7), currentMainColor);

    // return currentMainColor.withOpacity(0.2);
  }

  Color? get secondaryColorDark {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.1);
  }

  Color getPopUpColors(bool isTagMode) {
    if (mainColor.value == 'blue') {
      return isTagMode ? Color(0xFFF4FFF5) : Color(0xFFF0F7FF);
    }
    return currentMainColor.withOpacity(0.1);
  }

 Color get curentHomeIconColors {
    switch (mainColor.value) {
      case 'red':
        return const Color.fromARGB(255, 210, 32, 20);
      case 'green':
        return const Color.fromARGB(255, 10, 146, 14);
      case 'purple':
        return const Color.fromARGB(255, 114, 6, 133);
      case 'blue':
      default:
        return const Color.fromARGB(255, 16, 118, 201);
    }
  }

Color get curentHomeIconColorsDark {
    switch (mainColor.value) {
      case 'red':
        return const Color.fromARGB(255, 141, 17, 8);
      case 'green':
        return const Color.fromARGB(255, 9, 114, 13);
      case 'purple':
        return const Color.fromARGB(255, 133, 10, 155);
      case 'blue':
      default:
        return const Color.fromARGB(255, 5, 36, 62);
    }
  }

   Color? get currentHomeIconColor {
    // if (mainColor.value == 'blue') return null;
    return curentHomeIconColors;
  }

  Color? get curentHomeIconColorDark {
    // if (mainColor.value == 'blue') return null;
    return curentHomeIconColorsDark;
  }


  
  final count = 0.obs;
  @override
  void onInit() {
    super.onInit();
    ever<bool>(darkMode, (_) => AppSystemUi.syncTheme(darkMode.value));
    // Load saved preferences at app launch
    _loadPreferences();
  }

  @override
  void onReady() {
    super.onReady();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSystemUi.syncTheme(darkMode.value);
    });
  }

  @override
  void onClose() {
    super.onClose();
  }

  void increment() => count.value++;
}
