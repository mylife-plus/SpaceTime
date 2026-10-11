import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/modules/location_picker/repositories/location_picker_repository.dart';

/// Clears filter/search recents and drafts after Erase All Data.
/// Does not wipe offline map / MBTiles prefs.
Future<void> clearUserFilterPreferencesAfterErase() async {
  final prefs = await SharedPreferences.getInstance();
  await Future.wait([
    prefs.remove('recent_hashtags_filter'),
    prefs.remove('recent_individual_hashtags_filter'),
    prefs.remove('recent_hashtag_groups_filter'),
    prefs.remove('recent_contacts_filter'),
    prefs.remove('recent_individual_contacts_filter'),
    prefs.remove('recent_contact_groups_filter'),
    prefs.remove('recent_subcategories'),
    prefs.remove('recent_subgroups'),
    prefs.remove('memory_draft'),
  ]);
  try {
    await LocationPickerRepository().clearAllData();
  } catch (_) {}
}
