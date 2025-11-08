import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../models/hashtag_group_model.dart';
import '../../../services/hashtag_group_service.dart';

class HashtagGroupsController extends GetxController {
  final HashtagGroupService _hashtagGroupService = HashtagGroupService();

  final TextEditingController editController = TextEditingController();
  final RxBool isEditing = false.obs;
  final RxString editingItem = ''.obs;
  final RxString originalItem = ''.obs;

  // Hashtag groups data
  final RxList<HashtagGroup> _allGroups = <HashtagGroup>[].obs;
  final RxList<HashtagGroup> _selectedGroups = <HashtagGroup>[].obs;

  // Legacy sport hashtags for backward compatibility
  final RxList<String> sportHashtags =
      <String>[
        'football',
        'basketball',
        'tennis',
        'swimming',
        'running',
        'cycling',
      ].obs;

  // Getters
  List<HashtagGroup> get allGroups => _allGroups;
  List<HashtagGroup> get selectedGroups => _selectedGroups;

  @override
  void onInit() {
    super.onInit();
    ever(isEditing, (editing) {
      if (editing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          editController.text = editingItem.value;
          editController.selection = TextSelection.fromPosition(
            TextPosition(offset: editController.text.length),
          );
        });
      }
    });

    // Load hashtag groups
    loadHashtagGroups();
  }

  /// Load all hashtag groups from database
  Future<void> loadHashtagGroups() async {
    try {
      debugPrint('[HashtagGroupsController][loadHashtagGroups] Loading groups from database');

      final groups = await _hashtagGroupService.getAllGroupsHierarchical();
      _allGroups.assignAll(groups);

      debugPrint('[HashtagGroupsController][loadHashtagGroups] Loaded ${groups.length} groups');
    } catch (e) {
      debugPrint('[HashtagGroupsController][loadHashtagGroups] Error loading groups: $e');
    }
  }

  /// Add a new custom hashtag group
  Future<bool> addCustomGroup(String name, {int? parentId}) async {
    try {
      debugPrint('[HashtagGroupsController][addCustomGroup] Adding group: $name, parentId: $parentId');

      final newGroup = await _hashtagGroupService.addCustomGroup(name, parentId: parentId);

      if (newGroup != null) {
        await loadHashtagGroups(); // Reload to reflect changes
        debugPrint('[HashtagGroupsController][addCustomGroup] Successfully added group with ID: ${newGroup.id}');
        return true;
      } else {
        debugPrint('[HashtagGroupsController][addCustomGroup] Failed to add group');
        return false;
      }
    } catch (e) {
      debugPrint('[HashtagGroupsController][addCustomGroup] Error: $e');
      return false;
    }
  }

  /// Update an existing hashtag group
  Future<bool> updateGroup(int groupId, String name) async {
    try {
      debugPrint('[HashtagGroupsController][updateGroup] Updating group ID: $groupId, name: $name');

      final success = await _hashtagGroupService.updateGroup(groupId, name);

      if (success) {
        await loadHashtagGroups(); // Reload to reflect changes
        debugPrint('[HashtagGroupsController][updateGroup] Successfully updated group');
        return true;
      } else {
        debugPrint('[HashtagGroupsController][updateGroup] Failed to update group');
        return false;
      }
    } catch (e) {
      debugPrint('[HashtagGroupsController][updateGroup] Error: $e');
      return false;
    }
  }

  /// Delete a hashtag group
  /// Returns: true if deleted, false if failed, null if has memories (cannot delete)
  Future<bool?> deleteGroup(int groupId) async {
    try {
      debugPrint('[HashtagGroupsController][deleteGroup] Deleting group ID: $groupId');

      final result = await _hashtagGroupService.deleteGroup(groupId);

      if (result == true) {
        await loadHashtagGroups(); // Reload to reflect changes
        debugPrint('[HashtagGroupsController][deleteGroup] Successfully deleted group');
        return true;
      } else if (result == null) {
        debugPrint('[HashtagGroupsController][deleteGroup] Cannot delete group - has associated memories');
        return null; // Cannot delete due to memories
      } else {
        debugPrint('[HashtagGroupsController][deleteGroup] Failed to delete group');
        return false;
      }
    } catch (e) {
      debugPrint('[HashtagGroupsController][deleteGroup] Error: $e');
      return false;
    }
  }

  /// Get main groups only
  List<HashtagGroup> getMainGroups() {
    return _allGroups.where((group) => group.isMainGroup).toList();
  }

  /// Get subgroups for a specific main group
  List<HashtagGroup> getSubgroups(int mainGroupId) {
    final mainGroup = _allGroups.firstWhereOrNull((group) => group.id == mainGroupId);
    return mainGroup?.subgroups ?? [];
  }

  /// Find group by ID
  HashtagGroup? findGroupById(int groupId) {
    // Check main groups
    for (final mainGroup in _allGroups) {
      if (mainGroup.id == groupId) return mainGroup;

      // Check subgroups
      if (mainGroup.subgroups != null) {
        for (final subgroup in mainGroup.subgroups!) {
          if (subgroup.id == groupId) return subgroup;
        }
      }
    }
    return null;
  }

  /// Set selected groups
  void setSelectedGroups(List<HashtagGroup> groups) {
    _selectedGroups.assignAll(groups);
  }

  /// Add group to selection
  void addToSelection(HashtagGroup group) {
    if (!_selectedGroups.any((g) => g.id == group.id)) {
      _selectedGroups.add(group);
    }
  }

  /// Remove group from selection
  void removeFromSelection(HashtagGroup group) {
    _selectedGroups.removeWhere((g) => g.id == group.id);
  }

  /// Clear selection
  void clearSelection() {
    _selectedGroups.clear();
  }

  void startEditing(String item) {
    originalItem.value = item;
    editingItem.value = item;
    isEditing.value = true;
  }

  void cancelEditing() {
    isEditing.value = false;
    editingItem.value = '';
    originalItem.value = '';
  }

  void saveEditedItem(String newValue) {
    if (newValue.trim().isNotEmpty) {
      final oldItem = originalItem.value;
      final index = sportHashtags.indexOf(oldItem);
      if (index != -1) {
        sportHashtags[index] = newValue.trim();
      }
    }
    cancelEditing();
  }

  @override
  void onClose() {
    editController.dispose();
    super.onClose();
  }
}
