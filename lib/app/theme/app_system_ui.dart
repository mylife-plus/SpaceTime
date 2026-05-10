import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge-to-edge bars + dark/light system icon colors (status + Android nav bar).
class AppSystemUi {
  AppSystemUi._();

  static Future<void> enableEdgeToEdge() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  static SystemUiOverlayStyle overlayStyle({required bool dark}) {
    final navBg = dark ? Colors.black : Colors.white;
    final iconBrightness = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navBg,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Keeps Android navigation bar + status icons aligned with app theme.
  static void syncTheme(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(overlayStyle(dark: dark));
  }
}
