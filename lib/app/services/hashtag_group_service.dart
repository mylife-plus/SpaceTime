import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/hashtag_group_model.dart';
import '../services/memory_db.dart';

class HashtagGroupService {
  static final HashtagGroupService _instance = HashtagGroupService._internal();
  factory HashtagGroupService() => _instance;
  HashtagGroupService._internal();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Add a new custom hashtag group
  Future<HashtagGroup?> addCustomGroup(
    String name, {
    int? parentId,
  }) async {
    try {
      debugPrint(
        '[HashtagGroupService][addCustomGroup] Adding custom group: $name, parentId: $parentId',
      );

      final now = DateTime.now();
      final group = HashtagGroup(
        name: name.trim(),
        parentId: parentId,
        isCustom: true,
        createdAt: now,
        updatedAt: now,
      );

      final groupId = await _databaseHelper.insertHashtagGroup(group.toMap());

      if (groupId > 0) {
        final createdGroup = group.copyWith(id: groupId);
        debugPrint(
          '[HashtagGroupService][addCustomGroup] Successfully added group with ID: $groupId',
        );
        return createdGroup;
      } else {
        debugPrint(
          '[HashtagGroupService][addCustomGroup] Failed to add group',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[HashtagGroupService][addCustomGroup] Error: $e');
      return null;
    }
  }

  /// Update an existing hashtag group
  Future<bool> updateGroup(
    int groupId,
    String name,
  ) async {
    try {
      debugPrint('[HashtagGroupService][updateGroup] ===== UPDATE GROUP STARTED =====');
      debugPrint('[HashtagGroupService][updateGroup] Input parameters:');
      debugPrint('  - Group ID: $groupId (type: ${groupId.runtimeType})');
      debugPrint('  - Name: "$name" (type: ${name.runtimeType})');
      debugPrint('  - Name length: ${name.length}');
      debugPrint('  - Name trimmed: "${name.trim()}"');
      debugPrint('  - Name trimmed length: ${name.trim().length}');

      final updateData = {
        'name': name.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint('[HashtagGroupService][updateGroup] Update data: $updateData');
      debugPrint('[HashtagGroupService][updateGroup] 🔄 Calling database helper...');

      final updatedRows = await _databaseHelper.updateHashtagGroup(
        groupId,
        updateData,
      );

      debugPrint('[HashtagGroupService][updateGroup] Database response: $updatedRows rows affected');
      final success = updatedRows > 0;
      debugPrint('[HashtagGroupService][updateGroup] Final result: ${success ? '✅ SUCCESS' : '❌ FAILED'}');

      return success;
    } catch (e) {
      debugPrint('[HashtagGroupService][updateGroup] ❌ EXCEPTION CAUGHT: $e');
      debugPrint('[HashtagGroupService][updateGroup] Exception type: ${e.runtimeType}');
      debugPrint('[HashtagGroupService][updateGroup] Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Delete a hashtag group
  Future<bool> deleteGroup(int groupId) async {
    try {
      debugPrint(
        '[HashtagGroupService][deleteGroup] Deleting group ID: $groupId',
      );

      final deletedRows = await _databaseHelper.deleteHashtagGroup(groupId);
      final success = deletedRows > 0;

      debugPrint(
        '[HashtagGroupService][deleteGroup] Delete ${success ? 'successful' : 'failed'}, rows affected: $deletedRows',
      );

      return success;
    } catch (e) {
      debugPrint('[HashtagGroupService][deleteGroup] Error: $e');
      return false;
    }
  }

  /// Get all hashtag groups in hierarchical structure
  Future<List<HashtagGroup>> getAllGroupsHierarchical() async {
    try {
      debugPrint(
        '[HashtagGroupService][getAllGroupsHierarchical] Fetching hierarchical groups',
      );

      // Get main groups only (without subgroups)
      final mainGroupMaps = await _databaseHelper.getMainHashtagGroups();
      debugPrint(
        '[HashtagGroupService][getAllGroupsHierarchical] Got ${mainGroupMaps.length} main group maps',
      );

      final List<HashtagGroup> hierarchicalGroups = [];

      for (final mainGroupMap in mainGroupMaps) {
        final mainGroup = HashtagGroup.fromMap(mainGroupMap);
        debugPrint(
          '[HashtagGroupService][getAllGroupsHierarchical] Processing main group: ${mainGroup.name} (ID: ${mainGroup.id})',
        );

        // Get subgroups for this main group
        final subgroupMaps = await _databaseHelper.getSubHashtagGroups(mainGroup.id!);
        debugPrint(
          '[HashtagGroupService][getAllGroupsHierarchical] Got ${subgroupMaps.length} subgroups for ${mainGroup.name}',
        );

        final subgroups = HashtagGroupHelper.fromMapList(subgroupMaps);

        // Create main group with subgroups
        final mainGroupWithSubgroups = mainGroup.copyWith(subgroups: subgroups);
        hierarchicalGroups.add(mainGroupWithSubgroups);
      }

      debugPrint(
        '[HashtagGroupService][getAllGroupsHierarchical] Built ${hierarchicalGroups.length} hierarchical groups',
      );

      return hierarchicalGroups;
    } catch (e) {
      debugPrint(
        '[HashtagGroupService][getAllGroupsHierarchical] Error: $e',
      );
      return [];
    }
  }

  /// Get all hashtag groups as flat list
  Future<List<HashtagGroup>> getAllGroupsFlat() async {
    try {
      debugPrint('[HashtagGroupService][getAllGroupsFlat] Fetching all groups');

      final groupMaps = await _databaseHelper.getAllHashtagGroups();
      final groups = HashtagGroupHelper.fromMapList(groupMaps);

      debugPrint(
        '[HashtagGroupService][getAllGroupsFlat] Retrieved ${groups.length} groups',
      );

      return groups;
    } catch (e) {
      debugPrint('[HashtagGroupService][getAllGroupsFlat] Error: $e');
      return [];
    }
  }

  /// Get main hashtag groups only
  Future<List<HashtagGroup>> getMainGroups() async {
    try {
      debugPrint('[HashtagGroupService][getMainGroups] Fetching main groups');

      final groupMaps = await _databaseHelper.getMainHashtagGroups();
      final groups = HashtagGroupHelper.fromMapList(groupMaps);

      debugPrint(
        '[HashtagGroupService][getMainGroups] Retrieved ${groups.length} main groups',
      );

      return groups;
    } catch (e) {
      debugPrint('[HashtagGroupService][getMainGroups] Error: $e');
      return [];
    }
  }

  /// Get subgroups for a specific main group
  Future<List<HashtagGroup>> getSubgroups(int mainGroupId) async {
    try {
      debugPrint(
        '[HashtagGroupService][getSubgroups] Fetching subgroups for main group ID: $mainGroupId',
      );

      final subgroupMaps = await _databaseHelper.getSubHashtagGroups(mainGroupId);
      final subgroups = HashtagGroupHelper.fromMapList(subgroupMaps);

      debugPrint(
        '[HashtagGroupService][getSubgroups] Retrieved ${subgroups.length} subgroups',
      );

      return subgroups;
    } catch (e) {
      debugPrint('[HashtagGroupService][getSubgroups] Error: $e');
      return [];
    }
  }

  /// Get a specific hashtag group by ID
  Future<HashtagGroup?> getGroupById(int groupId) async {
    try {
      debugPrint(
        '[HashtagGroupService][getGroupById] Fetching group with ID: $groupId',
      );

      final groupMap = await _databaseHelper.getHashtagGroupById(groupId);
      if (groupMap != null) {
        final group = HashtagGroup.fromMap(groupMap);
        debugPrint(
          '[HashtagGroupService][getGroupById] Found group: ${group.name}',
        );
        return group;
      } else {
        debugPrint(
          '[HashtagGroupService][getGroupById] Group not found with ID: $groupId',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[HashtagGroupService][getGroupById] Error: $e');
      return null;
    }
  }

  /// Initialize hashtag groups if needed
  Future<void> initializeGroupsIfNeeded() async {
    try {
      debugPrint(
        '[HashtagGroupService][initializeGroupsIfNeeded] Checking initialization status',
      );
      await _databaseHelper.initializeHashtagGroupsIfNeeded();
    } catch (e) {
      debugPrint(
        '[HashtagGroupService][initializeGroupsIfNeeded] Error: $e',
      );
    }
  }

  /// Get groups suitable for dropdown/picker (with display text)
  Future<List<Map<String, dynamic>>> getGroupsForPicker({
    bool includeSubgroups = true,
  }) async {
    try {
      debugPrint(
        '[HashtagGroupService][getGroupsForPicker] Fetching groups for picker',
      );

      final List<Map<String, dynamic>> pickerItems = [];

      if (includeSubgroups) {
        // Get hierarchical structure
        final hierarchicalGroups = await getAllGroupsHierarchical();

        for (final mainGroup in hierarchicalGroups) {
          // Add main group
          pickerItems.add({
            'id': mainGroup.id,
            'name': mainGroup.name,
            'displayText': mainGroup.name,
            'isMainGroup': true,
            'parentId': null,
          });

          // Add subgroups
          if (mainGroup.subgroups != null) {
            for (final subgroup in mainGroup.subgroups!) {
              pickerItems.add({
                'id': subgroup.id,
                'name': subgroup.name,
                'displayText': '  ${subgroup.name}', // Indent subgroups
                'isMainGroup': false,
                'parentId': subgroup.parentId,
              });
            }
          }
        }
      } else {
        // Get main groups only
        final mainGroups = await getMainGroups();
        for (final group in mainGroups) {
          pickerItems.add({
            'id': group.id,
            'name': group.name,
            'displayText': group.name,
            'isMainGroup': true,
            'parentId': null,
          });
        }
      }

      debugPrint(
        '[HashtagGroupService][getGroupsForPicker] Prepared ${pickerItems.length} picker items',
      );

      return pickerItems;
    } catch (e) {
      debugPrint('[HashtagGroupService][getGroupsForPicker] Error: $e');
      return [];
    }
  }
}
