import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TagMentionStorage {
  static const _tagsKey = 'custom_tags';
  static const _mentionsKey = 'custom_mentions';

  static Future<List<String>> _getList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(key);
    if (data != null) {
      return List<String>.from(jsonDecode(data));
    }
    return [];
  }

  static Future<void> _saveList(String key, List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(list));
  }

  static Future<List<String>> getTags() => _getList(_tagsKey);
  static Future<List<String>> getMentions() => _getList(_mentionsKey);

  static Future<void> addTag(String tag) async {
    final tags = await getTags();
    if (!tags.contains(tag)) {
      tags.add(tag);
      await _saveList(_tagsKey, tags);
    }
  }

  static Future<void> addMention(String mention) async {
    final mentions = await getMentions();
    if (!mentions.contains(mention)) {
      mentions.add(mention);
      await _saveList(_mentionsKey, mentions);
    }
  }

  static Future<void> editTag(String old, String updated) async {
    final tags = await getTags();
    final index = tags.indexOf(old);
    if (index != -1) {
      tags[index] = updated;
      await _saveList(_tagsKey, tags);
    }
  }

  static Future<void> editMention(String old, String updated) async {
    final mentions = await getMentions();
    final index = mentions.indexOf(old);
    if (index != -1) {
      mentions[index] = updated;
      await _saveList(_mentionsKey, mentions);
    }
  }
}
