import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Loads [assets/l10n/{en,es,fr,de}.json] before [runApp].
class L10nLoader {
  L10nLoader._();

  static final Map<String, Map<String, String>> maps = {};

  static Future<void> init() async {
    maps.clear();
    for (final code in const ['en', 'es', 'fr', 'de']) {
      final raw = await rootBundle.loadString('assets/l10n/$code.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      maps[code] = decoded.map((k, v) => MapEntry(k, v.toString()));
    }
    final bundleRaw =
        await rootBundle.loadString('assets/l10n/place_category_bundle.json');
    final bundle = json.decode(bundleRaw) as Map<String, dynamic>;
    for (final code in const ['en', 'es', 'fr', 'de']) {
      final perLang = bundle[code] as Map<String, dynamic>?;
      if (perLang == null) continue;
      for (final e in perLang.entries) {
        maps[code]![e.key] = e.value.toString();
      }
    }
  }
}

/// GetX [Translations] backed by [L10nLoader.maps].
class SpaceTimeTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => L10nLoader.maps;
}

/// Snackbars: `title@@@message` — [showTrSnackbar] splits on this marker so GetX shows a title line and a body.
/// Do not use `@@@` in normal dialog/text keys unless they go through [showTrSnackbar].
const String kL10nSnackSplit = '@@@';

String trSubst(String template, List<Object?> args) {
  var s = template;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('\$${i + 1}', args[i].toString());
  }
  return s;
}

/// Localized string with positional `$1`, `$2`, … placeholders after [key].tr.
String trKey(String key, [List<Object?> args = const []]) {
  return trSubst(key.tr, args);
}

/// Like [trKey] but resolves [key] for [languageCode] (e.g. settings) via [trForLang].
String trKeyForLang(
  String key,
  String languageCode, [
  List<Object?> args = const [],
]) {
  return trSubst(trForLang(key, languageCode), args);
}

/// Resolves app language: [preferredCode] (e.g. settings), then [Get.locale], then `en`.
String effectiveLanguageCode([String? preferredCode]) {
  if (L10nLoader.maps.isEmpty) return 'en';
  String norm(String? s) => (s ?? '').trim().toLowerCase();
  final p = norm(preferredCode);
  if (p.isNotEmpty && L10nLoader.maps.containsKey(p)) return p;
  final g = norm(Get.locale?.languageCode);
  if (g.isNotEmpty && L10nLoader.maps.containsKey(g)) return g;
  return 'en';
}

/// Looks up [key] in [L10nLoader.maps] for [languageCode] (e.g. settings language code),
/// with English fallback. Prefer over `.tr` when [Get.locale] can lag behind settings.
String trForLang(String key, [String? languageCode]) {
  final code = effectiveLanguageCode(languageCode);
  final localized = L10nLoader.maps[code]?[key];
  if (localized != null && localized.isNotEmpty) {
    return localized;
  }
  return L10nLoader.maps['en']?[key] ?? key;
}

/// One fractional digit, locale-aware (e.g. `4.5` → `4,5` in `de`).
String formatLocaleOneDecimal(double value, [String? languageCode]) {
  final code = effectiveLanguageCode(languageCode);
  return NumberFormat.decimalPatternDigits(
    locale: code,
    decimalDigits: 1,
  ).format(value);
}

/// Integer formatting with grouping rules for [languageCode].
String formatLocaleInteger(num value, [String? languageCode]) {
  final code = effectiveLanguageCode(languageCode);
  return NumberFormat.decimalPatternDigits(
    locale: code,
    decimalDigits: 0,
  ).format(value);
}

OverlayState? _appRootOverlay() {
  final ctx = Get.key.currentContext ?? Get.context;
  if (ctx == null) return null;
  try {
    return Navigator.of(ctx, rootNavigator: true).overlay;
  } catch (_) {
    return null;
  }
}

/// Same outer margin as [Get.snackbar] defaults (Get 4.7.2 `extension_navigation`).
EdgeInsets _defaultGetSnackbarMargin() =>
    const EdgeInsets.symmetric(horizontal: 10);

EdgeInsets _resolveSnackMargin(EdgeInsets? margin) {
  return margin ?? _defaultGetSnackbarMargin();
}

/// Same blur as [Get.snackbar] default `barBlur`.
const double _kGetSnackbarBarBlur = 7.0;

/// Same border radius as [Get.snackbar] default when `borderRadius` is omitted.
const double _kGetSnackbarBorderRadius = 15;

/// Same inner padding as [GetSnackBar] default.
const EdgeInsets _kGetSnackbarPadding = EdgeInsets.all(16);

/// Matches Material [SnackBar] body: [SnackBarThemeData.contentTextStyle] or [TextTheme.bodyMedium].
TextStyle _snackbarMessageStyle(ThemeData theme, Color foreground) {
  final snack = theme.snackBarTheme;
  final base = snack.contentTextStyle ?? theme.textTheme.bodyMedium;
  return (base ?? const TextStyle()).copyWith(
    color: foreground,
    decoration: TextDecoration.none,
    decorationThickness: 0,
  );
}

/// Slightly heavier than body — same base as message, typical two-line snack title.
TextStyle _snackbarTitleStyle(ThemeData theme, Color foreground) {
  return _snackbarMessageStyle(theme, foreground).copyWith(
    fontWeight: FontWeight.w600,
  );
}

/// Toast above [showDialog] / Get dialogs (ScaffoldMessenger sits under those routes).
/// Layout matches GetX [Get.snackbar] / [GetSnackBar] (margin, radius, padding, typography, width).
void showOverlaySnackText(
  String message, {
  String title = '',
  Duration? duration,
  Color? backgroundColor,
  Color? colorText,
  EdgeInsets? margin,
  SnackPosition snackPosition = SnackPosition.BOTTOM,
  double? borderRadius,
  Widget? trailing,
}) {
  final overlay = _appRootOverlay();
  final d = duration ?? const Duration(seconds: 3);
  final bg = backgroundColor ?? Colors.grey.withValues(alpha: 0.2);
  final fg = colorText ?? Colors.black;
  final m = _resolveSnackMargin(margin);
  final rad = borderRadius ?? _kGetSnackbarBorderRadius;

  if (overlay == null) {
    if (title.isNotEmpty) {
      Get.snackbar(
        title,
        message,
        snackPosition: snackPosition,
        duration: d,
        backgroundColor: bg,
        colorText: fg,
        margin: m,
        borderRadius: rad,
        mainButton: trailing is TextButton ? trailing : null,
      );
    } else {
      Get.snackbar(
        '',
        message,
        snackPosition: snackPosition,
        duration: d,
        backgroundColor: bg,
        colorText: fg,
        margin: m,
        borderRadius: rad,
        mainButton: trailing is TextButton ? trailing : null,
      );
    }
    return;
  }

  final hasTitle = title.isNotEmpty;
  final rightPad = _kGetSnackbarPadding.right;
  final buttonPad = rightPad > 12 ? rightPad - 12.0 : 4.0;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final titleStyle = _snackbarTitleStyle(theme, fg);
      final messageStyle = _snackbarMessageStyle(theme, fg);
      final pad = MediaQuery.paddingOf(ctx);
      final viewInsets = MediaQuery.viewInsetsOf(ctx);
      final top = snackPosition == SnackPosition.TOP;
      final mq = MediaQuery.sizeOf(ctx);
      final barWidth =
          (mq.width - m.left - m.right).clamp(0.0, double.infinity).toDouble();

      return Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: m.left,
            right: m.right,
            top: top ? pad.top + m.top : m.top,
            bottom: top
                ? m.bottom
                : pad.bottom + m.bottom + viewInsets.bottom,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rad),
            child: SizedBox(
              width: barWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: _kGetSnackbarBarBlur,
                        sigmaY: _kGetSnackbarBarBlur,
                      ),
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(rad),
                    ),
                    child: Padding(
                      padding: _kGetSnackbarPadding,
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          decoration: TextDecoration.none,
                          decorationThickness: 0,
                        ),
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasTitle) Text(title, style: titleStyle),
                                if (hasTitle) const SizedBox(height: 6),
                                Text(message, style: messageStyle),
                              ],
                            ),
                          ),
                          if (trailing != null)
                            Padding(
                              padding: EdgeInsets.only(left: 8, right: buttonPad),
                              child: trailing,
                            ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  unawaited(
    Future<void>.delayed(d, () {
      try {
        entry.remove();
      } catch (_) {}
    }),
  );
}

void showTrSnackbar(
  String key, {
  List<Object?> args = const [],
  SnackPosition? snackPosition,
  Duration? duration,
  Color? backgroundColor,
  Color? colorText,
  EdgeInsets? margin,
  double? borderRadius,
  TextButton? mainButton,
}) {
  var raw = trSubst(key.tr, args);
  final i = raw.indexOf(kL10nSnackSplit);
  final pos = snackPosition ?? SnackPosition.BOTTOM;
  final dur = duration ?? const Duration(seconds: 3);
  final m = margin ?? _defaultGetSnackbarMargin();
  final rad = borderRadius ?? _kGetSnackbarBorderRadius;
  final bg = backgroundColor ?? Colors.red;
  final fg = colorText ?? Colors.white;

  if (i >= 0) {
    final title = raw.substring(0, i);
    final msg = raw.substring(i + kL10nSnackSplit.length);
    showOverlaySnackText(
      msg,
      title: title,
      snackPosition: pos,
      duration: dur,
      backgroundColor: bg,
      colorText: fg,
      margin: m,
      borderRadius: rad,
      trailing: mainButton,
    );
  } else {
    showOverlaySnackText(
      raw,
      snackPosition: pos,
      duration: dur,
      backgroundColor: bg,
      colorText: fg,
      margin: m,
      borderRadius: rad,
      trailing: mainButton,
    );
  }
}
