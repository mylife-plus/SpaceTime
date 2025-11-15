import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart' as gfonts;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/hashtag_group_service.dart';
import 'package:spacetime/app/models/hashtag_group_model.dart';
import 'package:spacetime/app/shared/widgets/searchable_hashtag_widget.dart';
import '../../../config/app_text.dart';

class HashtagGroupsView extends StatefulWidget {
  final Function(HashtagGroup)? onHashtagGroupSelected;
  final HashtagGroup? selectedHashtagGroup;

  // Multiple selection mode parameters
  final bool allowMultipleSelection;
  final List<HashtagGroup>? selectedHashtagGroups;
  final Function(List<HashtagGroup>)? onMultipleHashtagGroupsSelected;

  const HashtagGroupsView({
    super.key,
    this.onHashtagGroupSelected,
    this.selectedHashtagGroup,
    this.allowMultipleSelection = false,
    this.selectedHashtagGroups,
    this.onMultipleHashtagGroupsSelected,
  });

  @override
  State<HashtagGroupsView> createState() => _HashtagGroupsViewState();
}

class _HashtagGroupsViewState extends State<HashtagGroupsView> {
  final HashtagGroupService _hashtagGroupService = HashtagGroupService();

  // Reactive state variables
  final RxList<HashtagGroup> _mainHashtagGroups = <HashtagGroup>[].obs;
  final RxBool _isLoading = false.obs;
  final RxMap<int, bool> _expandedHashtagGroups = <int, bool>{}.obs;
  final RxMap<int, bool> _addingToHashtagGroup = <int, bool>{}.obs;
  final RxMap<int, TextEditingController> _inlineNameControllers = <int, TextEditingController>{}.obs;
  final RxMap<int, ExpansionTileController> _expansionControllers = <int, ExpansionTileController>{}.obs;
  final RxMap<int, bool> _pendingAddingMode = <int, bool>{}.obs;

  // Inline editing state for subgroups
  final RxMap<int, bool> _editingHashtagGroup = <int, bool>{}.obs;
  final RxMap<int, TextEditingController> _editNameControllers = <int, TextEditingController>{}.obs;

  // Inline add state for main hashtag groups
  final RxBool _addingMainHashtagGroup = false.obs;
  final TextEditingController _mainHashtagGroupNameController = TextEditingController();

  // Recently selected subgroups storage (max 6 items)
  static const String _recentSubgroupsKey = 'recent_subgroups';
  static const int _maxRecentItems = 6;

  // Multiple selection state
  final RxList<HashtagGroup> _selectedHashtagGroups = <HashtagGroup>[].obs;

  // Global refresh notifier for external access
  final RxInt _globalRefreshNotifier = 0.obs;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[HashtagGroupsView][initState] HashtagGroupsView opened, initializing...',
    );
    debugPrint(
      '[HashtagGroupsView][initState] Multiple selection mode: ${widget.allowMultipleSelection}',
    );
    debugPrint(
      '[HashtagGroupsView][initState] Starting database initialization and hashtag group loading',
    );

    // Initialize selected hashtag groups for multiple selection mode
    if (widget.allowMultipleSelection && widget.selectedHashtagGroups != null) {
      _selectedHashtagGroups.addAll(widget.selectedHashtagGroups!);
      debugPrint(
        '[HashtagGroupsView][initState] Initialized with ${_selectedHashtagGroups.length} pre-selected hashtag groups',
      );
    }

    // Register global refresh notifier for external access
    try {
      Get.put(_globalRefreshNotifier, tag: 'hashtagGroupsRefresh');
      debugPrint(
        '[HashtagGroupsView][initState] Global refresh notifier registered',
      );
    } catch (e) {
      debugPrint(
        '[HashtagGroupsView][initState] Global refresh notifier already registered: $e',
      );
    }

    _loadHashtagGroups();

    // Listen for global refresh triggers
    ever(_globalRefreshNotifier, (timestamp) {
      if (timestamp > 0) {
        debugPrint(
          '[HashtagGroupsView][initState] Global refresh triggered, refreshing hashtag groups...',
        );
        _refreshHashtagGroupsFromDatabase();
      }
    });

    debugPrint(
      '[HashtagGroupsView][initState] HashtagGroupsView initialization completed',
    );
  }

  @override
  void dispose() {
    _mainHashtagGroupNameController.dispose();

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
      Get.delete<RxInt>(tag: 'hashtagGroupsRefresh');
      debugPrint(
        '[HashtagGroupsView][dispose] Global refresh notifier cleaned up',
      );
    } catch (e) {
      debugPrint(
        '[HashtagGroupsView][dispose] Error cleaning up global refresh notifier: $e',
      );
    }

    super.dispose();
  }

  /// Load all main hashtag groups with their subgroups
  Future<void> _loadHashtagGroups() async {
    try {
      _isLoading.value = true;
      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Starting hashtag group loading process',
      );

      // Step 1: Fetch all hashtag groups from database
      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Fetching hashtag groups from database',
      );

      final hashtagGroups = await _hashtagGroupService.getAllGroupsHierarchical();
      _mainHashtagGroups.value = hashtagGroups;

      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Successfully loaded ${hashtagGroups.length} main hashtag groups from database',
      );

      // Verify we have the expected predefined hashtag groups
      if (_mainHashtagGroups.isNotEmpty) {
        debugPrint(
          '[HashtagGroupsView][_loadHashtagGroups] ✅ Database contains hashtag groups - initialization successful',
        );

        // Log hashtag group details for debugging
        for (int i = 0; i < _mainHashtagGroups.length; i++) {
          final hashtagGroup = _mainHashtagGroups[i];
          final subgroupCount = hashtagGroup.subgroups?.length ?? 0;
          final customStatus = hashtagGroup.isCustom ? '(Custom)' : '(Predefined)';
          debugPrint(
            '[HashtagGroupsView][_loadHashtagGroups] Main Hashtag Group ${i + 1}: ${hashtagGroup.name} - $subgroupCount subgroups $customStatus',
          );

          // Log first few subgroups for verification
          if (hashtagGroup.hasSubgroups && i < 3) {
            // Only log first 3 main hashtag groups' subgroups
            for (int j = 0; j < math.min(3, subgroupCount); j++) {
              final sub = hashtagGroup.subgroups![j];
              debugPrint(
                '[HashtagGroupsView][_loadHashtagGroups]   └─ Subgroup: ${sub.name}',
              );
            }
            if (subgroupCount > 3) {
              debugPrint(
                '[HashtagGroupsView][_loadHashtagGroups]   └─ ... and ${subgroupCount - 3} more subgroups',
              );
            }
          }
        }
      } else {
        debugPrint(
          '[HashtagGroupsView][_loadHashtagGroups] ⚠️ No hashtag groups found in database - this may indicate an initialization issue',
        );
      }
    } catch (e) {
      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Error during hashtag group loading/initialization: $e',
      );
      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Error type: ${e.runtimeType}',
      );
      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Stack trace: ${StackTrace.current}',
      );

      Get.snackbar(
        'Unable to Load',
        'Unable to load hashtag groups. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );

      // Set empty hashtag groups to prevent UI errors
      _mainHashtagGroups.value = [];
    } finally {
      _isLoading.value = false;
      debugPrint(
        '[HashtagGroupsView][_loadHashtagGroups] Hashtag group loading process completed',
      );
    }
  }

  /// Refresh hashtag groups from database (used after CRUD operations)
  Future<void> _refreshHashtagGroupsFromDatabase() async {
    try {
      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] ===== REFRESH STARTED =====');

      // Clear all controllers and state before refreshing
      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] 🧹 Clearing all controllers');
      _clearAllControllers();

      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] 🔄 Fetching hashtag groups from service');
      final hashtagGroups = await _hashtagGroupService.getAllGroupsHierarchical();

      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] Retrieved ${hashtagGroups.length} groups from service');
      for (int i = 0; i < hashtagGroups.length; i++) {
        final group = hashtagGroups[i];
        debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] Group $i: ID=${group.id}, Name="${group.name}", Subgroups=${group.subgroups?.length ?? 0}');
      }

      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] 📝 Updating reactive list');
      _mainHashtagGroups.value = hashtagGroups;

      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] ✅ Successfully refreshed ${hashtagGroups.length} main hashtag groups');
    } catch (e) {
      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] ❌ Error refreshing hashtag groups: $e');
      debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] Exception type: ${e.runtimeType}');

      Get.snackbar(
        'Unable to Refresh',
        'Unable to refresh hashtag groups. Please try again.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
    debugPrint('[HashtagGroupsView][_refreshHashtagGroupsFromDatabase] ===== REFRESH COMPLETED =====');
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(HashtagGroup hashtagGroup) {
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
                'Delete Hashtag Group',
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),

              // Message
              Text(
                'Are you sure you want to delete "${hashtagGroup.name}"?',
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
                    onPressed: () => _deleteHashtagGroup(hashtagGroup.id!),
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

  /// Delete a hashtag group
  Future<void> _deleteHashtagGroup(int hashtagGroupId) async {
    try {
      debugPrint(
        '[HashtagGroupsView][_deleteHashtagGroup] Deleting hashtag group ID: $hashtagGroupId',
      );

      final result = await _hashtagGroupService.deleteGroup(hashtagGroupId);

      if (result == true) {
        // Successfully deleted
        Get.back(); // Close confirmation dialog

        // Remove from recent selections before refreshing
        final group = await _hashtagGroupService.getGroupById(hashtagGroupId);
        if (group != null) {
          if (group.parentId == null) {
            // Main group deleted - remove it and all its subgroups from recent selections
            final subgroups = await _hashtagGroupService.getSubgroups(hashtagGroupId);
            await removeGroupAndSubgroupsFromRecent(hashtagGroupId, subgroups);

            // Also remove from searchable hashtag widget recent lists
            final subgroupIds = subgroups.map((s) => s.id!).toList();
            await SearchableHashtagWidget.removeGroupAndSubgroupsFromRecentHashtagGroups(hashtagGroupId, subgroupIds);

            // Remove hashtag names from recent hashtags
            await SearchableHashtagWidget.removeFromRecentHashtags(group.name);
            for (final subgroup in subgroups) {
              await SearchableHashtagWidget.removeFromRecentHashtags(subgroup.name);
            }
          } else {
            // Subgroup deleted - remove only this subgroup from recent selections
            await removeFromRecentlySelectedSubgroups(hashtagGroupId);

            // Also remove from searchable hashtag widget recent lists
            await SearchableHashtagWidget.removeFromRecentHashtagGroups(hashtagGroupId);
            await SearchableHashtagWidget.removeFromRecentHashtags(group.name);
          }
        }

        // Refresh hashtag groups from database to show the deletion
        debugPrint(
          '[HashtagGroupsView][_deleteHashtagGroup] Refreshing hashtag groups from database after deletion',
        );
        await _refreshHashtagGroupsFromDatabase();

        Get.snackbar(
          'Success',
          'Hashtag group deleted successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else if (result == null) {
        // Cannot delete due to memories
        Get.back(); // Close confirmation dialog

        // Get the group name and memory count for the error dialog
        final group = await _hashtagGroupService.getGroupById(hashtagGroupId);
        final memoryCount = group != null
            ? await _hashtagGroupService.getMemoryCountForGroup(group.name)
            : 0;

        _showCannotDeleteDialog(group?.name ?? 'Unknown', memoryCount);
      } else {
        // Failed to delete
        Get.snackbar(
          'Unable to Delete',
          'Unable to delete hashtag group. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[HashtagGroupsView][_deleteHashtagGroup] Error: $e');
      Get.snackbar(
        'Unable to Delete',
        'Unable to delete hashtag group. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Show dialog when hashtag group cannot be deleted due to existing memories
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
                      'Cannot Delete Hashtag Group',
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
                'The hashtag group "$groupName" cannot be deleted because it is being used by $memoryCount ${memoryCount == 1 ? 'memory' : 'memories'}.',
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
                        'To delete this hashtag group, first remove the hashtags from all memories that use them, or delete those memories.',
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

  /// Show edit hashtag group dialog - matches category picker styling
  void _showEditHashtagGroupDialog(HashtagGroup hashtagGroup) {
    debugPrint(
      '[HashtagGroupsView][_showEditHashtagGroupDialog] ===== EDIT DIALOG OPENED =====',
    );
    debugPrint(
      '[HashtagGroupsView][_showEditHashtagGroupDialog] Hashtag Group Details:',
    );
    debugPrint('  - ID: ${hashtagGroup.id}');
    debugPrint('  - Name: "${hashtagGroup.name}"');
    debugPrint('  - Parent ID: ${hashtagGroup.parentId}');
    debugPrint('  - Is Custom: ${hashtagGroup.isCustom}');
    debugPrint('  - Is Subgroup: ${hashtagGroup.isSubgroup}');

    final uiController = Get.find<UiController>();
    final nameController = TextEditingController(text: hashtagGroup.name);
    final focusNode = FocusNode();

    // Auto-focus the text field after dialog is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });

    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: uiController.darkMode.value
                ? Colors.grey[900]
                : Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Text input field
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      cursorColor: uiController.currentMainColor,
                      selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                      selectionHandleColor: uiController.currentMainColor,
                    ),
                  ),
                  child: TextField(
                    controller: nameController,
                    focusNode: focusNode,
                    autofocus: true,
                    cursorColor: uiController.currentMainColor,
                    style: gfonts.GoogleFonts.kumbhSans(
                      color: uiController.darkMode.value ? Colors.white : Colors.black,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Hashtag Group Name',
                      hintStyle: gfonts.GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.grey[500],
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Cancel button (red cross)
              GestureDetector(
                onTap: () => Get.back(),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.red,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      'assets/images/ic_cross.png',
                      width: 10,
                      height: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Save button (green tick)
              GestureDetector(
                onTap: () async {
                  debugPrint('[HashtagGroupsView][EditDialog] ===== SAVE BUTTON PRESSED =====');
                  final name = nameController.text.trim();
                  debugPrint('[HashtagGroupsView][EditDialog] Original name: "${hashtagGroup.name}"');
                  debugPrint('[HashtagGroupsView][EditDialog] New name: "$name"');

                  // Validate that name is provided
                  if (name.isEmpty) {
                    debugPrint('[HashtagGroupsView][EditDialog] ❌ Validation failed: Empty name');
                    Get.snackbar(
                      'Validation Error',
                      'Please enter a hashtag group name',
                      backgroundColor: Colors.orange,
                      colorText: Colors.white,
                    );
                    return;
                  }

                  if (name == hashtagGroup.name) {
                    debugPrint('[HashtagGroupsView][EditDialog] ⚠️ No changes detected, closing dialog');
                    Get.back();
                    return;
                  }

                  try {
                    debugPrint('[HashtagGroupsView][EditDialog] 🔄 Starting update process...');
                    debugPrint('[HashtagGroupsView][EditDialog] Calling updateGroup with:');
                    debugPrint('  - Group ID: ${hashtagGroup.id}');
                    debugPrint('  - New Name: "$name"');

                    final success = await _hashtagGroupService.updateGroup(
                      hashtagGroup.id!,
                      name,
                    );

                    debugPrint('[HashtagGroupsView][EditDialog] Update result: $success');

                    if (success) {
                      debugPrint('[HashtagGroupsView][EditDialog] ✅ Update successful, closing dialog');
                      Get.back(); // Close dialog

                      debugPrint('[HashtagGroupsView][EditDialog] 🔄 Refreshing hashtag groups from database');
                      await _refreshHashtagGroupsFromDatabase();

                      debugPrint('[HashtagGroupsView][EditDialog] ✅ Showing success message');
                      Get.snackbar(
                        'Success',
                        'Hashtag group "$name" updated successfully!',
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                      );
                    } else {
                      debugPrint('[HashtagGroupsView][EditDialog] ❌ Update failed: Service returned false');
                      Get.snackbar(
                        'Unable to Update',
                        'Unable to update hashtag group. Please try again.',
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  } catch (e) {
                    debugPrint('[HashtagGroupsView][EditDialog] ❌ Exception occurred: $e');
                    debugPrint('[HashtagGroupsView][EditDialog] Exception type: ${e.runtimeType}');
                    Get.snackbar(
                      'Unable to Update',
                      'Unable to update hashtag group. Please try again.',
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                    );
                  }
                },
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Image.asset(
                    'assets/images/ic_tick.png',
                    width: 10,
                    height: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Delete a subgroup (hashtag)
  Future<void> _deleteSubgroup(HashtagGroup subgroup) async {
    try {
      debugPrint(
        '[HashtagGroupsView][_deleteSubgroup] Deleting subgroup ID: ${subgroup.id}',
      );

      final result = await _hashtagGroupService.deleteGroup(subgroup.id!);

      if (result == true) {
        // Successfully deleted - also remove from recent selections
        await removeFromRecentlySelectedSubgroups(subgroup.id!);

        // Also remove from searchable hashtag widget recent lists
        await SearchableHashtagWidget.removeFromRecentHashtagGroups(subgroup.id!);
        await SearchableHashtagWidget.removeFromRecentHashtags(subgroup.name);

        // Refresh hashtag groups from database to show the deletion
        debugPrint(
          '[HashtagGroupsView][_deleteSubgroup] Refreshing hashtag groups from database after deletion',
        );
        await _refreshHashtagGroupsFromDatabase();

        Get.snackbar(
          'Success',
          'Hashtag deleted successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else if (result == null) {
        // Cannot delete due to memories
        final memoryCount = await _hashtagGroupService.getMemoryCountForGroup(subgroup.name);
        _showCannotDeleteDialog(subgroup.name, memoryCount);
      } else {
        // Failed to delete
        Get.snackbar(
          'Unable to Delete',
          'Unable to delete hashtag. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[HashtagGroupsView][_deleteSubgroup] Error: $e');
      Get.snackbar(
        'Unable to Delete',
        'Unable to delete hashtag. Please try again.',
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
        debugPrint('[HashtagGroupsView] Error disposing inline controller: $e');
      }
    }
    _inlineNameControllers.clear();

    // Dispose and clear edit name controllers
    for (final controller in _editNameControllers.values) {
      try {
        controller.dispose();
      } catch (e) {
        debugPrint('[HashtagGroupsView] Error disposing edit controller: $e');
      }
    }
    _editNameControllers.clear();

    // Clear expansion controllers (don't dispose as they're managed by ExpansionTile)
    _expansionControllers.clear();

    // Clear all state maps
    _expandedHashtagGroups.clear();
    _addingToHashtagGroup.clear();
    _pendingAddingMode.clear();
    _editingHashtagGroup.clear();
  }



  /// Select a hashtag group and return to parent
  void _selectHashtagGroup(HashtagGroup hashtagGroup) {
    debugPrint(
      '[HashtagGroupsView][_selectHashtagGroup] Selected: ${hashtagGroup.name}',
    );

    // Save to recent subgroups if it's a subgroup
    if (hashtagGroup.isSubgroup) {
      _saveRecentlySelectedSubgroup(hashtagGroup);
    }

    if (widget.allowMultipleSelection) {
      // Multiple selection mode - toggle hashtag group selection
      _toggleHashtagGroupSelection(hashtagGroup);
    } else {
      // Single selection mode - original behavior
      if (widget.onHashtagGroupSelected != null) {
        widget.onHashtagGroupSelected!(hashtagGroup);
      }

      Get.back(result: hashtagGroup);
    }
  }

  /// Toggle hashtag group selection for multiple selection mode
  void _toggleHashtagGroupSelection(HashtagGroup hashtagGroup) {
    final isSelected = _selectedHashtagGroups.any((g) => g.id == hashtagGroup.id);

    if (isSelected) {
      // Deselecting
      _selectedHashtagGroups.removeWhere((g) => g.id == hashtagGroup.id);
      debugPrint(
        '[HashtagGroupsView][_toggleHashtagGroupSelection] Removed: ${hashtagGroup.name}',
      );

      // If this is a main group, also remove all its subgroups
      if (hashtagGroup.isMainGroup && hashtagGroup.hasSubgroups) {
        for (final subgroup in hashtagGroup.subgroups!) {
          _selectedHashtagGroups.removeWhere((g) => g.id == subgroup.id);
          debugPrint(
            '[HashtagGroupsView][_toggleHashtagGroupSelection] Removed subgroup: ${subgroup.name}',
          );
        }
      }

      // If this is a subgroup, check if we should deselect the main group
      if (hashtagGroup.isSubgroup) {
        final mainGroup = _findMainGroupForSubgroup(hashtagGroup);
        if (mainGroup != null) {
          _selectedHashtagGroups.removeWhere((g) => g.id == mainGroup.id);
          debugPrint(
            '[HashtagGroupsView][_toggleHashtagGroupSelection] Removed main group: ${mainGroup.name} (subgroup was deselected)',
          );
        }
      }
    } else {
      // Selecting
      // If this is a main group, only add its subgroups (not the main group itself)
      if (hashtagGroup.isMainGroup && hashtagGroup.hasSubgroups) {
        for (final subgroup in hashtagGroup.subgroups!) {
          if (!_selectedHashtagGroups.any((g) => g.id == subgroup.id)) {
            _selectedHashtagGroups.add(subgroup);
            debugPrint(
              '[HashtagGroupsView][_toggleHashtagGroupSelection] Added subgroup: ${subgroup.name}',
            );
          }
        }
        debugPrint(
          '[HashtagGroupsView][_toggleHashtagGroupSelection] Selected main group: ${hashtagGroup.name} (added ${hashtagGroup.subgroups!.length} subgroups)',
        );
      } else {
        // For subgroups, add them directly
        _selectedHashtagGroups.add(hashtagGroup);
        debugPrint(
          '[HashtagGroupsView][_toggleHashtagGroupSelection] Added: ${hashtagGroup.name}',
        );

        // Save to recent subgroups
        _saveRecentlySelectedSubgroup(hashtagGroup);
      }
    }

    debugPrint(
      '[HashtagGroupsView][_toggleHashtagGroupSelection] Total selected: ${_selectedHashtagGroups.length}',
    );
  }

  /// Find the main group for a given subgroup
  HashtagGroup? _findMainGroupForSubgroup(HashtagGroup subgroup) {
    for (final mainGroup in _mainHashtagGroups) {
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
  bool _areAllSubgroupsSelected(HashtagGroup mainGroup) {
    if (!mainGroup.hasSubgroups) return false;

    for (final subgroup in mainGroup.subgroups!) {
      if (!_selectedHashtagGroups.any((g) => g.id == subgroup.id)) {
        return false;
      }
    }
    return true;
  }

  /// Check if a main group is selected (meaning all its subgroups are selected)
  bool _isMainGroupSelected(HashtagGroup mainGroup) {
    return _selectedHashtagGroups.any((g) => g.id == mainGroup.id);
  }

  /// Handle done button press for multiple selection mode
  void _onDonePressed() {
    debugPrint(
      '[HashtagGroupsView][_onDonePressed] Returning ${_selectedHashtagGroups.length} selected hashtag groups',
    );

    if (widget.onMultipleHashtagGroupsSelected != null) {
      widget.onMultipleHashtagGroupsSelected!(_selectedHashtagGroups.toList());
    }

    Get.back(result: _selectedHashtagGroups.toList());
  }

  /// Start inline adding for a hashtag group
  void _startInlineAdding(int hashtagGroupId) {
    final isCurrentlyExpanded = _expandedHashtagGroups[hashtagGroupId] ?? false;

    if (!isCurrentlyExpanded) {
      // If not expanded, use the controller to expand (this will trigger onExpansionChanged)
      final controller = _expansionControllers[hashtagGroupId];
      if (controller != null && !controller.isExpanded) {
        // Set a flag to indicate we're expanding for adding mode
        _pendingAddingMode[hashtagGroupId] = true;
        controller.expand();
      }
    } else {
      // If already expanded, just enable adding mode
      _enableAddingMode(hashtagGroupId);
    }

    debugPrint('[HashtagGroupsView][_startInlineAdding] Started inline adding for hashtag group: $hashtagGroupId, controller expanded: ${_expansionControllers[hashtagGroupId]?.isExpanded}, tracked expanded: ${_expandedHashtagGroups[hashtagGroupId]}, adding: ${_addingToHashtagGroup[hashtagGroupId]}');
  }

  /// Helper method to enable adding mode
  void _enableAddingMode(int hashtagGroupId) {
    _addingToHashtagGroup[hashtagGroupId] = true;

    // Initialize controllers
    _inlineNameControllers[hashtagGroupId] = TextEditingController();
  }

  /// Cancel inline adding
  void _cancelInlineAdding(int hashtagGroupId) {
    _addingToHashtagGroup[hashtagGroupId] = false;
    _inlineNameControllers[hashtagGroupId]?.dispose();
    _inlineNameControllers.remove(hashtagGroupId);
  }

  /// Save recently selected subgroup
  Future<void> _saveRecentlySelectedSubgroup(HashtagGroup subgroup) async {
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

      debugPrint('[HashtagGroupsView] Saved recent subgroup: ${subgroup.name} (ID: ${subgroup.id})');
      debugPrint('[HashtagGroupsView] Total recent subgroups: ${recentList.length}');
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error saving recent subgroup: $e');
    }
  }

  /// Get recently selected subgroups
  static Future<List<HashtagGroup>> getRecentlySelectedSubgroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_recentSubgroupsKey);

      if (existingJson == null) return [];

      final decoded = json.decode(existingJson) as List;
      final recentList = decoded.cast<Map<String, dynamic>>();

      // Convert back to HashtagGroup objects
      final recentSubgroups = <HashtagGroup>[];
      for (final item in recentList) {
        try {
          final subgroup = HashtagGroup.fromJson(item);
          recentSubgroups.add(subgroup);
        } catch (e) {
          debugPrint('[HashtagGroupsView] Error parsing recent subgroup: $e');
          // Skip invalid entries
        }
      }

      debugPrint('[HashtagGroupsView] Loaded ${recentSubgroups.length} recent subgroups');
      return recentSubgroups;
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error getting recent subgroups: $e');
      return [];
    }
  }

  /// Remove a specific hashtag group from recently selected subgroups
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
        debugPrint('[HashtagGroupsView] Removed group ID $groupId from recent subgroups');
      }
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error removing from recent subgroups: $e');
    }
  }

  /// Remove hashtag group and all its subgroups from recently selected subgroups
  static Future<void> removeGroupAndSubgroupsFromRecent(int mainGroupId, List<HashtagGroup> subgroups) async {
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
        debugPrint('[HashtagGroupsView] Removed main group ID $mainGroupId and ${subgroups.length} subgroups from recent subgroups');
      }
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error removing group and subgroups from recent: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return PopScope(
      canPop: !widget.allowMultipleSelection || _selectedHashtagGroups.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop &&
            widget.allowMultipleSelection &&
            _selectedHashtagGroups.isNotEmpty) {
          _onDonePressed();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading:
              widget.allowMultipleSelection
                  ? Obx(
                    () => IconButton(
                      onPressed:
                          _selectedHashtagGroups.isNotEmpty
                              ? _onDonePressed
                              : () => Get.back(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: _selectedHashtagGroups.isNotEmpty ? 'Done' : 'Back',
                    ),
                  )
                  : null,
          title: Obx(
            () => Text(
              widget.allowMultipleSelection
                  ? 'Hashtags'
                  : AppTexts.hashTagGroups,
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
                onPressed: () => _startInlineAddingMainHashtagGroup(),
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
                tooltip: 'Add New Hashtag Group',
              ),
          ],
        ),
        body: Column(
          children: [
            // Selection indicator when in filter mode
            if (widget.allowMultipleSelection)
              Obx(() {
                // if (_selectedHashtagGroups.isEmpty) {
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
                        Text(
                          '${(_selectedHashtagGroups.isEmpty) ? 0 :_selectedHashtagGroups.length} selected',
                          style: gfonts.GoogleFonts.kumbhSans(
                            color: uiController.currentMainColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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

  /// Build main content (hierarchical hashtag groups)
  Widget _buildMainContent(UiController uiController) {
    return Container(
      color: uiController.darkMode.value
          ? Colors.black
          : uiController.currentMainColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: _buildHierarchicalHashtagGroups(),
      ),
    );
  }



  /// Build hierarchical hashtag groups
  Widget _buildHierarchicalHashtagGroups() {
    final uiController = Get.find<UiController>();

    return ListView(
      children: [
        // Inline add widget for main hashtag groups (at the top)
        Obx(() => _addingMainHashtagGroup.value
            ? _buildInlineAddMainHashtagGroupWidget()
            : const SizedBox.shrink()),

        // Show empty state message if no groups and not adding
        if (_mainHashtagGroups.isEmpty)
          Obx(() => !_addingMainHashtagGroup.value
              ? Container(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      'No hashtag groups found.\nTap + to add a new group.',
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

        // Main hashtag groups
        ..._mainHashtagGroups.map((mainHashtagGroup) =>
            _buildMainHashtagGroupExpansionTile(mainHashtagGroup)),
      ],
    );
  }

  /// Build main hashtag group expansion tile
  Widget _buildMainHashtagGroupExpansionTile(HashtagGroup mainHashtagGroup) {
    final uiController = Get.find<UiController>();
    final isExpanded = _expandedHashtagGroups[mainHashtagGroup.id] ?? false;

    // Create a new expansion controller for this group to avoid state conflicts
    final groupId = mainHashtagGroup.id!;
    _expansionControllers[groupId] = ExpansionTileController();
    final controller = _expansionControllers[groupId]!;

    return Obx(() {
      // Check if all subgroups are selected (for filter mode)
      final allSubgroupsSelected = widget.allowMultipleSelection &&
          mainHashtagGroup.subgroups != null &&
          mainHashtagGroup.subgroups!.isNotEmpty &&
          mainHashtagGroup.subgroups!.every((subgroup) =>
              _selectedHashtagGroups.any((g) => g.id == subgroup.id));

      // Count selected subgroups
      final selectedSubgroupsCount = widget.allowMultipleSelection &&
          mainHashtagGroup.subgroups != null
          ? mainHashtagGroup.subgroups!.where((subgroup) =>
              _selectedHashtagGroups.any((g) => g.id == subgroup.id)).length
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
            // Grey container with border for the hashtag group header
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
                key: ValueKey('hashtag_group_${mainHashtagGroup.id}'),
                controller: controller,
                initiallyExpanded: isExpanded,
                onExpansionChanged: (expanded) {
                  _expandedHashtagGroups[mainHashtagGroup.id!] = expanded;

                  // Check if we need to enable adding mode after expansion
                  if (expanded && (_pendingAddingMode[mainHashtagGroup.id!] ?? false)) {
                    _pendingAddingMode[mainHashtagGroup.id!] = false;
                    _enableAddingMode(mainHashtagGroup.id!);
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
                        onTap: () => _selectHashtagGroup(mainHashtagGroup),
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
                      ? () => _selectHashtagGroup(mainHashtagGroup)
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
                                  text: mainHashtagGroup.name,
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
                                    text: '/${mainHashtagGroup.subgroups?.length ?? 0})',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  )
                                else
                                  TextSpan(
                                    text: ' (${mainHashtagGroup.subgroups?.length ?? 0})',
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
                      // Edit button for main hashtag group
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
                        onPressed: () => _showEditHashtagGroupDialog(mainHashtagGroup),
                        tooltip: 'Edit Hashtag Group',
                      ),
                      // Delete button for main hashtag group (only show if no subgroups)
                      if ((mainHashtagGroup.subgroups?.isEmpty ?? true))
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
                          onPressed: () => _showDeleteConfirmation(mainHashtagGroup),
                          tooltip: 'Delete Hashtag Group',
                        ),
                      // Add subgroup button
                      IconButton(
                        onPressed: (_addingToHashtagGroup[mainHashtagGroup.id] ?? false)
                            ? null
                            : () => _startInlineAdding(mainHashtagGroup.id!),
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
                          (_expandedHashtagGroups[mainHashtagGroup.id!] ?? false)
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
              if (mainHashtagGroup.subgroups != null && mainHashtagGroup.subgroups!.isNotEmpty)
                ..._buildSubgroupsList(mainHashtagGroup, uiController),

              // Inline adding widget
              Obx(() {
                if (_addingToHashtagGroup[mainHashtagGroup.id] ?? false) {
                  return _buildInlineAddWidget(mainHashtagGroup.id!, uiController);
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
  List<Widget> _buildSubgroupsList(HashtagGroup mainHashtagGroup, UiController uiController) {
    return mainHashtagGroup.subgroups!.asMap().entries.map((entry) {
      final index = entry.key;
      final subgroup = entry.value;
      final isLast = index == mainHashtagGroup.subgroups!.length - 1;

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
  Widget _buildSubgroupTile(HashtagGroup subgroup, UiController uiController) {
    final isSelected = widget.allowMultipleSelection &&
        _selectedHashtagGroups.any((g) => g.id == subgroup.id);

    return Obx(() {
      final isEditing = _editingHashtagGroup[subgroup.id] ?? false;

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
                  text: '#  ',
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
              ? () => _selectHashtagGroup(subgroup)
              : () => _selectHashtagGroup(subgroup),
        ),
      );
    });
  }



  /// Build inline add widget for main hashtag groups
  Widget _buildInlineAddMainHashtagGroupWidget() {
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
                    controller: _mainHashtagGroupNameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'add Hashtag Name',
                      // hintText: 'Hashtag group name',
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
                onPressed: () => _saveInlineAddMainHashtagGroup(),
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
                onPressed: () => _cancelInlineAddingMainHashtagGroup(),
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

  /// Start inline editing for a subgroup
  void _startInlineEditing(HashtagGroup hashtagGroup) {
    _editingHashtagGroup[hashtagGroup.id!] = true;
    _editNameControllers[hashtagGroup.id!] = TextEditingController(text: hashtagGroup.name);
  }

  /// Build inline edit widget
  Widget _buildInlineEditWidget(HashtagGroup hashtagGroup, UiController uiController) {
    final nameController = _editNameControllers[hashtagGroup.id!]!;

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
                      hintText: 'edit Hashtag',
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
                onPressed: () => _saveInlineEdit(hashtagGroup),
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
                onPressed: () => _cancelInlineEdit(hashtagGroup.id!),
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
  Future<void> _saveInlineEdit(HashtagGroup hashtagGroup) async {
    final nameController = _editNameControllers[hashtagGroup.id!]!;
    final newName = nameController.text.trim();

    if (newName.isEmpty) {
      Get.snackbar(
        'Invalid Name',
        'Hashtag group name cannot be empty',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      await _hashtagGroupService.updateGroup(hashtagGroup.id!, newName);

      // Update in recents if it exists
      await SearchableHashtagWidget.updateHashtagGroupInRecents(hashtagGroup.id!, newName);

      _cancelInlineEdit(hashtagGroup.id!);
      await _refreshHashtagGroupsFromDatabase();

      Get.snackbar(
        'Success',
        'Hashtag updated successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error updating hashtag group: $e');
      if (e.toString().contains('DUPLICATE_HASHTAG_NAME')) {
        final message = hashtagGroup.parentId == null
            ? 'Hashtag Group with this name already exists.'
            : 'Hashtag with this name already exists.';
        Get.snackbar(
          'Duplicate Hashtag',
          message,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else if (e.toString().contains('MAIN_GROUP_CONFLICTS_WITH_SUBGROUP')) {
        Get.snackbar(
          'Name Conflict',
          'This name is already used by a hashtag in another group.',
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
          'Unable to update hashtag group. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  /// Cancel inline edit
  void _cancelInlineEdit(int hashtagGroupId) {
    _editingHashtagGroup[hashtagGroupId] = false;
    _editNameControllers[hashtagGroupId]?.dispose();
    _editNameControllers.remove(hashtagGroupId);
  }

  /// Start inline adding for main hashtag group
  void _startInlineAddingMainHashtagGroup() {
    _addingMainHashtagGroup.value = true;
    _mainHashtagGroupNameController.clear();

    // Auto-focus the text field after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The focus will be handled by the TextField's autofocus property
    });
  }

  /// Cancel inline adding for main hashtag group
  void _cancelInlineAddingMainHashtagGroup() {
    _addingMainHashtagGroup.value = false;
    _mainHashtagGroupNameController.clear();
  }

  /// Save inline add for main hashtag group
  Future<void> _saveInlineAddMainHashtagGroup() async {
    final name = _mainHashtagGroupNameController.text.trim();

    if (name.isEmpty) {
      Get.snackbar(
        'Invalid Name',
        'Hashtag group name cannot be empty',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      final newGroup = await _hashtagGroupService.addCustomGroup(name);

      if (newGroup == null) {
        Get.snackbar(
          'Unable to Add',
          'Unable to add hashtag group. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      } else if (newGroup.id == -1) {
        // Duplicate main hashtag group name
        Get.snackbar(
          'Duplicate Hashtag',
          'Hashtag Group with this name already exists.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      } else if (newGroup.id == -3) {
        // Main group name conflicts with existing subgroup
        Get.snackbar(
          'Name Conflict',
          'This name is already used by a hashtag in another group.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      _cancelInlineAddingMainHashtagGroup();
      await _refreshHashtagGroupsFromDatabase();

      Get.snackbar(
        'Success',
        'Hashtag group "$name" added successfully!',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error adding main hashtag group: $e');
      Get.snackbar(
        'Unable to Add',
        'Unable to add hashtag group. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }



  /// Build inline add widget
  Widget _buildInlineAddWidget(int parentHashtagGroupId, UiController uiController) {
    final nameController = _inlineNameControllers[parentHashtagGroupId]!;

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
            // Hash symbol to match subgroup tiles
            Text(
              '#  ',
              style: gfonts.GoogleFonts.kumbhSans(
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
                fontSize: 20,
              ),
            ),
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
                    hintText: 'add Hashtag',
                    hintStyle: gfonts.GoogleFonts.kumbhSans(
                      color: uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey[500],
                      fontSize: 18, // Match subgroup tile font size
                    ),
                    border: InputBorder.none, // Remove border to match ListTile style
                    contentPadding: EdgeInsets.zero, // Remove padding to align with hash symbol
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
              onPressed: () => _saveInlineSubgroup(parentHashtagGroupId),
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
              onPressed: () => _cancelInlineAdding(parentHashtagGroupId),
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
  Future<void> _saveInlineSubgroup(int parentHashtagGroupId) async {
    final nameController = _inlineNameControllers[parentHashtagGroupId]!;
    final name = nameController.text.trim();

    if (name.isEmpty) {
      Get.snackbar(
        'Invalid Name',
        'Hashtag name cannot be empty',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      final newSubgroup = await _hashtagGroupService.addCustomGroup(
        name,
        parentId: parentHashtagGroupId,
      );

      if (newSubgroup == null) {
        Get.snackbar(
          'Unable to Add',
          'Unable to add hashtag. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      } else if (newSubgroup.id == -1) {
        // Duplicate subgroup hashtag name
        Get.snackbar(
          'Duplicate Hashtag',
          'Hashtag with this name already exists.',
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

      _cancelInlineAdding(parentHashtagGroupId);
      await _refreshHashtagGroupsFromDatabase();

      Get.snackbar(
        'Success',
        'Hashtag added successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('[HashtagGroupsView] Error adding subgroup: $e');
      Get.snackbar(
        'Unable to Add',
        'Unable to add hashtag. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }


}