import 'package:flutter/foundation.dart';
import '../models/contact_group_model.dart';
import '../services/memory_db.dart';

class ContactGroupService {
  static final ContactGroupService _instance = ContactGroupService._internal();
  factory ContactGroupService() => _instance;
  ContactGroupService._internal();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Add a new custom contact group
  Future<ContactGroup?> addCustomGroup(
    String name, {
    int? parentId,
  }) async {
    try {
      debugPrint(
        '[ContactGroupService][addCustomGroup] Adding custom group: $name, parentId: $parentId',
      );

      final now = DateTime.now();
      final group = ContactGroup(
        name: name.trim(),
        parentId: parentId,
        isCustom: true,
        createdAt: now,
        updatedAt: now,
      );

      final groupId = await _databaseHelper.insertContactGroup(group.toMap());

      if (groupId > 0) {
        final createdGroup = group.copyWith(id: groupId);
        debugPrint(
          '[ContactGroupService][addCustomGroup] Successfully added group with ID: $groupId',
        );
        return createdGroup;
      } else {
        debugPrint(
          '[ContactGroupService][addCustomGroup] Failed to add group',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[ContactGroupService][addCustomGroup] Error: $e');
      return null;
    }
  }

  /// Update an existing contact group
  Future<bool> updateGroup(
    int groupId,
    String name,
  ) async {
    try {
      debugPrint('[ContactGroupService][updateGroup] ===== UPDATE GROUP STARTED =====');
      debugPrint('[ContactGroupService][updateGroup] Input parameters:');
      debugPrint('  - Group ID: $groupId (type: ${groupId.runtimeType})');
      debugPrint('  - Name: "$name" (type: ${name.runtimeType})');
      debugPrint('  - Name length: ${name.length}');
      debugPrint('  - Name trimmed: "${name.trim()}"');
      debugPrint('  - Name trimmed length: ${name.trim().length}');

      final updateData = {
        'contact_group_name': name.trim(),
        'contact_group_updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint('[ContactGroupService][updateGroup] Update data: $updateData');
      debugPrint('[ContactGroupService][updateGroup] 🔄 Calling database helper...');

      final updatedRows = await _databaseHelper.updateContactGroup(
        groupId,
        updateData,
      );

      debugPrint('[ContactGroupService][updateGroup] Database response: $updatedRows rows affected');
      final success = updatedRows > 0;
      debugPrint('[ContactGroupService][updateGroup] Final result: ${success ? '✅ SUCCESS' : '❌ FAILED'}');

      return success;
    } catch (e) {
      debugPrint('[ContactGroupService][updateGroup] ❌ EXCEPTION CAUGHT: $e');
      debugPrint('[ContactGroupService][updateGroup] Exception type: ${e.runtimeType}');
      debugPrint('[ContactGroupService][updateGroup] Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Delete a contact group
  Future<bool> deleteGroup(int groupId) async {
    try {
      debugPrint(
        '[ContactGroupService][deleteGroup] Deleting group ID: $groupId',
      );

      final deletedRows = await _databaseHelper.deleteContactGroup(groupId);
      final success = deletedRows > 0;

      debugPrint(
        '[ContactGroupService][deleteGroup] Delete ${success ? 'successful' : 'failed'}, rows affected: $deletedRows',
      );

      return success;
    } catch (e) {
      debugPrint('[ContactGroupService][deleteGroup] Error: $e');
      return false;
    }
  }

  /// Get all contact groups in hierarchical structure
  Future<List<ContactGroup>> getAllGroupsHierarchical() async {
    try {
      debugPrint(
        '[ContactGroupService][getAllGroupsHierarchical] Fetching hierarchical groups',
      );

      // Get main groups only (without subgroups)
      final mainGroupMaps = await _databaseHelper.getMainContactGroups();
      debugPrint(
        '[ContactGroupService][getAllGroupsHierarchical] Got ${mainGroupMaps.length} main group maps',
      );

      final List<ContactGroup> hierarchicalGroups = [];

      for (final mainGroupMap in mainGroupMaps) {
        final mainGroup = ContactGroup.fromMap(mainGroupMap);
        debugPrint(
          '[ContactGroupService][getAllGroupsHierarchical] Processing main group: ${mainGroup.name} (ID: ${mainGroup.id})',
        );

        // Get subgroups for this main group
        final subgroupMaps = await _databaseHelper.getSubContactGroups(mainGroup.id!);
        debugPrint(
          '[ContactGroupService][getAllGroupsHierarchical] Got ${subgroupMaps.length} subgroups for ${mainGroup.name}',
        );

        final subgroups = ContactGroupHelper.fromMapList(subgroupMaps);

        // Create main group with subgroups
        final mainGroupWithSubgroups = mainGroup.copyWith(subgroups: subgroups);
        hierarchicalGroups.add(mainGroupWithSubgroups);
      }

      debugPrint(
        '[ContactGroupService][getAllGroupsHierarchical] Built ${hierarchicalGroups.length} hierarchical groups',
      );

      return hierarchicalGroups;
    } catch (e) {
      debugPrint(
        '[ContactGroupService][getAllGroupsHierarchical] Error: $e',
      );
      return [];
    }
  }

  /// Get all contact groups as flat list
  Future<List<ContactGroup>> getAllGroupsFlat() async {
    try {
      debugPrint('[ContactGroupService][getAllGroupsFlat] Fetching all groups');

      final groupMaps = await _databaseHelper.getAllContactGroups();
      final groups = ContactGroupHelper.fromMapList(groupMaps);

      debugPrint(
        '[ContactGroupService][getAllGroupsFlat] Retrieved ${groups.length} groups',
      );

      return groups;
    } catch (e) {
      debugPrint('[ContactGroupService][getAllGroupsFlat] Error: $e');
      return [];
    }
  }

  /// Get main contact groups only
  Future<List<ContactGroup>> getMainGroups() async {
    try {
      debugPrint('[ContactGroupService][getMainGroups] Fetching main groups');

      final groupMaps = await _databaseHelper.getMainContactGroups();
      final groups = ContactGroupHelper.fromMapList(groupMaps);

      debugPrint(
        '[ContactGroupService][getMainGroups] Retrieved ${groups.length} main groups',
      );

      return groups;
    } catch (e) {
      debugPrint('[ContactGroupService][getMainGroups] Error: $e');
      return [];
    }
  }

  /// Get subgroups for a specific main group
  Future<List<ContactGroup>> getSubgroups(int mainGroupId) async {
    try {
      debugPrint(
        '[ContactGroupService][getSubgroups] Fetching subgroups for main group ID: $mainGroupId',
      );

      final subgroupMaps = await _databaseHelper.getSubContactGroups(mainGroupId);
      final subgroups = ContactGroupHelper.fromMapList(subgroupMaps);

      debugPrint(
        '[ContactGroupService][getSubgroups] Retrieved ${subgroups.length} subgroups',
      );

      return subgroups;
    } catch (e) {
      debugPrint('[ContactGroupService][getSubgroups] Error: $e');
      return [];
    }
  }

  /// Get a specific contact group by ID
  Future<ContactGroup?> getGroupById(int groupId) async {
    try {
      debugPrint(
        '[ContactGroupService][getGroupById] Fetching group with ID: $groupId',
      );

      final groupMap = await _databaseHelper.getContactGroupById(groupId);
      if (groupMap != null) {
        final group = ContactGroup.fromMap(groupMap);
        debugPrint(
          '[ContactGroupService][getGroupById] Found group: ${group.name}',
        );
        return group;
      } else {
        debugPrint(
          '[ContactGroupService][getGroupById] Group not found with ID: $groupId',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[ContactGroupService][getGroupById] Error: $e');
      return null;
    }
  }

  /// Initialize contact groups if needed
  Future<void> initializeGroupsIfNeeded() async {
    try {
      debugPrint(
        '[ContactGroupService][initializeGroupsIfNeeded] Checking initialization status',
      );
      await _databaseHelper.initializeContactGroupsIfNeeded();
    } catch (e) {
      debugPrint(
        '[ContactGroupService][initializeGroupsIfNeeded] Error: $e',
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
        '[ContactGroupService][getGroupsForPicker] Fetching groups for picker',
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
        '[ContactGroupService][getGroupsForPicker] Prepared ${pickerItems.length} picker items',
      );

      return pickerItems;
    } catch (e) {
      debugPrint('[ContactGroupService][getGroupsForPicker] Error: $e');
      return [];
    }
  }
}
