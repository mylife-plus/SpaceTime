import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge-to-edge bars + dark/light system icon colors (status + Android nav bar).
class AppSystemUi {
  AppSystemUi._();

  static Future<void> enableEdgeToEdge() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// [statusBarColor] overrides the (transparent) status bar fill — used e.g.
  /// when the memory filter overlay is open and the bar must match its surface.
  static SystemUiOverlayStyle overlayStyle({
    required bool dark,
    Color? statusBarColor,
  }) {
    final navBg = dark ? Colors.black : Colors.white;
    final iconBrightness = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: statusBarColor ?? Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navBg,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Overlay style for screens whose TOP area is dark or a saturated color
  /// (e.g. the map's black status bar, or the add-memories main-color header):
  /// forces WHITE status-bar text/icons for contrast while keeping the Android
  /// navigation bar aligned with the app theme.
  static SystemUiOverlayStyle overlayStyleLightStatusIcons({
    required bool dark,
  }) {
    final navBg = dark ? Colors.black : Colors.white;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Android: white status icons
      statusBarBrightness: Brightness.dark, // iOS: white status text
      systemNavigationBarColor: navBg,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Status bar fill matched to a specific surface (filter/search overlays).
  static SystemUiOverlayStyle overlayStyleMatchingSurface({
    required Color surface,
    required bool darkTheme,
  }) {
    final lightStatusIcons = surface.computeLuminance() < 0.5;
    final navBg = darkTheme ? Colors.black : Colors.white;
    final navIconBrightness = darkTheme ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: surface,
      statusBarIconBrightness:
          lightStatusIcons ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          lightStatusIcons ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navBg,
      systemNavigationBarIconBrightness: navIconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Keeps Android navigation bar + status icons aligned with app theme.
  static void syncTheme(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(overlayStyle(dark: dark));
  }
}
