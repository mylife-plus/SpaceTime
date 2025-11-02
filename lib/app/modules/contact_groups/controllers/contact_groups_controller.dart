import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../models/contact_group_model.dart';
import '../../../services/contact_group_service.dart';

class ContactGroupsController extends GetxController {
  final ContactGroupService _contactGroupService = ContactGroupService();

  final TextEditingController editController = TextEditingController();
  final RxBool isEditing = false.obs;
  final RxString editingItem = ''.obs;
  final RxString originalItem = ''.obs;

  // Contact groups data
  final RxList<ContactGroup> _allGroups = <ContactGroup>[].obs;
  final RxList<ContactGroup> _selectedGroups = <ContactGroup>[].obs;

  // Legacy sport contacts for backward compatibility
  final RxList<String> sportContacts =
      <String>[
        'football',
        'basketball',
        'tennis',
        'swimming',
        'running',
        'cycling',
      ].obs;

  // Getters
  List<ContactGroup> get allGroups => _allGroups;
  List<ContactGroup> get selectedGroups => _selectedGroups;

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

    // Load contact groups
    loadContactGroups();
  }

  /// Load all contact groups from database
  Future<void> loadContactGroups() async {
    try {
      debugPrint('[ContactGroupsController][loadContactGroups] Loading groups from database');

      final groups = await _contactGroupService.getAllGroupsHierarchical();
      _allGroups.assignAll(groups);

      debugPrint('[ContactGroupsController][loadContactGroups] Loaded ${groups.length} groups');
    } catch (e) {
      debugPrint('[ContactGroupsController][loadContactGroups] Error loading groups: $e');
    }
  }

  /// Add a new custom contact group
  Future<bool> addCustomGroup(String name, {int? parentId}) async {
    try {
      debugPrint('[ContactGroupsController][addCustomGroup] Adding group: $name, parentId: $parentId');

      final newGroup = await _contactGroupService.addCustomGroup(name, parentId: parentId);

      if (newGroup != null) {
        await loadContactGroups(); // Reload to reflect changes
        debugPrint('[ContactGroupsController][addCustomGroup] Successfully added group with ID: ${newGroup.id}');
        return true;
      } else {
        debugPrint('[ContactGroupsController][addCustomGroup] Failed to add group');
        return false;
      }
    } catch (e) {
      debugPrint('[ContactGroupsController][addCustomGroup] Error: $e');
      return false;
    }
  }

  /// Update an existing contact group
  Future<bool> updateGroup(int groupId, String name) async {
    try {
      debugPrint('[ContactGroupsController][updateGroup] Updating group ID: $groupId, name: $name');

      final success = await _contactGroupService.updateGroup(groupId, name);

      if (success) {
        await loadContactGroups(); // Reload to reflect changes
        debugPrint('[ContactGroupsController][updateGroup] Successfully updated group');
        return true;
      } else {
        debugPrint('[ContactGroupsController][updateGroup] Failed to update group');
        return false;
      }
    } catch (e) {
      debugPrint('[ContactGroupsController][updateGroup] Error: $e');
      return false;
    }
  }

  /// Delete a contact group
  Future<bool> deleteGroup(int groupId) async {
    try {
      debugPrint('[ContactGroupsController][deleteGroup] Deleting group ID: $groupId');

      final success = await _contactGroupService.deleteGroup(groupId);

      if (success) {
        await loadContactGroups(); // Reload to reflect changes
        debugPrint('[ContactGroupsController][deleteGroup] Successfully deleted group');
        return true;
      } else {
        debugPrint('[ContactGroupsController][deleteGroup] Failed to delete group');
        return false;
      }
    } catch (e) {
      debugPrint('[ContactGroupsController][deleteGroup] Error: $e');
      return false;
    }
  }

  /// Get main groups only
  List<ContactGroup> getMainGroups() {
    return _allGroups.where((group) => group.isMainGroup).toList();
  }

  /// Get subgroups for a specific main group
  List<ContactGroup> getSubgroups(int mainGroupId) {
    final mainGroup = _allGroups.firstWhereOrNull((group) => group.id == mainGroupId);
    return mainGroup?.subgroups ?? [];
  }

  /// Find group by ID
  ContactGroup? findGroupById(int groupId) {
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
  void setSelectedGroups(List<ContactGroup> groups) {
    _selectedGroups.assignAll(groups);
  }

  /// Add group to selection
  void addToSelection(ContactGroup group) {
    if (!_selectedGroups.any((g) => g.id == group.id)) {
      _selectedGroups.add(group);
    }
  }

  /// Remove group from selection
  void removeFromSelection(ContactGroup group) {
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
      final index = sportContacts.indexOf(oldItem);
      if (index != -1) {
        sportContacts[index] = newValue.trim();
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
