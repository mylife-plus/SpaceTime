import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Syncs Android per-app locales so system permission dialogs match [languageCode]
/// (en, de, es, fr). No-op on other platforms.
class AndroidApplicationLocale {
  static const MethodChannel _channel = MethodChannel('com.spacetime/app_locale');

  static Future<void> sync(String languageCode) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(
        'setApplicationLocales',
        <String, dynamic>{'languageTag': languageCode},
      );
    } catch (e, st) {
      debugPrint('[AndroidApplicationLocale] sync failed: $e\n$st');
    }
  }
}
