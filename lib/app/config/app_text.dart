import 'package:get/get.dart';

class AppTexts {
  AppTexts._();
  static String get settings => 'apptexts_settings'.tr;
  static String get security => 'apptexts_security'.tr;
  static String get ui => 'apptexts_ui'.tr;
  static String get data => 'apptexts_data'.tr;
  static String get hashTagGroups => 'apptexts_hashtag_groups'.tr;
  static String get contactGroups => 'apptexts_contact_groups'.tr;
  static String get places => 'apptexts_places'.tr;
  static String get feedBack => 'apptexts_feedback'.tr;

  /// Security page — app lock toggle
  static String get activePhoneVerification =>
      'apptexts_active_phone_verification_pin'.tr;

  /// ui page verifications
  static String get language => 'apptexts_language'.tr;
  static String get eng => 'apptexts_english'.tr;
  static String get darkMode => 'apptexts_dark_mode'.tr;
  static String get mainColor => 'apptexts_main_color'.tr;
  static String get blue => 'apptexts_blue'.tr;

  /// Theme / accent color picker (settings → UI).
  static String get selectThemeColor => 'title_literal_select_theme_color'.tr;

  /// Map year-marker palette (same order as [MapController.markerColors]).
  static const List<String> paletteColorL10nKeys = [
    'palette_color_blue',
    'palette_color_green',
    'palette_color_orange',
    'palette_color_purple',
    'palette_color_red',
    'palette_color_cyan',
    'palette_color_yellow',
    'palette_color_brown',
    'palette_color_blue_grey',
    'palette_color_pink',
    'palette_color_indigo',
    'palette_color_teal',
    'palette_color_deep_orange',
    'palette_color_light_green',
    'palette_color_lime',
    'palette_color_amber',
    'palette_color_deep_purple',
    'palette_color_green_accent',
    'palette_color_red_accent',
    'palette_color_blue_accent',
  ];

  static String paletteColorNameByIndex(int colorIndex) {
    final keys = paletteColorL10nKeys;
    final i = colorIndex.abs() % keys.length;
    return keys[i].tr;
  }

  static String paletteColorNameForYear(int year, int baseYear) {
    final yearDifference = year - baseYear;
    final colorIndex =
        (yearDifference % paletteColorL10nKeys.length).abs();
    return paletteColorNameByIndex(colorIndex);
  }

  /// Accent / theme storage values: `blue`, `red`, `green`, `purple`.
  static String themeColorDisplayName(String storageValue) {
    switch (storageValue.toLowerCase()) {
      case 'blue':
        return 'palette_color_blue'.tr;
      case 'red':
        return 'palette_color_red'.tr;
      case 'green':
        return 'palette_color_green'.tr;
      case 'purple':
        return 'palette_color_purple'.tr;
      default:
        return storageValue;
    }
  }

  /// data view texts
  static String get uploadGPS => 'apptexts_upload_gps_points'.tr;
  static String get uploadMedia => 'apptexts_upload_media_with_gps'.tr;
  static String get backupMemories => 'apptexts_backup_memories'.tr;
  static String get uploadMemories => 'apptexts_upload_memories'.tr;
  static String get eraseAllData => 'apptexts_erase_all_data'.tr;

  /// Hashtag Groups texts
  static String get sport => 'apptexts_sport'.tr;
  static String get exercise => 'apptexts_exercise'.tr;

  /// Contact Groups texts
  static String get family => 'apptexts_family'.tr;
  static String get homes => 'apptexts_homes'.tr;

  /// feedback page texts
  static String get discoverIntegration =>
      'apptexts_discourse_integration_webview'.tr;
  static String get web => 'apptexts_https_discourse_org'.tr;
}
