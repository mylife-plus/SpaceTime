import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart' as gfonts;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/contact_group_service.dart';
import 'package:spacetime/app/models/contact_group_model.dart';
import 'package:spacetime/app/shared/widgets/searchable_contact_widget.dart';
import 'package:spacetime/app/shared/widgets/add_edit_group_popup.dart';
import '../../../config/app_text.dart';

class ContactGroupsView extends StatefulWidget {
  final Function(ContactGroup)? onContactGroupSelected;
  final ContactGroup? selectedContactGroup;

  // Multiple selection mode parameters
  final bool allowMultipleSelection;
  final List<ContactGroup>? selectedContactGroups;
  final Function(List<ContactGroup>)? onMultipleContactGroupsSelected;

  const ContactGroupsView({
    super.key,
    this.onContactGroupSelected,
    this.selectedContactGroup,
    this.allowMultipleSelection = false,
    this.selectedContactGroups,
    this.onMultipleContactGroupsSelected,
  });

  @override
  State<ContactGroupsView> createState() => _ContactGroupsViewState();
}

class _ContactGroupsViewState extends State<ContactGroupsView> {
  final ContactGroupService _contactGroupService = ContactGroupService();

  // Reactive state variables
  final RxList<ContactGroup> _mainContactGroups = <ContactGroup>[].obs;
  final RxBool _isLoading = false.obs;
  final RxMap<int, bool> _expandedContactGroups = <int, bool>{}.obs;
  final RxMap<int, bool> _addingToContactGroup = <int, bool>{}.obs;
  final RxMap<int, TextEditingController> _inlineNameControllers = <int, TextEditingController>{}.obs;
  final RxMap<int, ExpansionTileController> _expansionControllers = <int, ExpansionTileController>{}.obs;
  final RxMap<int, bool> _pendingAddingMode = <int, bool>{}.obs;

  // Inline editing state for subgroups
  final RxMap<int, bool> _editingContactGroup = <int, bool>{}.obs;
  final RxMap<int, TextEditingController> _editNameControllers = <int, TextEditingController>{}.obs;

  // Inline add state for main contact groups
  final RxBool _addingMainContactGroup = false.obs;
  final TextEditingController _mainContactGroupNameController = TextEditingController();

  // Recently selected subgroups storage (max 6 items)
  static const String _recentSubgroupsKey = 'recent_subgroups';
  static const int _maxRecentItems = 6;

  // Multiple selection state
  final RxList<ContactGroup> _selectedContactGroups = <ContactGroup>[].obs;

  // Global refresh notifier for external access
  final RxInt _globalRefreshNotifier = 0.obs;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[ContactGroupsView][initState] ContactGroupsView opened, initializing...',
    );
    debugPrint(
      '[ContactGroupsView][initState] Multiple selection mode: ${widget.allowMultipleSelection}',
    );
    debugPrint(
      '[ContactGroupsView][initState] Starting database initialization and contact group loading',
    );

    // Initialize selected contact groups for multiple selection mode
    if (widget.allowMultipleSelection && widget.selectedContactGroups != null) {
      _selectedContactGroups.addAll(widget.selectedContactGroups!);
      debugPrint(
        '[ContactGroupsView][initState] Initialized with ${_selectedContactGroups.length} pre-selected contact groups',
      );
    }

    // Register global refresh notifier for external access
    try {
      Get.put(_globalRefreshNotifier, tag: 'contactGroupsRefresh');
      debugPrint(
        '[ContactGroupsView][initState] Global refresh notifier registered',
      );
    } catch (e) {
      debugPrint(
        '[ContactGroupsView][initState] Global refresh notifier already registered: $e',
      );
    }

    _loadContactGroups();

    // Listen for global refresh triggers
    ever(_globalRefreshNotifier, (timestamp) {
      if (timestamp > 0) {
        debugPrint(
          '[ContactGroupsView][initState] Global refresh triggered, refreshing contact groups...',
        );
        _refreshContactGroupsFromDatabase();
      }
    });

    debugPrint(
      '[ContactGroupsView][initState] ContactGroupsView initialization completed',
    );
  }

  @override
  void dispose() {
    _mainContactGroupNameController.dispose();

    // Dispose inline controllers
    for (final controller in _inlineNameControllers.values) {
      controller.dispose();
    }

    // Dispose editing controllers
    for (final controller in _editNameControllers.values) {
      controller.dispose();
    }

    // Clean up global refresh notifier
    try {
      Get.delete<RxInt>(tag: 'contactGroupsRefresh');
      debugPrint(
        '[ContactGroupsView][dispose] Global refresh notifier cleaned up',
      );
    } catch (e) {
      debugPrint(
        '[ContactGroupsView][dispose] Error cleaning up global refresh notifier: $e',
      );
    }

    super.dispose();
  }

  /// Load all main contact groups with their subgroups
  Future<void> _loadContactGroups() async {
    try {
      _isLoading.value = true;
      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Starting contact group loading process',
      );

      // Step 1: Fetch all contact groups from database
      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Fetching contact groups from database',
      );

      final contactGroups = await _contactGroupService.getAllGroupsHierarchical();
      _mainContactGroups.value = contactGroups;

      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Successfully loaded ${contactGroups.length} main contact groups from database',
      );

      // Verify we have the expected predefined contact groups
      if (_mainContactGroups.isNotEmpty) {
        debugPrint(
          '[ContactGroupsView][_loadContactGroups] ✅ Database contains contact groups - initialization successful',
        );

        // Log contact group details for debugging
        for (int i = 0; i < _mainContactGroups.length; i++) {
          final contactGroup = _mainContactGroups[i];
          final subgroupCount = contactGroup.subgroups?.length ?? 0;
          final customStatus = contactGroup.isCustom ? '(Custom)' : '(Predefined)';
          debugPrint(
            '[ContactGroupsView][_loadContactGroups] Main Contact Group ${i + 1}: ${contactGroup.name} - $subgroupCount subgroups $customStatus',
          );

          // Log first few subgroups for verification
          if (contactGroup.hasSubgroups && i < 3) {
            // Only log first 3 main contact groups' subgroups
            for (int j = 0; j < math.min(3, subgroupCount); j++) {
              final sub = contactGroup.subgroups![j];
              debugPrint(
                '[ContactGroupsView][_loadContactGroups]   └─ Subgroup: ${sub.name}',
              );
            }
            if (subgroupCount > 3) {
              debugPrint(
                '[ContactGroupsView][_loadContactGroups]   └─ ... and ${subgroupCount - 3} more subgroups',
              );
            }
          }
        }
      } else {
        debugPrint(
          '[ContactGroupsView][_loadContactGroups] ⚠️ No contact groups found in database - this may indicate an initialization issue',
        );
      }
    } catch (e) {
      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Error during contact group loading/initialization: $e',
      );
      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Error type: ${e.runtimeType}',
      );
      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Stack trace: ${StackTrace.current}',
      );

      Get.snackbar(
        'Unable to Load',
        'Unable to load contact groups. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );

      // Set empty contact groups to prevent UI errors
      _mainContactGroups.value = [];
    } finally {
      _isLoading.value = false;
      debugPrint(
        '[ContactGroupsView][_loadContactGroups] Contact group loading process completed',
      );
    }
  }

  /// Refresh contact groups from database (used after CRUD operations)
  Future<void> _refreshContactGroupsFromDatabase() async {
    try {
      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] ===== REFRESH STARTED =====');

      // Clear all controllers and state before refreshing
      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] 🧹 Clearing all controllers');
      _clearAllControllers();

      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] 🔄 Fetching contact groups from service');
      final contactGroups = await _contactGroupService.getAllGroupsHierarchical();

      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] Retrieved ${contactGroups.length} groups from service');
      for (int i = 0; i < contactGroups.length; i++) {
        final group = contactGroups[i];
        debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] Group $i: ID=${group.id}, Name="${group.name}", Subgroups=${group.subgroups?.length ?? 0}');
      }

      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] 📝 Updating reactive list');
      _mainContactGroups.value = contactGroups;

      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] ✅ Successfully refreshed ${contactGroups.length} main contact groups');
    } catch (e) {
      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] ❌ Error refreshing contact groups: $e');
      debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] Exception type: ${e.runtimeType}');

      Get.snackbar(
        'Unable to Refresh',
        'Unable to refresh contact groups. Please try again.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
    debugPrint('[ContactGroupsView][_refreshContactGroupsFromDatabase] ===== REFRESH COMPLETED =====');
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(ContactGroup contactGroup) {
    final uiController = Get.find<UiController>();

    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                'Delete Contact Group',
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),

              // Message
              Text(
                'Are you sure you want to delete "${contactGroup.name}"?',
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),

              // Warning box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone.',
                        style: gfonts.GoogleFonts.kumbhSans(
                          color: Colors.orange[700],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Get.back(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text(
                      'Cancel',
                      style: gfonts.GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _deleteContactGroup(contactGroup.id!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      'Delete',
                      style: gfonts.GoogleFonts.kumbhSans(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Delete a contact group
  Future<void> _deleteContactGroup(int contactGroupId) async {
    try {
      debugPrint(
        '[ContactGroupsView][_deleteContactGroup] Deleting contact group ID: $contactGroupId',
      );

      final result = await _contactGroupService.deleteGroup(contactGroupId);

      if (result == true) {
        // Successfully deleted
// Navigator.pop(Get.context!);
        // Remove from recent selections before refreshing
        final group = await _contactGroupService.getGroupById(contactGroupId);
        if (group != null) {
          if (group.parentId == null) {
            // Main group deleted - remove it and all its subgroups from recent selections
            final subgroups = await _contactGroupService.getSubgroups(contactGroupId);
            await removeGroupAndSubgroupsFromRecent(contactGroupId, subgroups);

            // Also remove from searchable contact widget recent lists (filter overlay)
            final subgroupIds = subgroups.map((s) => s.id!).toList();
            await SearchableContactWidget.removeGroupAndSubgroupsFromRecentContactGroups(contactGroupId, subgroupIds);
          } else {
            // Subgroup deleted - remove only this subgroup from recent selections
            await removeFromRecentlySelectedSubgroups(contactGroupId);

            // Also remove from searchable contact widget recent lists (filter overlay)
            await SearchableContactWidget.removeFromRecentContactGroups(contactGroupId);
            await SearchableContactWidget.removeFromRecentContacts(group.name);
          }
        }

        // Refresh contact groups from database to show the deletion
        debugPrint(
          '[ContactGroupsView][_deleteContactGroup] Refreshing contact groups from database after deletion',
        );
        await _refreshContactGroupsFromDatabase();

        Get.snackbar(
          'Success',
          'Contact group deleted successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else if (result == null) {
        // Cannot delete due to memories
        // Get.back(); // Close confirmation dialog

        // Get the group name and memory count for the error dialog
        final group = await _contactGroupService.getGroupById(contactGroupId);
        final memoryCount = group != null
            ? await _contactGroupService.getMemoryCountForGroup(group.name)
            : 0;

        _showCannotDeleteDialog(group?.name ?? 'Unknown', memoryCount);
      } else {
        // Failed to delete
        Get.snackbar(
          'Unable to Delete',
          'Unable to delete contact group. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[ContactGroupsView][_deleteContactGroup] Error: $e');
      Get.snackbar(
        'Unable to Delete',
        'Unable to delete contact group. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Show dialog when contact group cannot be deleted due to existing memories
  void _showCannotDeleteDialog(String groupName, int memoryCount) {
    final uiController = Get.find<UiController>();

    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title with icon
              Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cannot Delete The Contact',
                      style: gfonts.GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Message
              Text(
                'The contact "$groupName" cannot be deleted because it is being used by $memoryCount ${memoryCount == 1 ? 'memory' : 'memories'}.',
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'To delete this contact group, first remove the mentions from all memories that use them, or delete those memories.',
                        style: gfonts.GoogleFonts.kumbhSans(
                          color: Colors.orange[700],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // OK button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Get.back(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text(
                    'OK',
                    style: gfonts.GoogleFonts.kumbhSans(
                      color: uiController.currentMainColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show edit contact group dialog using AddEditGroupPopup
  void _showEditContactGroupDialog(ContactGroup contactGroup) async {
    // Get parent group name if this is a subgroup
    String? parentGroupName;
    if (contactGroup.parentId != null) {
      final parentGroup = await _contactGroupService.getGroupById(contactGroup.parentId!);
      parentGroupName = parentGroup?.name;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AddEditGroupPopup(
          isHashtagMode: false,
          isMainGroup: contactGroup.parentId == null,
          initialName: contactGroup.name,
          editItemId: contactGroup.id,
          parentId: contactGroup.parentId,
          parentGroupName: parentGroupName,
          onSave: (newName, parentId) async {
            // Validate that name is provided
            if (newName.isEmpty) {
              Get.snackbar(
                'Validation Error',
                'Please enter a contact group name',
                backgroundColor: Colors.orange,
                colorText: Colors.white,
              );
              return;
            }

            if (newName == contactGroup.name) {
              // No changes, just close
              Navigator.of(context).pop();
              return;
            }

            try {
              final success = await _contactGroupService.updateGroup(
                contactGroup.id!,
                newName,
              );

              if (success) {
                Navigator.of(context).pop(); // Close dialog
                await _refreshContactGroupsFromDatabase();

                Get.snackbar(
                  'Success',
                  'Contact group "$newName" updated successfully!',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } else {
                Get.snackbar(
                  'Unable to Update',
                  'Unable to update contact group. Please try again.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            } catch (e) {
              debugPrint('[ContactGroupsView][EditDialog] Exception occurred: $e');
              Get.snackbar(
                'Unable to Update',
                'Unable to update contact group. Please try again.',
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            }
          },
        );
      },
    );
  }

  /// Delete a subgroup (contact)
  Future<void> _deleteSubgroup(ContactGroup subgroup) async {
    try {
      debugPrint(
        '[ContactGroupsView][_deleteSubgroup] Deleting subgroup ID: ${subgroup.id}',
      );

      final result = await _contactGroupService.deleteGroup(subgroup.id!);

      if (result == true) {
        // Successfully deleted - also remove from recent selections
        await removeFromRecentlySelectedSubgroups(subgroup.id!);

        // Also remove from searchable contact widget recent lists (filter overlay)
        await SearchableContactWidget.removeFromRecentContactGroups(subgroup.id!);
        await SearchableContactWidget.removeFromRecentContacts(subgroup.name);

        // Refresh contact groups from database to show the deletion
        debugPrint(
          '[ContactGroupsView][_deleteSubgroup] Refreshing contact groups from database after deletion',
        );
        await _refreshContactGroupsFromDatabase();

        Get.snackbar(
          'Success',
          'Contact deleted successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else if (result == null) {
        // Cannot delete due to memories
        final memoryCount = await _contactGroupService.getMemoryCountForGroup(subgroup.name);
        _showCannotDeleteDialog(subgroup.name, memoryCount);
      } else {
        // Failed to delete
        Get.snackbar(
          'Unable to Delete',
          'Unable to delete contact. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[ContactGroupsView][_deleteSubgroup] Error: $e');
      Get.snackbar(
        'Unable to Delete',
        'Unable to delete contact. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Clear all controllers and state to prevent disposed controller errors
  void _clearAllControllers() {
    // Dispose and clear inline name controllers
    for (final controller in _inlineNameControllers.values) {
      try {
        controller.dispose();
      } catch (e) {
        debugPrint('[ContactGroupsView] Error disposing inline controller: $e');
      }
    }
    _inlineNameControllers.clear();

    // Dispose and clear edit name controllers
    for (final controller in _editNameControllers.values) {
      try {
        controller.dispose();
      } catch (e) {
        debugPrint('[ContactGroupsView] Error disposing edit controller: $e');
      }
    }
    _editNameControllers.clear();

    // Clear expansion controllers (don't dispose as they're managed by ExpansionTile)
    _expansionControllers.clear();

    // Clear all state maps
    _expandedContactGroups.clear();
    _addingToContactGroup.clear();
    _pendingAddingMode.clear();
    _editingContactGroup.clear();
  }



  /// Select a contact group and return to parent
  void _selectContactGroup(ContactGroup contactGroup) {
    debugPrint(
      '[ContactGroupsView][_selectContactGroup] Selected: ${contactGroup.name}',
    );

    // Save to recent subgroups if it's a subgroup
    if (contactGroup.isSubgroup) {
      _saveRecentlySelectedSubgroup(contactGroup);
    }

    if (widget.allowMultipleSelection) {
      // Multiple selection mode - toggle contact group selection
      _toggleContactGroupSelection(contactGroup);
    } else {
      // Single selection mode - original behavior
      if (widget.onContactGroupSelected != null) {
        widget.onContactGroupSelected!(contactGroup);
      }

      Get.back(result: contactGroup);
    }
  }

  /// Toggle contact group selection for multiple selection mode
  void _toggleContactGroupSelection(ContactGroup contactGroup) {
    debugPrint(
      '[ContactGroupsView][_toggleContactGroupSelection] Toggling: ${contactGroup.name} (isMainGroup: ${contactGroup.isMainGroup}, isSubgroup: ${contactGroup.isSubgroup})',
    );

    // Determine if the group is currently selected
    bool isSelected;
    if (contactGroup.isMainGroup && contactGroup.hasSubgroups) {
      // For main groups, check if ALL subgroups are selected
      isSelected = contactGroup.subgroups!.every(
        (subgroup) => _selectedContactGroups.any((g) => g.id == subgroup.id)
      );
    } else {
      // For subgroups, check if this specific group is selected
      isSelected = _selectedContactGroups.any((g) => g.id == contactGroup.id);
    }

    debugPrint(
      '[ContactGroupsView][_toggleContactGroupSelection] Current selection state: $isSelected',
    );

    if (isSelected) {
      // Deselecting
      if (contactGroup.isMainGroup && contactGroup.hasSubgroups) {
        // If this is a main group, remove all its subgroups
        for (final subgroup in contactGroup.subgroups!) {
          _selectedContactGroups.removeWhere((g) => g.id == subgroup.id);
          debugPrint(
            '[ContactGroupsView][_toggleContactGroupSelection] Removed subgroup: ${subgroup.name}',
          );
        }
        debugPrint(
          '[ContactGroupsView][_toggleContactGroupSelection] Deselected main group: ${contactGroup.name} (removed all subgroups)',
        );
      } else {
        // For subgroups, remove them directly
        _selectedContactGroups.removeWhere((g) => g.id == contactGroup.id);
        debugPrint(
          '[ContactGroupsView][_toggleContactGroupSelection] Removed: ${contactGroup.name}',
        );
      }
    } else {
      // Selecting
      if (contactGroup.isMainGroup && contactGroup.hasSubgroups) {
        // If this is a main group, add all its subgroups (not the main group itself)
        for (final subgroup in contactGroup.subgroups!) {
          if (!_selectedContactGroups.any((g) => g.id == subgroup.id)) {
            _selectedContactGroups.add(subgroup);
            debugPrint(
              '[ContactGroupsView][_toggleContactGroupSelection] Added subgroup: ${subgroup.name}',
            );
          }
        }
        debugPrint(
          '[ContactGroupsView][_toggleContactGroupSelection] Selected main group: ${contactGroup.name} (added ${contactGroup.subgroups!.length} subgroups)',
        );
      } else {
        // For subgroups, add them directly
        _selectedContactGroups.add(contactGroup);
        debugPrint(
          '[ContactGroupsView][_toggleContactGroupSelection] Added: ${contactGroup.name}',
        );

        // Save to recent subgroups
        _saveRecentlySelectedSubgroup(contactGroup);
      }
    }

    debugPrint(
      '[ContactGroupsView][_toggleContactGroupSelection] Total selected: ${_selectedContactGroups.length}',
    );
  }

  /// Find the main group for a given subgroup
  ContactGroup? _findMainGroupForSubgroup(ContactGroup subgroup) {
    for (final mainGroup in _mainContactGroups) {
      if (mainGroup.subgroups != null) {
        for (final sub in mainGroup.subgroups!) {
          if (sub.id == subgroup.id) {
            return mainGroup;
          }
        }
      }
    }
    return null;
  }

  /// Check if all subgroups of a main group are selected
  bool _areAllSubgroupsSelected(ContactGroup mainGroup) {
    if (!mainGroup.hasSubgroups) return false;

    for (final subgroup in mainGroup.subgroups!) {
      if (!_selectedContactGroups.any((g) => g.id == subgroup.id)) {
        return false;
      }
    }
    return true;
  }

  /// Check if a main group is selected (meaning all its subgroups are selected)
  bool _isMainGroupSelected(ContactGroup mainGroup) {
    return _selectedContactGroups.any((g) => g.id == mainGroup.id);
  }

  /// Handle done button press for multiple selection mode
  void _onDonePressed() {
    debugPrint(
      '[ContactGroupsView][_onDonePressed] Returning ${_selectedContactGroups.length} selected contact groups',
    );

    if (widget.onMultipleContactGroupsSelected != null) {
      widget.onMultipleContactGroupsSelected!(_selectedContactGroups.toList());
    }

    Get.back(result: _selectedContactGroups.toList());
  }

  /// Toggle expansion state of a main contact group
  void _toggleContactGroupExpansion(int contactGroupId) {
    _expandedContactGroups[contactGroupId] =
        !(_expandedContactGroups[contactGroupId] ?? false);
  }

  /// Show popup for adding subgroup to a contact group
  void _startInlineAdding(int contactGroupId, String contactGroupName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AddEditGroupPopup(
          isHashtagMode: false,
          isMainGroup: false,
          parentId: contactGroupId,
          parentGroupName: contactGroupName,
          onSave: (name, parentId) async {
            // Use the existing save logic
            if (name.isEmpty) {
              Get.snackbar(
                'Invalid Name',
                'Contact name cannot be empty',
                backgroundColor: Colors.orange,
                colorText: Colors.white,
              );
              return;
            }

            try {
              final newSubgroup = await _contactGroupService.addCustomGroup(
                name,
                parentId: contactGroupId,
              );

              if (newSubgroup == null) {
                Get.snackbar(
                  'Unable to Add',
                  'Unable to add contact. Please try again.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              } else if (newSubgroup.id == -1) {
                // Duplicate subgroup contact name
                Get.snackbar(
                  'Duplicate Contact',
                  'Contact with this name already exists.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              } else if (newSubgroup.id == -4) {
                // Subgroup name conflicts with parent group
                Get.snackbar(
                  'Name Conflict',
                  'This name is already used by the parent group.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }

              await _refreshContactGroupsFromDatabase();

              Get.snackbar(
                'Success',
                'Contact added successfully',
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            } catch (e) {
              debugPrint('[ContactGroupsView] Error adding subgroup: $e');
              Get.snackbar(
                'Unable to Add',
                'Unable to add contact. Please try again.',
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            }
          },
        );
      },
    );
  }

  /// Force expansion state and trigger UI rebuild
  void _forceExpansionState(int contactGroupId, bool expanded) {
    setState(() {
      _expandedContactGroups[contactGroupId] = expanded;
    });

    if (expanded) {
      // Enable adding mode after state is set
      _enableAddingMode(contactGroupId);
    }

    debugPrint('[ContactGroupsView][_forceExpansionState] Forced expansion state for contact group $contactGroupId to: $expanded');
  }

  /// Helper method to enable adding mode
  void _enableAddingMode(int contactGroupId) {
    _addingToContactGroup[contactGroupId] = true;

    // Initialize controllers
    _inlineNameControllers[contactGroupId] = TextEditingController();
  }

  /// Cancel inline adding
  void _cancelInlineAdding(int contactGroupId) {
    _addingToContactGroup[contactGroupId] = false;
    _inlineNameControllers[contactGroupId]?.dispose();
    _inlineNameControllers.remove(contactGroupId);
  }

  /// Save recently selected subgroup
  Future<void> _saveRecentlySelectedSubgroup(ContactGroup subgroup) async {
    try {
      // Only save subgroups (not main groups)
      if (!subgroup.isSubgroup) return;

      final prefs = await SharedPreferences.getInstance();

      // Get existing recent subgroups
      final existingJson = prefs.getString(_recentSubgroupsKey);
      List<Map<String, dynamic>> recentList = [];

      if (existingJson != null) {
        final decoded = json.decode(existingJson) as List;
        recentList = decoded.cast<Map<String, dynamic>>();
      }

      // Remove if already exists (to move to front)
      recentList.removeWhere((item) => item['id'] == subgroup.id);

      // Add to front
      recentList.insert(0, subgroup.toJson());

      // Keep only max items
      if (recentList.length > _maxRecentItems) {
        recentList = recentList.take(_maxRecentItems).toList();
      }

      // Save back to preferences
      final updatedJson = json.encode(recentList);
      await prefs.setString(_recentSubgroupsKey, updatedJson);

      debugPrint('[ContactGroupsView] Saved recent subgroup: ${subgroup.name} (ID: ${subgroup.id})');
      debugPrint('[ContactGroupsView] Total recent subgroups: ${recentList.length}');
    } catch (e) {
      debugPrint('[ContactGroupsView] Error saving recent subgroup: $e');
    }
  }

  /// Get recently selected subgroups
  static Future<List<ContactGroup>> getRecentlySelectedSubgroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_recentSubgroupsKey);

      if (existingJson == null) return [];

      final decoded = json.decode(existingJson) as List;
      final recentList = decoded.cast<Map<String, dynamic>>();

      // Convert back to ContactGroup objects
      final recentSubgroups = <ContactGroup>[];
      for (final item in recentList) {
        try {
          final subgroup = ContactGroup.fromJson(item);
          recentSubgroups.add(subgroup);
        } catch (e) {
          debugPrint('[ContactGroupsView] Error parsing recent subgroup: $e');
          // Skip invalid entries
        }
      }

      debugPrint('[ContactGroupsView] Loaded ${recentSubgroups.length} recent subgroups');
      return recentSubgroups;
    } catch (e) {
      debugPrint('[ContactGroupsView] Error getting recent subgroups: $e');
      return [];
    }
  }

  /// Clear recently selected subgroups
  static Future<void> clearRecentlySelectedSubgroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSubgroupsKey);
      debugPrint('[ContactGroupsView] Cleared recent subgroups');
    } catch (e) {
      debugPrint('[ContactGroupsView] Error clearing recent subgroups: $e');
    }
  }

  /// Remove a specific contact group from recently selected subgroups
  static Future<void> removeFromRecentlySelectedSubgroups(int groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_recentSubgroupsKey);

      if (existingJson == null) return;

      final decoded = json.decode(existingJson) as List;
      List<Map<String, dynamic>> recentList = decoded.cast<Map<String, dynamic>>();

      // Remove the deleted group from recent list
      final originalLength = recentList.length;
      recentList.removeWhere((item) => item['id'] == groupId);

      if (recentList.length != originalLength) {
        // Save updated list back to preferences
        final updatedJson = json.encode(recentList);
        await prefs.setString(_recentSubgroupsKey, updatedJson);
        debugPrint('[ContactGroupsView] Removed group ID $groupId from recent subgroups');
      }
    } catch (e) {
      debugPrint('[ContactGroupsView] Error removing from recent subgroups: $e');
    }
  }

  /// Remove contact group and all its subgroups from recently selected subgroups
  static Future<void> removeGroupAndSubgroupsFromRecent(int mainGroupId, List<ContactGroup> subgroups) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_recentSubgroupsKey);

      if (existingJson == null) return;

      final decoded = json.decode(existingJson) as List;
      List<Map<String, dynamic>> recentList = decoded.cast<Map<String, dynamic>>();

      // Remove main group and all its subgroups from recent list
      final originalLength = recentList.length;
      recentList.removeWhere((item) {
        final itemId = item['id'];
        // Remove if it's the main group or any of its subgroups
        if (itemId == mainGroupId) return true;
        return subgroups.any((subgroup) => subgroup.id == itemId);
      });

      if (recentList.length != originalLength) {
        // Save updated list back to preferences
        final updatedJson = json.encode(recentList);
        await prefs.setString(_recentSubgroupsKey, updatedJson);
        debugPrint('[ContactGroupsView] Removed main group ID $mainGroupId and ${subgroups.length} subgroups from recent subgroups');
      }
    } catch (e) {
      debugPrint('[ContactGroupsView] Error removing group and subgroups from recent: $e');
    }
  }

  /// Example method to demonstrate how to use recent subgroups
  /// Call this from other screens to get and display recent subgroups
  static Future<void> printRecentSubgroups() async {
    final recentSubgroups = await getRecentlySelectedSubgroups();
    debugPrint('[ContactGroupsView] Recent subgroups (${recentSubgroups.length}):');
    for (final subgroup in recentSubgroups) {
      debugPrint('  - ${subgroup.name} (ID: ${subgroup.id}, Parent: ${subgroup.parentId})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return PopScope(
      canPop: !widget.allowMultipleSelection,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.allowMultipleSelection) {
          // Call _onDonePressed even when selection is empty to properly clear filters
          _onDonePressed();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading:
              widget.allowMultipleSelection
                  ? Obx(
                    () => IconButton(
                      onPressed: _onDonePressed,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: _selectedContactGroups.isNotEmpty ? 'Done' : 'Back',
                    ),
                  )
                  : null,
          title: Obx(
            () => Text(
              widget.allowMultipleSelection
                  ? 'Contacts'
                  : AppTexts.contactGroups,
              style: gfonts.GoogleFonts.kumbhSans(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              maxLines: null, // Allow unlimited lines
              overflow: TextOverflow.visible, // Show all text
              textAlign: TextAlign.center, // Keep centered
            ),
          ),
          centerTitle: true,
          backgroundColor: uiController.currentMainColor,
          foregroundColor:
              uiController.darkMode.value ? Colors.white : Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(
            color: uiController.darkMode.value ? Colors.white : Colors.white,
          ),
          actions: [
            // Hide add button in filter mode
            if (!widget.allowMultipleSelection)
              IconButton(
                onPressed: () => _startInlineAddingMainContactGroup(),
                icon: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/ic_add.png',
                    width: 25,
                    height: 25,
                  ),
                ),
                tooltip: 'Add New Contact Group',
              ),
          ],
        ),
        body: Column(
          children: [
            // Selection indicator when in filter mode
            if (widget.allowMultipleSelection)
              Obx(() {
                // if (_selectedContactGroups.isEmpty) {
                //   return const SizedBox.shrink();
                // }
                return Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    // decoration: BoxDecoration(
                    //   color: uiController.currentMainColor.withValues(alpha: 0.1),
                    //   border: Border(
                    //     bottom: BorderSide(
                    //       color: uiController.currentMainColor.withValues(alpha: 0.3),
                    //       width: 1,
                    //     ),
                    //   ),
                    // ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Center(
                          child: Text(
                            '${_selectedContactGroups.where((g) => g.isSubgroup).length} selected',
                            style: gfonts.GoogleFonts.kumbhSans(
                              color: uiController.currentMainColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            // Main content
            Expanded(
              child: Obx(() {
                if (_isLoading.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildMainContent(uiController);
              }),
            ),
          ],
        ),

      ),
    );
  }

  /// Build main content (hierarchical contact groups)
  Widget _buildMainContent(UiController uiController) {
    return Container(
      color: uiController.darkMode.value
          ? Colors.black
          : uiController.currentMainColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: _buildHierarchicalContactGroups(),
      ),
    );
  }



  /// Build hierarchical contact groups
  Widget _buildHierarchicalContactGroups() {
    final uiController = Get.find<UiController>();

    return Obx(() {
      // Check if any contact group is expanded
      final hasExpandedGroup = _expandedContactGroups.values.any((expanded) => expanded == true);

      return ListView(
        children: [
          // Inline add widget for main contact groups (at the top)
          Obx(() => _addingMainContactGroup.value
              ? _buildInlineAddMainContactGroupWidget()
              : const SizedBox.shrink()),

          // Show empty state message if no groups and not adding
          if (_mainContactGroups.isEmpty)
            Obx(() => !_addingMainContactGroup.value
                ? Container(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'No contact groups found.\nTap + to add a new group.',
                        textAlign: TextAlign.center,
                        style: gfonts.GoogleFonts.kumbhSans(
                          fontSize: 16,
                          color: uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink()),

          // Main contact groups
          ..._mainContactGroups.map((mainContactGroup) =>
              _buildMainContactGroupExpansionTile(mainContactGroup)),

          // Add spacing at the end if any group is expanded
          if (hasExpandedGroup) const SizedBox(height: 15),
        ],
      );
    });
  }

  /// Build main contact group expansion tile
  Widget _buildMainContactGroupExpansionTile(ContactGroup mainContactGroup) {
    final uiController = Get.find<UiController>();
    final isExpanded = _expandedContactGroups[mainContactGroup.id] ?? false;

    // Create a new expansion controller for this group to avoid state conflicts
    final groupId = mainContactGroup.id!;
    _expansionControllers[groupId] = ExpansionTileController();
    final controller = _expansionControllers[groupId]!;

    return Obx(() {
      // Check if all subgroups are selected (for filter mode)
      final allSubgroupsSelected = widget.allowMultipleSelection &&
          mainContactGroup.subgroups != null &&
          mainContactGroup.subgroups!.isNotEmpty &&
          mainContactGroup.subgroups!.every((subgroup) =>
              _selectedContactGroups.any((g) => g.id == subgroup.id));

      // Count selected subgroups
      final selectedSubgroupsCount = widget.allowMultipleSelection &&
          mainContactGroup.subgroups != null
          ? mainContactGroup.subgroups!.where((subgroup) =>
              _selectedContactGroups.any((g) => g.id == subgroup.id)).length
          : 0;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(2),
          // Add border to entire container when all subgroups are selected (filter mode only)
          border: widget.allowMultipleSelection && allSubgroupsSelected
              ? Border.all(
                  color: uiController.currentMainColor,
                  width: 2,
                )
              : null,
        ),
        child: Column(
          children: [
            // Grey container with border for the contact group header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                // Changed background color: white in light mode, grey in dark mode
                color: uiController.darkMode.value
                    ? Colors.grey[900]
                    : Colors.white,
                borderRadius: BorderRadius.circular(2),
                // No border on main group header since we only select subgroups
                border: null,
              ),
              child: ExpansionTile(
                key: ValueKey('contact_group_${mainContactGroup.id}'),
                controller: controller,
                initiallyExpanded: isExpanded,
                onExpansionChanged: (expanded) {
                  _expandedContactGroups[mainContactGroup.id!] = expanded;

                  // Check if we need to enable adding mode after expansion
                  if (expanded && (_pendingAddingMode[mainContactGroup.id!] ?? false)) {
                    _pendingAddingMode[mainContactGroup.id!] = false;
                    _enableAddingMode(mainContactGroup.id!);
                  }
                },
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                collapsedBackgroundColor: Colors.transparent,
                collapsedShape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
                // Show checkbox on the left when in filter mode
                leading: widget.allowMultipleSelection
                    ? GestureDetector(
                        onTap: () => _selectContactGroup(mainContactGroup),
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(left: 16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: allSubgroupsSelected
                                  ? uiController.currentMainColor
                                  : (uiController.darkMode.value
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Colors.grey[400]!),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            color: allSubgroupsSelected
                                ? uiController.currentMainColor
                                : Colors.transparent,
                          ),
                          child: allSubgroupsSelected
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      )
                    : null,
                title: GestureDetector(
                  onTap: widget.allowMultipleSelection
                      ? () => _selectContactGroup(mainContactGroup)
                      : null,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: widget.allowMultipleSelection ? 8.0 : 20.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: mainContactGroup.name,
                                  style: gfonts.GoogleFonts.kumbhSans(
                                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                // Show selection count when in filter mode
                                if (widget.allowMultipleSelection)
                                  TextSpan(
                                    text: ' (',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  ),
                                if (widget.allowMultipleSelection)
                                  TextSpan(
                                    text: '$selectedSubgroupsCount',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.currentMainColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (widget.allowMultipleSelection)
                                  TextSpan(
                                    text: '/${mainContactGroup.subgroups?.length ?? 0})',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  )
                                else
                                  TextSpan(
                                    text: ' (${mainContactGroup.subgroups?.length ?? 0})',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white.withValues(alpha: 0.6)
                                              : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: null, // Allow unlimited lines
                            overflow: TextOverflow.visible, // Show all text
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hide edit/delete/add buttons when in filter mode
                    if (!widget.allowMultipleSelection) ...[
                      // Edit button for main contact group
                      IconButton(
                        icon: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.6)
                                : Colors.grey[500] ?? Colors.grey,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/ic_edit.png',
                            width: 25,
                            height: 25,
                          ),
                        ),
                        onPressed: () => _showEditContactGroupDialog(mainContactGroup),
                        tooltip: 'Edit Contact Group',
                      ),
                      // Delete button for main contact group (only show if no subgroups)
                      if ((mainContactGroup.subgroups?.isEmpty ?? true))
                        IconButton(
                          icon: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              Colors.red,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              'assets/images/ic_cross.png',
                              width: 25,
                              height: 25,
                            ),
                          ),
                          onPressed: () => _deleteContactGroup(mainContactGroup.id!),
                          tooltip: 'Delete Contact Group',
                        ),
                      // Add subgroup button
                      IconButton(
                        onPressed: (_addingToContactGroup[mainContactGroup.id] ?? false)
                            ? null
                            : () => _startInlineAdding(mainContactGroup.id!, mainContactGroup.name),
                        icon: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            uiController.darkMode.value ? Colors.white : uiController.currentMainColor,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/ic_add.png',
                            width: 25,
                            height: 25,
                          ),
                        ),
                        tooltip: 'Add Subgroup',
                      ),
                    ],
                    // Expansion/collapse icon
                    Obx(
                      () => ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.grey[600] ?? Colors.grey,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          (_expandedContactGroups[mainContactGroup.id!] ?? false)
                              ? 'assets/images/ic_expand_close.png'
                              : 'assets/images/ic_expand_open.png',
                          width: 25,
                          height: 25,
                        ),
                      ),
                    ),
                    Container(width: 15),
                  ],
                ),
                children: [],
              ),
            ),
            // Subgroups section (outside the grey container)
            if (isExpanded) ...[
              // Subgroups list
              if (mainContactGroup.subgroups != null && mainContactGroup.subgroups!.isNotEmpty)
                ..._buildSubgroupsList(mainContactGroup, uiController),

              // Inline adding widget
              Obx(() {
                if (_addingToContactGroup[mainContactGroup.id] ?? false) {
                  return _buildInlineAddWidget(mainContactGroup.id!, uiController);
                }
                return const SizedBox.shrink();
              }),
            ],
          ],
        ),
      );
    });
  }



  /// Build subgroups list
  List<Widget> _buildSubgroupsList(ContactGroup mainContactGroup, UiController uiController) {
    return mainContactGroup.subgroups!.asMap().entries.map((entry) {
      final index = entry.key;
      final subgroup = entry.value;
      final isLast = index == mainContactGroup.subgroups!.length - 1;

      return Column(
        children: [
          _buildSubgroupTile(subgroup, uiController),
          // Add bottom padding after last subgroup when in filter mode
          if (isLast && widget.allowMultipleSelection)
            const SizedBox(height: 8),
        ],
      );
    }).toList();
  }

  /// Build individual subgroup tile
  Widget _buildSubgroupTile(ContactGroup subgroup, UiController uiController) {
    final isSelected = widget.allowMultipleSelection &&
        _selectedContactGroups.any((g) => g.id == subgroup.id);

    return Obx(() {
      final isEditing = _editingContactGroup[subgroup.id] ?? false;

      if (isEditing) {
        return _buildInlineEditWidget(subgroup, uiController);
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          // Changed background color to #F1F1F1 in light mode
          color: uiController.darkMode.value
              ? Colors.grey[900]
              : const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(2),
          border: isSelected
              ? Border.all(
                  color: uiController.currentMainColor,
                  width: 2,
                )
              : null,
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 5),
          dense: true,
          title: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '@ ',
                  style: gfonts.GoogleFonts.kumbhSans(
                    color: Colors.grey[400],
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 20,
                  ),
                ),
                TextSpan(
                  text: subgroup.name,
                  style: gfonts.GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          trailing: widget.allowMultipleSelection
              ? null // Hide edit/delete buttons in filter mode
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit button
                    IconButton(
                      onPressed: () => _startInlineEditing(subgroup),
                      icon: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          uiController.darkMode.value ? Colors.white70 : Colors.black54,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/images/ic_edit.png',
                          width: 20,
                          height: 20,
                        ),
                      ),
                      tooltip: 'Edit',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                    // Delete button
                    IconButton(
                      onPressed: () => _deleteSubgroup(subgroup),
                      icon: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          Colors.red.withValues(alpha: 0.7),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/images/ic_cross.png',
                          width: 20,
                          height: 20,
                        ),
                      ),
                      tooltip: 'Delete',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
          onTap: widget.allowMultipleSelection
              ? () => _selectContactGroup(subgroup)
              : () => _selectContactGroup(subgroup),
        ),
      );
    });
  }



  /// Build inline add widget for main contact groups
  Widget _buildInlineAddMainContactGroupWidget() {
    final uiController = Get.find<UiController>();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black
            : Colors.white,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color:
              uiController.darkMode.value
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        
          Row(
            children: [
              Expanded(
                child: TextSelectionTheme(
                  data: TextSelectionThemeData(
                    cursorColor: uiController.currentMainColor,
                    selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                    selectionHandleColor: uiController.currentMainColor,
                  ),
                  child: TextField(
                    controller: _mainContactGroupNameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'add Contact Name',
                      // hintText: 'Contact group name',
                      hintStyle: gfonts.GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.grey[500],
                        fontSize: 16,
                      ),
                      filled: true,
                      fillColor: uiController.darkMode.value
                          ? Colors.grey[700]
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    style: gfonts.GoogleFonts.kumbhSans(

                      color: uiController.darkMode.value ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Save button
              IconButton(
                onPressed: () => _saveInlineAddMainContactGroup(),
                icon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.green,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/ic_tick.png',
                    width: 20,
                    height: 20,
                  ),
                ),
                tooltip: 'Save',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
              // Cancel button
              IconButton(
                onPressed: () => _cancelInlineAddingMainContactGroup(),
                icon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.red,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/ic_cross.png',
                    width: 20,
                    height: 20,
                  ),
                ),
                tooltip: 'Cancel',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Show popup for editing a subgroup
  void _startInlineEditing(ContactGroup contactGroup) async {
    // Get parent group name if this is a subgroup
    String? parentGroupName;
    if (contactGroup.parentId != null) {
      final parentGroup = await _contactGroupService.getGroupById(contactGroup.parentId!);
      parentGroupName = parentGroup?.name;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AddEditGroupPopup(
          isHashtagMode: false,
          isMainGroup: contactGroup.parentId == null,
          initialName: contactGroup.name,
          editItemId: contactGroup.id,
          parentId: contactGroup.parentId,
          parentGroupName: parentGroupName,
          onSave: (newName, parentId) async {
            // Use the existing save logic
            if (newName.isEmpty) {
              Get.snackbar(
                'Invalid Name',
                'Contact group name cannot be empty',
                backgroundColor: Colors.orange,
                colorText: Colors.white,
              );
              return;
            }

            try {
              await _contactGroupService.updateGroup(contactGroup.id!, newName);

              // Update in recents if it exists
              await SearchableContactWidget.updateContactGroupInRecents(contactGroup.id!, newName);

              await _refreshContactGroupsFromDatabase();

              Get.snackbar(
                'Success',
                'Contact updated successfully',
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            } catch (e) {
              debugPrint('[ContactGroupsView] Error updating contact group: $e');
              if (e.toString().contains('DUPLICATE_CONTACT_NAME')) {
                final message = contactGroup.parentId == null
                    ? 'Contact Group with this name already exists.'
                    : 'Contact with this name already exists.';
                Get.snackbar(
                  'Duplicate Contact',
                  message,
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
              } else if (e.toString().contains('MAIN_GROUP_CONFLICTS_WITH_SUBGROUP')) {
                Get.snackbar(
                  'Name Conflict',
                  'This name is already used by a contact in another group.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
              } else if (e.toString().contains('SUBGROUP_CONFLICTS_WITH_PARENT')) {
                Get.snackbar(
                  'Name Conflict',
                  'This name is already used by the parent group.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
              } else {
                Get.snackbar(
                  'Unable to Update',
                  'Unable to update contact group. Please try again.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            }
          },
        );
      },
    );
  }

  /// Build inline edit widget
  Widget _buildInlineEditWidget(ContactGroup contactGroup, UiController uiController) {
    final nameController = _editNameControllers[contactGroup.id!]!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black
            : uiController.currentMainColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text(
          //   'Edit Subgroup',
          //   style: gfonts.GoogleFonts.kumbhSans(
          //     fontSize: 12,
          //     fontWeight: FontWeight.w600,
          //     color: uiController.currentMainColor,
          //   ),
          // ),
          // const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextSelectionTheme(
                  data: TextSelectionThemeData(
                    cursorColor: uiController.currentMainColor,
                    selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                    selectionHandleColor: uiController.currentMainColor,
                  ),
                  child: TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'edit Contact',
                      hintStyle: gfonts.GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.grey[500],
                        fontSize: 18,
                      ),
                      // filled: true,
                      // fillColor: uiController.darkMode.value
                      //     ? Colors.grey[700]
                      //     : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    style: gfonts.GoogleFonts.kumbhSans(
                      color: uiController.darkMode.value ? Colors.white : Colors.black,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Save button
              IconButton(
                onPressed: () => _saveInlineEdit(contactGroup),
                icon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.green,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/ic_tick.png',
                    width: 20,
                    height: 20,
                  ),
                ),
                tooltip: 'Save',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
              // Cancel button
              IconButton(
                onPressed: () => _cancelInlineEdit(contactGroup.id!),
                icon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.red,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/ic_cross.png',
                    width: 20,
                    height: 20,
                  ),
                ),
                tooltip: 'Cancel',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Save inline edit
  Future<void> _saveInlineEdit(ContactGroup contactGroup) async {
    final nameController = _editNameControllers[contactGroup.id!]!;
    final newName = nameController.text.trim();

    if (newName.isEmpty) {
      Get.snackbar(
        'Invalid Name',
        'Contact group name cannot be empty',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      await _contactGroupService.updateGroup(contactGroup.id!, newName);

      // Update in recents if it exists
      await SearchableContactWidget.updateContactGroupInRecents(contactGroup.id!, newName);

      _cancelInlineEdit(contactGroup.id!);
      await _refreshContactGroupsFromDatabase();

      Get.snackbar(
        'Success',
        'Contact updated successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('[ContactGroupsView] Error updating contact group: $e');
      if (e.toString().contains('DUPLICATE_CONTACT_NAME')) {
        final message = contactGroup.parentId == null
            ? 'Contact Group with this name already exists.'
            : 'Contact with this name already exists.';
        Get.snackbar(
          'Duplicate Contact',
          message,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else if (e.toString().contains('MAIN_GROUP_CONFLICTS_WITH_SUBGROUP')) {
        Get.snackbar(
          'Name Conflict',
          'This name is already used by a contact in another group.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else if (e.toString().contains('SUBGROUP_CONFLICTS_WITH_PARENT')) {
        Get.snackbar(
          'Name Conflict',
          'This name is already used by the parent group.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'Unable to Update',
          'Unable to update contact group. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  /// Cancel inline edit
  void _cancelInlineEdit(int contactGroupId) {
    _editingContactGroup[contactGroupId] = false;
    _editNameControllers[contactGroupId]?.dispose();
    _editNameControllers.remove(contactGroupId);
  }

  /// Show popup for adding main contact group
  void _startInlineAddingMainContactGroup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AddEditGroupPopup(
          isHashtagMode: false,
          isMainGroup: true,
          onSave: (name, parentId) async {
            // Use the existing save logic
            if (name.isEmpty) {
              Get.snackbar(
                'Invalid Name',
                'Contact group name cannot be empty',
                backgroundColor: Colors.orange,
                colorText: Colors.white,
              );
              return;
            }

            try {
              final newGroup = await _contactGroupService.addCustomGroup(name);

              if (newGroup == null) {
                Get.snackbar(
                  'Unable to Add',
                  'Unable to add contact group. Please try again.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              } else if (newGroup.id == -1) {
                // Duplicate main contact group name
                Get.snackbar(
                  'Duplicate Contact',
                  'Contact Group with this name already exists.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              } else if (newGroup.id == -3) {
                // Main group name conflicts with existing subgroup
                Get.snackbar(
                  'Name Conflict',
                  'This name is already used by a contact in another group.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }

              await _refreshContactGroupsFromDatabase();

              Get.snackbar(
                'Success',
                'Contact group "$name" added successfully!',
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            } catch (e) {
              debugPrint('[ContactGroupsView] Error adding main contact group: $e');
              Get.snackbar(
                'Unable to Add',
                'Unable to add contact group. Please try again.',
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            }
          },
        );
      },
    );
  }

  /// Cancel inline adding for main contact group
  void _cancelInlineAddingMainContactGroup() {
    _addingMainContactGroup.value = false;
    _mainContactGroupNameController.clear();
  }

  /// Save inline add for main contact group
  Future<void> _saveInlineAddMainContactGroup() async {
    final name = _mainContactGroupNameController.text.trim();

    if (name.isEmpty) {
      Get.snackbar(
        'Invalid Name',
        'Contact group name cannot be empty',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      final newGroup = await _contactGroupService.addCustomGroup(name);

      if (newGroup == null) {
        Get.snackbar(
          'Unable to Add',
          'Unable to add contact group. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      } else if (newGroup.id == -1) {
        // Duplicate main contact group name
        Get.snackbar(
          'Duplicate Contact',
          'Contact Group with this name already exists.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      } else if (newGroup.id == -3) {
        // Main group name conflicts with existing subgroup
        Get.snackbar(
          'Name Conflict',
          'This name is already used by a contact in another group.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      _cancelInlineAddingMainContactGroup();
      await _refreshContactGroupsFromDatabase();

      Get.snackbar(
        'Success',
        'Contact group "$name" added successfully!',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('[ContactGroupsView] Error adding main contact group: $e');
      Get.snackbar(
        'Unable to Add',
        'Unable to add contact group. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }



  /// Build inline add widget
  Widget _buildInlineAddWidget(int parentContactGroupId, UiController uiController) {
    final nameController = _inlineNameControllers[parentContactGroupId]!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), // Match subgroup tile margin
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.grey[900]
            : Colors.grey[100], // Match subgroup tile background
        borderRadius: BorderRadius.circular(2),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 5), // Match subgroup tile padding
        dense: true, // Match subgroup tile density
        title: Row(
          children: [
            // Contact icon to match subgroup tiles
            Icon(
              Icons.person,
              color: Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextSelectionTheme(
                data: TextSelectionThemeData(
                  cursorColor: uiController.currentMainColor,
                  selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                  selectionHandleColor: uiController.currentMainColor,
                ),
                child: TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'add Contact',
                    hintStyle: gfonts.GoogleFonts.kumbhSans(
                      color: uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey[500],
                      fontSize: 18, // Match subgroup tile font size
                    ),
                    border: InputBorder.none, // Remove border to match ListTile style
                    contentPadding: EdgeInsets.zero, // Remove padding to align with icon
                  ),
                  style: gfonts.GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 18, // Match subgroup tile font size
                    fontWeight: FontWeight.w500, // Match subgroup tile font weight
                  ),
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Save button
            IconButton(
              onPressed: () => _saveInlineSubgroup(parentContactGroupId),
              icon: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.green,
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'assets/images/ic_tick.png',
                  width: 20,
                  height: 20,
                ),
              ),
              tooltip: 'Save',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
            // Cancel button
            IconButton(
              onPressed: () => _cancelInlineAdding(parentContactGroupId),
              icon: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.red.withValues(alpha: 0.7),
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'assets/images/ic_cross.png',
                  width: 20,
                  height: 20,
                ),
              ),
              tooltip: 'Cancel',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Save inline added subgroup
  Future<void> _saveInlineSubgroup(int parentContactGroupId) async {
    final nameController = _inlineNameControllers[parentContactGroupId]!;
    final name = nameController.text.trim();

    if (name.isEmpty) {
      Get.snackbar(
        'Invalid Name',
        'Contact name cannot be empty',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      final newSubgroup = await _contactGroupService.addCustomGroup(
        name,
        parentId: parentContactGroupId,
      );

      if (newSubgroup == null) {
        Get.snackbar(
          'Unable to Add',
          'Unable to add contact. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      } else if (newSubgroup.id == -1) {
        // Duplicate subgroup contact name
        Get.snackbar(
          'Duplicate Contact',
          'Contact with this name already exists.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      } else if (newSubgroup.id == -4) {
        // Subgroup name conflicts with parent group
        Get.snackbar(
          'Name Conflict',
          'This name is already used by the parent group.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      _cancelInlineAdding(parentContactGroupId);
      await _refreshContactGroupsFromDatabase();

      Get.snackbar(
        'Success',
        'Contact added successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('[ContactGroupsView] Error adding subgroup: $e');
      Get.snackbar(
        'Unable to Add',
        'Unable to add contact. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }


}