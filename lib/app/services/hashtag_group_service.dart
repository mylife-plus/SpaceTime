import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/hashtag_group_model.dart';
import '../services/memory_db.dart';
import '../modules/add_memories/controllers/add_memories_controller.dart';
import '../modules/memories/helpers/tagmention_helper.dart';

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

      // Check for duplicate hashtag name across all groups (case-insensitive)
      final allGroups = await getAllGroupsFlat();
      final nameLower = name.trim().toLowerCase();

      for (final group in allGroups) {
        if (group.name.toLowerCase() == nameLower) {
          debugPrint(
            '[HashtagGroupService][addCustomGroup] Duplicate hashtag name found: ${group.name}',
          );
          // Return a special marker to indicate duplicate
          // We'll use a group with id = -1 to signal duplicate
          return HashtagGroup(
            id: -1,
            name: name.trim(),
            parentId: parentId,
            isCustom: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      }

      // Additional check: If adding a main group, check if name conflicts with any subgroup
      // If adding a subgroup, check if name conflicts with its parent group
      if (parentId == null) {
        // Adding a main group - check if this name exists as any subgroup
        for (final group in allGroups) {
          if (group.parentId != null && group.name.toLowerCase() == nameLower) {
            debugPrint(
              '[HashtagGroupService][addCustomGroup] Main group name conflicts with existing subgroup: ${group.name}',
            );
            // Return id = -3 to signal main group conflicts with subgroup
            return HashtagGroup(
              id: -3,
              name: name.trim(),
              parentId: parentId,
              isCustom: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }
        }
      } else {
        // Adding a subgroup - check if name conflicts with parent group
        final parentGroup = await getGroupById(parentId);
        if (parentGroup != null && parentGroup.name.toLowerCase() == nameLower) {
          debugPrint(
            '[HashtagGroupService][addCustomGroup] Subgroup name conflicts with parent group: ${parentGroup.name}',
          );
          // Return id = -4 to signal subgroup conflicts with parent group
          return HashtagGroup(
            id: -4,
            name: name.trim(),
            parentId: parentId,
            isCustom: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      }

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

      // Get the old name before updating
      final oldGroup = await getGroupById(groupId);
      final oldName = oldGroup?.name;
      final newName = name.trim();

      debugPrint('[HashtagGroupService][updateGroup] Old name: "$oldName"');
      debugPrint('[HashtagGroupService][updateGroup] New name: "$newName"');

      // Check for duplicate hashtag name across all groups (case-insensitive) if name is being changed
      if (oldName != null && newName.toLowerCase() != oldName.toLowerCase()) {
        final allGroups = await getAllGroupsFlat();
        final nameLower = newName.toLowerCase();

        for (final group in allGroups) {
          // Skip the current group being edited
          if (group.id != groupId && group.name.toLowerCase() == nameLower) {
            debugPrint(
              '[HashtagGroupService][updateGroup] Duplicate hashtag name found: ${group.name}',
            );
            throw Exception('DUPLICATE_HASHTAG_NAME');
          }
        }

        // Additional check: If editing a main group, check if name conflicts with any subgroup
        // If editing a subgroup, check if name conflicts with its parent group
        final currentGroup = await getGroupById(groupId);
        if (currentGroup != null) {
          if (currentGroup.parentId == null) {
            // Editing a main group - check if this name exists as any subgroup
            for (final group in allGroups) {
              if (group.id != groupId && group.parentId != null && group.name.toLowerCase() == nameLower) {
                debugPrint(
                  '[HashtagGroupService][updateGroup] Main group name conflicts with existing subgroup: ${group.name}',
                );
                throw Exception('MAIN_GROUP_CONFLICTS_WITH_SUBGROUP');
              }
            }
          } else {
            // Editing a subgroup - check if name conflicts with parent group
            final parentGroup = await getGroupById(currentGroup.parentId!);
            if (parentGroup != null && parentGroup.name.toLowerCase() == nameLower) {
              debugPrint(
                '[HashtagGroupService][updateGroup] Subgroup name conflicts with parent group: ${parentGroup.name}',
              );
              throw Exception('SUBGROUP_CONFLICTS_WITH_PARENT');
            }
          }
        }
      }

      final updateData = {
        'hashtag_group_name': newName,
        'hashtag_group_updated_at': DateTime.now().toIso8601String(),
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

      // ✅ Update all memories that use this hashtag
      if (success && oldName != null && oldName != newName) {
        debugPrint('[HashtagGroupService][updateGroup] 🔄 Updating memories with hashtag...');
        await _updateMemoriesWithTag(oldName, newName);
      }

      return success;
    } catch (e) {
      debugPrint('[HashtagGroupService][updateGroup] ❌ EXCEPTION CAUGHT: $e');
      debugPrint('[HashtagGroupService][updateGroup] Exception type: ${e.runtimeType}');
      debugPrint('[HashtagGroupService][updateGroup] Stack trace: ${StackTrace.current}');
      // Rethrow duplicate exceptions so UI can handle them
      if (e.toString().contains('DUPLICATE_HASHTAG_NAME')) {
        rethrow;
      }
      return false;
    }
  }

  /// Update all memories that contain the old tag with the new tag
  Future<void> _updateMemoriesWithTag(String oldTag, String newTag) async {
    try {
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 ========================================');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 UPDATING MEMORIES WITH TAG');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 Old tag: "$oldTag"');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 New tag: "$newTag"');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 ========================================');

      final allMemories = await _databaseHelper.queryAllMemories();
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 📊 Total memories in database: ${allMemories.length}');

      int updatedCount = 0;
      int checkedCount = 0;

      for (final memory in allMemories) {
        final memoryId = memory['id'] as int;
        final tagsString = memory['tags'] as String?;
        final descriptionText = memory['description'] as String?;

        if (tagsString != null && tagsString.isNotEmpty) {
          final tags = tagsString.split(',').map((t) => t.trim()).toList();

          if (tags.contains(oldTag)) {
            checkedCount++;

            // Replace old tag with new tag in the tags field
            final updatedTags = tags.map((t) => t == oldTag ? newTag : t).toList();

            // Also replace in the description text
            String updatedDescription = descriptionText ?? '';
            if (updatedDescription.isNotEmpty) {
              updatedDescription = updatedDescription.replaceAll('#$oldTag', '#$newTag');
            }

            debugPrint('[HashtagGroupService][_updateMemoriesWithTag]    🔄 Updating memory #$memoryId');
            debugPrint('[HashtagGroupService][_updateMemoriesWithTag]       Old tags: $tags');
            debugPrint('[HashtagGroupService][_updateMemoriesWithTag]       New tags: $updatedTags');

            // Update the memory with both tags field AND description text
            await _databaseHelper.updateMemory({
              'id': memoryId,
              'tags': updatedTags.join(','),
              'description': updatedDescription,
            });

            updatedCount++;
          }
        }
      }

      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 ========================================');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] ✅ SUMMARY:');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag]    Total memories checked: ${allMemories.length}');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag]    Memories with tags: $checkedCount');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag]    Memories updated: $updatedCount');
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] 🔄 ========================================');

      // Update recently selected tags
      await TagMentionStorage.editTag(oldTag, newTag);
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] ✅ Updated recent tags');

      // Refresh the memories list in AddMemoriesController
      try {
        final addMemoriesController = Get.find<AddMemoriesController>();
        addMemoriesController.onAgainInit();
        debugPrint('[HashtagGroupService][_updateMemoriesWithTag] ✅ Refreshed AddMemoriesController');
      } catch (e) {
        debugPrint('[HashtagGroupService][_updateMemoriesWithTag] ⚠️ Could not refresh AddMemoriesController: $e');
      }
    } catch (e) {
      debugPrint('[HashtagGroupService][_updateMemoriesWithTag] ❌ Error updating memories with tag: $e');
      rethrow;
    }
  }

  /// Delete a hashtag group
  /// Returns: true if deleted, false if failed, null if has memories (cannot delete)
  Future<bool?> deleteGroup(int groupId) async {
    try {
      debugPrint(
        '[HashtagGroupService][deleteGroup] Deleting group ID: $groupId',
      );

      // First, get the group to check its name
      final group = await getGroupById(groupId);
      if (group == null) {
        debugPrint(
          '[HashtagGroupService][deleteGroup] Group not found for ID: $groupId',
        );
        return false;
      }

      // Check if any memories are using this hashtag group
      final memoryCount = await _databaseHelper.getMemoryCountForHashtagGroup(group.name);
      if (memoryCount > 0) {
        debugPrint(
          '[HashtagGroupService][deleteGroup] Cannot delete group "${group.name}" - $memoryCount memories are using it',
        );
        return null; // null indicates cannot delete due to memories
      }

      // If this is a main group, check if ANY of its subgroups have associated memories
      if (group.parentId == null) {
        final subgroups = await getSubgroups(groupId);
        for (final subgroup in subgroups) {
          final subgroupMemoryCount = await _databaseHelper.getMemoryCountForHashtagGroup(subgroup.name);
          if (subgroupMemoryCount > 0) {
            debugPrint(
              '[HashtagGroupService][deleteGroup] Cannot delete main group "${group.name}" - subgroup "${subgroup.name}" has $subgroupMemoryCount memories',
            );
            return null; // null indicates cannot delete due to memories in subgroups
          }
        }
      }

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
      debugPrint('[HashtagGroupService][getGroupById] Fetching group ID: $groupId');

      final groupMap = await _databaseHelper.getHashtagGroupById(groupId);
      if (groupMap == null) {
        debugPrint('[HashtagGroupService][getGroupById] Group not found');
        return null;
      }

      final group = HashtagGroup.fromMap(groupMap);
      debugPrint('[HashtagGroupService][getGroupById] Retrieved group: ${group.name}');

      return group;
    } catch (e) {
      debugPrint('[HashtagGroupService][getGroupById] Error: $e');
      return null;
    }
  }

  /// Get memory count for a specific hashtag group
  Future<int> getMemoryCountForGroup(String groupName) async {
    try {
      return await _databaseHelper.getMemoryCountForHashtagGroup(groupName);
    } catch (e) {
      debugPrint('[HashtagGroupService][getMemoryCountForGroup] Error: $e');
      return 0;
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
    bool includeMainGroups = false, // Categories should not show as list items by default
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
          // Add main group only if requested (categories should not show as list items by default)
          if (includeMainGroups) {
            pickerItems.add({
              'id': mainGroup.id,
              'name': mainGroup.name,
              'displayText': mainGroup.name,
              'isMainGroup': true,
              'parentId': null,
            });
          }

          // Add subgroups
          if (mainGroup.subgroups != null) {
            for (final subgroup in mainGroup.subgroups!) {
              pickerItems.add({
                'id': subgroup.id,
                'name': subgroup.name,
                'displayText': includeMainGroups ? '  ${subgroup.name}' : subgroup.name, // Indent only if main groups are included
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
