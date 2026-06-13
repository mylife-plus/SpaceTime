import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_locale.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

Locale appPickerLocale([UiController? ui]) {
  final c = ui ?? Get.find<UiController>();
  return appLocaleFromLanguageCode(c.selectedLanguage.value);
}

ColorScheme _pickerColorScheme(UiController ui) {
  final isDark = ui.darkMode.value;
  final accent = ui.currentMainColor;
  if (isDark) {
    return ColorScheme.dark(
      primary: accent,
      onPrimary: Colors.white,
      surface: const Color(0xFF1E1E1E),
      onSurface: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      outline: Colors.grey[600]!,
      surfaceContainerHighest: const Color(0xFF2E2E2E),
      onSurfaceVariant: Colors.white,
      surfaceTint: Colors.transparent,
      tertiary: accent,
      onTertiary: Colors.white,
    );
  }
  return ColorScheme.light(
    primary: accent,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    secondary: accent,
    onSecondary: Colors.white,
    outline: Colors.grey[300]!,
    surfaceContainerHighest: Colors.white,
    onSurfaceVariant: Colors.black,
    surfaceTint: Colors.transparent,
    tertiary: accent,
    onTertiary: Colors.white,
  );
}

/// Shared Material date/time picker chrome: [UiController] accent + dark/light surfaces,
/// and locale from app language (Material OK/Cancel + calendar strings).
ThemeData appPickerTheme(BuildContext _, UiController ui) {
  final isDark = ui.darkMode.value;
  final accent = ui.currentMainColor;
  final scheme = _pickerColorScheme(ui);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
    scaffoldBackgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      headerBackgroundColor: accent,
      headerForegroundColor: Colors.white,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return isDark ? Colors.grey[600]! : Colors.grey[400]!;
        }
        return isDark ? Colors.white : Colors.black;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
      todayForegroundColor: WidgetStateProperty.all(accent),
      todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return isDark ? Colors.white : Colors.black;
      }),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      hourMinuteTextColor: isDark ? Colors.white : Colors.black,
      dayPeriodTextColor: isDark ? Colors.white : Colors.black,
      dialHandColor: accent,
      dialBackgroundColor:
          isDark ? const Color(0xFF2E2E2E) : Colors.grey[100]!,
      dialTextColor: isDark ? Colors.white : Colors.black,
      entryModeIconColor: accent,
      helpTextStyle: TextStyle(
        color: isDark ? Colors.white54 : Colors.black54,
      ),
    ),
  );
}

Widget _wrapPicker(
  BuildContext context,
  UiController ui,
  Widget? child,
) {
  if (child == null) return const SizedBox.shrink();
  final locale = appPickerLocale(ui);
  return Localizations.override(
    context: context,
    locale: locale,
    child: Theme(
      data: appPickerTheme(context, ui),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    ),
  );
}

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
}) async {
  final ui = Get.find<UiController>();
  return showDatePicker(
    context: context,
    useRootNavigator: true,
    locale: appPickerLocale(ui),
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    initialEntryMode: initialEntryMode,
    selectableDayPredicate: selectableDayPredicate,
    helpText: helpText ?? 'app_picker_select_date'.tr,
    cancelText: cancelText ?? 'text_cancel'.tr,
    confirmText: confirmText ?? 'text_ok'.tr,
    builder: (ctx, child) => _wrapPicker(ctx, ui, child),
  );
}

Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TimePickerEntryMode initialEntryMode = TimePickerEntryMode.dial,
}) async {
  final ui = Get.find<UiController>();
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: initialEntryMode,
    cancelText: 'text_cancel'.tr,
    confirmText: 'text_ok'.tr,
    helpText: 'app_picker_select_time'.tr,
    builder: (ctx, child) => _wrapPicker(ctx, ui, child),
  );
}
