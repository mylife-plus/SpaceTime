import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/models/contact_group_model.dart';
import 'package:spacetime/app/services/contact_group_service.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/contact_groups/views/contact_groups_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SearchableContactWidget extends StatefulWidget {
  final String title;
  final Function(String) onContactSelected;
  final Function(ContactGroup)? onGroupSelected;
  final Function(bool isFocused)? onFocusChanged;
  final bool showActionButtons;
  final String? iconPath;
  final Color? backgroundColor;
  final bool isCompact;

  /// Previously selected contacts to pass to the picker (for filter mode)
  final List<String>? previouslySelectedContacts;

  /// Callback when multiple contact groups are selected from the picker (for filter mode)
  /// This is called when user returns from the picker with a new selection
  final Function(List<ContactGroup> groups)? onMultipleGroupsSelectedFromPicker;

  /// Whether this widget is being used inside a filter overlay (affects padding)
  final bool isInFilterMode;

  const SearchableContactWidget({
    super.key,
    this.title = 'Search Contacts',
    required this.onContactSelected,
    this.onGroupSelected,
    this.onMultipleGroupsSelectedFromPicker,
    this.onFocusChanged,
    this.showActionButtons = false,
    this.iconPath,
    this.backgroundColor,
    this.isCompact = false,
    this.previouslySelectedContacts,
    this.isInFilterMode = false,
  });

  @override
  State<SearchableContactWidget> createState() => _SearchableContactWidgetState();

  /// Remove deleted contact group from recent contact groups
  static Future<void> removeFromRecentContactGroups(int groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_contact_groups_filter') ?? [];

      // Remove the deleted group from recent list
      final originalLength = recentGroupsJson.length;
      recentGroupsJson.removeWhere((item) {
        try {
          final data = json.decode(item);
          return data['id'] == groupId;
        } catch (e) {
          return false;
        }
      });

      if (recentGroupsJson.length != originalLength) {
        await prefs.setStringList('recent_contact_groups_filter', recentGroupsJson);
        debugPrint('[SearchableContactWidget] Removed group ID $groupId from recent contact groups');
      }
    } catch (e) {
      debugPrint('[SearchableContactWidget] Error removing group from recent: $e');
    }
  }

  /// Remove contact group and all its subgroups from recent contact groups
  static Future<void> removeGroupAndSubgroupsFromRecentContactGroups(int mainGroupId, List<int> subgroupIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_contact_groups_filter') ?? [];

      // Remove main group and all its subgroups from recent list
      final originalLength = recentGroupsJson.length;
      recentGroupsJson.removeWhere((item) {
        try {
          final data = json.decode(item);
          final itemId = data['id'];
          // Remove if it's the main group or any of its subgroups
          if (itemId == mainGroupId) return true;
          return subgroupIds.contains(itemId);
        } catch (e) {
          return false;
        }
      });

      if (recentGroupsJson.length != originalLength) {
        await prefs.setStringList('recent_contact_groups_filter', recentGroupsJson);
        debugPrint('[SearchableContactWidget] Removed main group ID $mainGroupId and ${subgroupIds.length} subgroups from recent contact groups');
      }
    } catch (e) {
      debugPrint('[SearchableContactWidget] Error removing group and subgroups from recent: $e');
    }
  }

  /// Update contact group name in recent contact groups
  static Future<void> updateContactGroupInRecents(int groupId, String newName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_contact_groups_filter') ?? [];

      bool updated = false;
      final updatedList = recentGroupsJson.map((item) {
        try {
          final data = json.decode(item);
          if (data['id'] == groupId) {
            data['name'] = newName;
            data['timestamp'] = DateTime.now().millisecondsSinceEpoch;
            updated = true;
            return json.encode(data);
          }
          return item;
        } catch (e) {
          return item;
        }
      }).toList();

      if (updated) {
        await prefs.setStringList('recent_contact_groups_filter', updatedList);
        debugPrint('[SearchableContactWidget] Updated contact group ID $groupId to "$newName" in recent contact groups');
      }
    } catch (e) {
      debugPrint('[SearchableContactWidget] Error updating contact group in recents: $e');
    }
  }
}

class _SearchableContactWidgetState extends State<SearchableContactWidget> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ContactGroupService _contactGroupService = ContactGroupService();
  
  final RxBool _showResults = false.obs;
  final RxList<String> _searchResults = <String>[].obs;
  final RxList<ContactGroup> _groupResults = <ContactGroup>[].obs;
  final RxList<String> _recentContacts = <String>[].obs;
  final RxList<String> _recentContactGroups = <String>[].obs; // Track which recent items are groups
  final RxBool _isLoading = false.obs;

  List<String> _allContacts = [];
  List<ContactGroup> _allGroups = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final isFocused = _focusNode.hasFocus;
    if (isFocused) {
      _showResults.value = true;
    } else {
      // If losing focus, collapse the widget
      _showResults.value = false;
      debugPrint('[SearchableContactWidget] Collapsed due to focus loss');
    }
    widget.onFocusChanged?.call(isFocused);
    debugPrint('[SearchableContactWidget] Focus changed: $isFocused');
  }

  Future<void> _loadData() async {
    _isLoading.value = true;
    try {
      // Load contact groups
      _allGroups = await _contactGroupService.getAllGroupsHierarchical();

      // Load actual contacts from AddMemoriesController if available
      try {
        final controller = Get.find<AddMemoriesController>();
        _allContacts = List.from(controller.getAvailableContacts);
      } catch (e) {
        debugPrint('[SearchableContactWidget] AddMemoriesController not found, using group names: $e');
        // Fallback: Extract contact names from groups (both main groups and subgroups)
        _allContacts = [];
        for (final group in _allGroups) {
          _allContacts.add(group.name);
          if (group.subgroups != null) {
            for (final subgroup in group.subgroups!) {
              _allContacts.add(subgroup.name);
            }
          }
        }
      }

      // Load recent contacts from SharedPreferences
      await _loadRecentContacts();

    } catch (e) {
      debugPrint('[SearchableContactWidget] Error loading data: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> _loadRecentContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentContactsJson = prefs.getStringList('recent_contacts_filter') ?? [];

      // Load recent contacts (individual contacts)
      final recentContacts = <String>[];
      for (final contactJson in recentContactsJson) {
        try {
          final contactData = json.decode(contactJson);
          if (contactData is Map<String, dynamic> && contactData.containsKey('name')) {
            recentContacts.add(contactData['name']);
          }
        } catch (e) {
          debugPrint('[SearchableContactWidget] Error parsing recent contact: $e');
        }
      }

      // Load recent contact groups
      final recentGroupsJson = prefs.getStringList('recent_contact_groups_filter') ?? [];
      final recentGroups = <String>[];
      final mainCategoryGroups = <String>[]; // Track which groups are main categories (parentId is null)
      for (final groupJson in recentGroupsJson) {
        try {
          final groupData = json.decode(groupJson);
          if (groupData is Map<String, dynamic> && groupData.containsKey('name')) {
            recentGroups.add(groupData['name']);
            // Check if this is a main category (parentId is null)
            if (groupData['parentId'] == null) {
              mainCategoryGroups.add(groupData['name']);
            }
          }
        } catch (e) {
          debugPrint('[SearchableContactWidget] Error parsing recent contact group: $e');
        }
      }

      // Combine recent contacts and groups, prioritizing groups (max 6 items total)
      final combinedRecent = <String>[];
      final groupNames = <String>[];

      combinedRecent.addAll(recentGroups.take(6)); // Max 6 groups
      groupNames.addAll(mainCategoryGroups.take(6)); // Track which are MAIN CATEGORY groups (not subcategories)

      if (combinedRecent.length < 6) {
        combinedRecent.addAll(recentContacts.take(6 - combinedRecent.length)); // Fill remaining with contacts
      }

      _recentContacts.value = combinedRecent;
      _recentContactGroups.value = groupNames; // Store which items are main category groups
      debugPrint('[SearchableContactWidget] Loaded ${combinedRecent.length} recent items (${groupNames.length} main category groups)');

    } catch (e) {
      debugPrint('[SearchableContactWidget] Error loading recent contacts: $e');
      _recentContacts.value = [];
      _recentContactGroups.value = [];
    }
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      _searchResults.clear();
      _groupResults.clear();
      return;
    }

    final lowerQuery = query.toLowerCase();
    
    // Search individual contacts
    final contactResults = _allContacts
        .where((contact) => contact.toLowerCase().contains(lowerQuery))
        .take(10)
        .toList();
    
    // Search groups (both main groups and subgroups)
    final groupResults = <ContactGroup>[];
    for (final group in _allGroups) {
      if (group.name.toLowerCase().contains(lowerQuery)) {
        groupResults.add(group);
      }
      if (group.subgroups != null) {
        for (final subgroup in group.subgroups!) {
          if (subgroup.name.toLowerCase().contains(lowerQuery)) {
            groupResults.add(subgroup);
          }
        }
      }
    }
    
    _searchResults.value = contactResults;
    _groupResults.value = groupResults.take(5).toList();
  }

  void _selectContact(String contact) {
    widget.onContactSelected(contact);
    _saveRecentContact(contact);
    _searchController.clear();
    _showResults.value = false;
    _focusNode.unfocus();
  }

  void _selectGroup(ContactGroup group) {
    if (widget.onGroupSelected != null) {
      widget.onGroupSelected!(group);
    }
    _saveRecentContactGroup(group);
    _searchController.clear();
    _showResults.value = false;
    _focusNode.unfocus();
  }

  Future<void> _saveRecentContact(String contact) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentContactsJson = prefs.getStringList('recent_contacts_filter') ?? [];

      // Create contact data
      final contactData = {
        'name': contact,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Remove if already exists
      recentContactsJson.removeWhere((item) {
        try {
          final data = json.decode(item);
          return data['name'] == contact;
        } catch (e) {
          return false;
        }
      });

      // Add to beginning
      recentContactsJson.insert(0, json.encode(contactData));

      // Keep only last 10 items
      if (recentContactsJson.length > 10) {
        recentContactsJson.removeRange(10, recentContactsJson.length);
      }

      await prefs.setStringList('recent_contacts_filter', recentContactsJson);
      debugPrint('[SearchableContactWidget] Saved recent contact: $contact');

    } catch (e) {
      debugPrint('[SearchableContactWidget] Error saving recent contact: $e');
    }
  }

  Future<void> _saveRecentContactGroup(ContactGroup group) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_contact_groups_filter') ?? [];

      // Create group data
      final groupData = {
        'id': group.id,
        'name': group.name,
        'parentId': group.parentId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Remove if already exists
      recentGroupsJson.removeWhere((item) {
        try {
          final data = json.decode(item);
          return data['id'] == group.id;
        } catch (e) {
          return false;
        }
      });

      // Add to beginning
      recentGroupsJson.insert(0, json.encode(groupData));

      // Keep only last 6 items
      if (recentGroupsJson.length > 6) {
        recentGroupsJson.removeRange(6, recentGroupsJson.length);
      }

      await prefs.setStringList('recent_contact_groups_filter', recentGroupsJson);
      debugPrint('[SearchableContactWidget] Saved recent contact group: ${group.name}');

    } catch (e) {
      debugPrint('[SearchableContactWidget] Error saving recent contact group: $e');
    }
  }

  Widget _buildSearchField(UiController uiController) {
    return SizedBox(
      height: 20, // Fixed height to match icon height
      child: TextField(
      controller: _searchController,
      focusNode: _focusNode,
      style: AppFonts.medium(16, color: uiController.darkMode.value ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: widget.title,
        hintStyle: AppFonts.regular(16, color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 2), // Center text with 20px icon
        suffixIcon: _searchController.text.isNotEmpty ? GestureDetector(
          onTap: () {
            _searchController.clear();
            _performSearch('');
          },
          child: Icon(
            Icons.clear,
            size: 18,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
          ),
        ) : null,
      ),
      onChanged: _performSearch,
    ),
    );
  }

  Widget _buildDisplayText(UiController uiController) {
    return Text(
      widget.title,
      style: AppFonts.regular(16, color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? (uiController.darkMode.value
            ? Colors.grey[850]
            : Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                widget.iconPath ?? AppImages.mention,
                width: 20,
                height: 20,
                color: uiController.darkMode.value ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _showResults.value
                    ? _buildSearchField(uiController)
                    : GestureDetector(
                        onTap: () {
                          _showResults.value = true;
                          _focusNode.requestFocus();
                        },
                        child: _buildDisplayText(uiController),
                      ),
              ),
            ],
          ),

          // Search results
          if (_showResults.value) ...[
            // const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              child: Column(
                children: [
                  // Results list
                  Expanded(
                    child: _isLoading.value
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _buildResultsList(uiController),
                  ),

                  // Bottom "See List" button (sticky)
                  _buildSeeListButton(uiController),
                ],
              ),
            ),
          ],
        ],
      ),
    ));
  }

  Widget _buildResultsList(UiController uiController) {
    final hasSearchQuery = _searchController.text.isNotEmpty;
    final hasResults = _searchResults.isNotEmpty || _groupResults.isNotEmpty;
    final hasRecent = _recentContacts.isNotEmpty;

    final allItems = <Widget>[];

    if (hasSearchQuery && !hasResults) {
      // Show "No contacts found" message
      allItems.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: const Text(
          'No contacts found',
          style: TextStyle(color: Colors.grey),
        ),
      ));
    } else if (!hasSearchQuery && !hasRecent) {
      // Show "No recent contacts" message
      allItems.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Text(
          'No recent contacts',
          style: AppFonts.medium(
            14,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
        ),
      ));
    } else {
      // Add search results or recent contacts
      if (hasSearchQuery) {
        // Group results
        for (int i = 0; i < _groupResults.length; i++) {
          allItems.add(_buildGroupItem(_groupResults[i], uiController));
          if (i < _groupResults.length - 1 || _searchResults.isNotEmpty) {
            allItems.add(Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)));
          }
        }
        // Individual contact results
        for (int i = 0; i < _searchResults.length; i++) {
          allItems.add(_buildContactItem(_searchResults[i], uiController));
          if (i < _searchResults.length - 1) {
            allItems.add(Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)));
          }
        }
      } else {
        // Recent contacts
        for (int i = 0; i < _recentContacts.length; i++) {
          allItems.add(_buildContactItem(_recentContacts[i], uiController));
          if (i < _recentContacts.length - 1) {
            allItems.add(Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)));
          }
        }
      }
    }

    return ListView(
      shrinkWrap: true,
      children: allItems,
    );
  }

  Widget _buildContactItem(String contact, UiController uiController) {
    // Check if this item is a group (exists in _recentContactGroups)
    final isGroup = _recentContactGroups.contains(contact);

    return InkWell(
      onTap: () => _selectContact(contact),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              '@',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: uiController.darkMode.value ? Colors.white : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                contact,
                style: AppFonts.medium(18, color: uiController.darkMode.value ? Colors.white : Colors.black87),
              ),
            ),
            // Show folder icon for groups
            if (isGroup)
              Icon(
                Icons.folder_outlined,
                size: 18,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItem(ContactGroup group, UiController uiController) {
    // Check if this is a main category (parentId is null)
    final isMainCategory = group.parentId == null;

    return InkWell(
      onTap: () => _selectGroup(group),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              '@',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: uiController.darkMode.value ? Colors.white : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.name,
                style: AppFonts.medium(18, color: uiController.darkMode.value ? Colors.white : Colors.black87),
              ),
            ),
            // Show folder icon only for main categories (not subcategories)
            if (isMainCategory)
              Icon(
                Icons.folder_outlined,
                size: 18,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeeListButton(UiController uiController) {
    return Container(
      child: Column(
        children: [
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)),
          InkWell(
            onTap: () async {
              // Convert previously selected contact strings to ContactGroup objects
              List<ContactGroup>? previouslySelected;
              if (widget.previouslySelectedContacts != null && widget.previouslySelectedContacts!.isNotEmpty) {
                previouslySelected = await _convertContactStringsToGroups(widget.previouslySelectedContacts!);
                debugPrint('[SearchableContactWidget] Passing ${previouslySelected.length} previously selected contact groups to picker');
              }
      
              // Navigate to Contact Groups page in multiple selection mode
              final result = await Get.to(
                () => ContactGroupsView(
                  allowMultipleSelection: true,
                  selectedContactGroups: previouslySelected,
                  onMultipleContactGroupsSelected: (selectedGroups) {
                    // If we have a callback for replacing selection (filter mode), use it
                    if (widget.onMultipleGroupsSelectedFromPicker != null) {
                      widget.onMultipleGroupsSelectedFromPicker!(selectedGroups);
                      // Save each selected group to recents
                      for (final group in selectedGroups) {
                        _saveRecentContactGroup(group);
                      }
                      // Reload recent contacts to update the UI
                      _loadRecentContacts();
                    } else {
                      // Otherwise, add groups individually (normal mode)
                      for (final group in selectedGroups) {
                        _selectGroup(group);
                      }
                    }
                  },
                ),
              );
      
              // Handle result if returned via Get.back
              if (result != null && result is List<ContactGroup>) {
                // If we have a callback for replacing selection (filter mode), use it
                if (widget.onMultipleGroupsSelectedFromPicker != null) {
                  widget.onMultipleGroupsSelectedFromPicker!(result);
                  // Save each selected group to recents
                  for (final group in result) {
                    _saveRecentContactGroup(group);
                  }
                  // Reload recent contacts to update the UI
                  _loadRecentContacts();
                } else {
                  // Otherwise, add groups individually (normal mode)
                  for (final group in result) {
                    _selectGroup(group);
                  }
                }
              }
            },
            child: Container(
              height: widget.isInFilterMode ? 40 : null, // Fixed height only in filter mode
              padding: widget.isInFilterMode
                  ? const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 0) // No padding in filter mode - let Center handle it
                  : const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
              child: Center(
                child: Text(
                  'See List',
                  style: AppFonts.medium(18, color: uiController.currentMainColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Convert contact strings to ContactGroup objects
  Future<List<ContactGroup>> _convertContactStringsToGroups(List<String> contactStrings) async {
    final List<ContactGroup> groups = [];

    try {
      // Get all contact groups from the service
      final allGroups = await _contactGroupService.getAllGroupsHierarchical();

      for (final contactString in contactStrings) {
        // Find matching group in all groups (including subgroups)
        ContactGroup? matchedGroup = _findGroupByName(allGroups, contactString);

        if (matchedGroup != null) {
          groups.add(matchedGroup);
          debugPrint('[SearchableContactWidget] Matched contact group: ${matchedGroup.name}');
        } else {
          debugPrint('[SearchableContactWidget] Could not find contact group for: $contactString');
        }
      }
    } catch (e) {
      debugPrint('[SearchableContactWidget] Error converting contact strings: $e');
    }

    return groups;
  }

  /// Recursively find a contact group by name in the hierarchical structure
  ContactGroup? _findGroupByName(List<ContactGroup> groups, String name) {
    for (final group in groups) {
      if (group.name == name) {
        return group;
      }

      // Check subgroups
      if (group.subgroups != null) {
        final found = _findGroupByName(group.subgroups!, name);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }
}
