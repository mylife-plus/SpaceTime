import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/models/hashtag_group_model.dart';
import 'package:spacetime/app/services/hashtag_group_service.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/hashtag_groups/views/hashtag_groups_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SearchableHashtagWidget extends StatefulWidget {
  final String title;
  final Function(String) onHashtagSelected;
  final Function(HashtagGroup)? onGroupSelected;
  final Function(bool isFocused)? onFocusChanged;
  final bool showActionButtons;
  final String? iconPath;
  final Color? backgroundColor;
  final bool isCompact;

  /// Previously selected hashtags to pass to the picker (for filter mode)
  final List<String>? previouslySelectedHashtags;

  /// Callback when multiple hashtag groups are selected from the picker (for filter mode)
  /// This is called when user returns from the picker with a new selection
  final Function(List<HashtagGroup> groups)? onMultipleGroupsSelectedFromPicker;

  /// Whether this widget is being used inside a filter overlay (affects padding)
  final bool isInFilterMode;

  /// Border radius for the container (optional)
  final double? borderRadius;

  const SearchableHashtagWidget({
    super.key,
    this.title = 'Search Hashtags',
    required this.onHashtagSelected,
    this.onGroupSelected,
    this.onMultipleGroupsSelectedFromPicker,
    this.onFocusChanged,
    this.showActionButtons = false,
    this.iconPath,
    this.backgroundColor,
    this.isCompact = false,
    this.previouslySelectedHashtags,
    this.isInFilterMode = false,
    this.borderRadius,
  });

  @override
  State<SearchableHashtagWidget> createState() => _SearchableHashtagWidgetState();

  /// Remove deleted hashtag from recent hashtags
  static Future<void> removeFromRecentHashtags(String hashtagName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentHashtagsJson = prefs.getStringList('recent_hashtags_filter') ?? [];

      // Remove the deleted hashtag from recent list
      final originalLength = recentHashtagsJson.length;
      recentHashtagsJson.removeWhere((item) {
        try {
          final data = json.decode(item);
          return data['name'] == hashtagName;
        } catch (e) {
          return false;
        }
      });

      if (recentHashtagsJson.length != originalLength) {
        await prefs.setStringList('recent_hashtags_filter', recentHashtagsJson);
        debugPrint('[SearchableHashtagWidget] Removed hashtag "$hashtagName" from recent hashtags');
      }
    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error removing hashtag from recent: $e');
    }
  }

  /// Remove deleted hashtag group from recent hashtag groups
  static Future<void> removeFromRecentHashtagGroups(int groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_hashtag_groups_filter') ?? [];

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
        await prefs.setStringList('recent_hashtag_groups_filter', recentGroupsJson);
        debugPrint('[SearchableHashtagWidget] Removed group ID $groupId from recent hashtag groups');
      }
    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error removing group from recent: $e');
    }
  }

  /// Remove hashtag group and all its subgroups from recent hashtag groups
  static Future<void> removeGroupAndSubgroupsFromRecentHashtagGroups(int mainGroupId, List<int> subgroupIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_hashtag_groups_filter') ?? [];

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
        await prefs.setStringList('recent_hashtag_groups_filter', recentGroupsJson);
        debugPrint('[SearchableHashtagWidget] Removed main group ID $mainGroupId and ${subgroupIds.length} subgroups from recent hashtag groups');
      }
    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error removing group and subgroups from recent: $e');
    }
  }

  /// Update hashtag group name in recent hashtag groups
  static Future<void> updateHashtagGroupInRecents(int groupId, String newName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_hashtag_groups_filter') ?? [];

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
        await prefs.setStringList('recent_hashtag_groups_filter', updatedList);
        debugPrint('[SearchableHashtagWidget] Updated hashtag group ID $groupId to "$newName" in recent hashtag groups');
      }
    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error updating hashtag group in recents: $e');
    }
  }
}

class _SearchableHashtagWidgetState extends State<SearchableHashtagWidget> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final HashtagGroupService _hashtagGroupService = HashtagGroupService();
  
  final RxBool _showResults = false.obs;
  final RxList<String> _searchResults = <String>[].obs;
  final RxList<HashtagGroup> _groupResults = <HashtagGroup>[].obs;
  final RxList<String> _recentHashtags = <String>[].obs;
  final RxList<String> _recentHashtagGroups = <String>[].obs; // Track which recent items are groups
  final RxBool _isLoading = false.obs;

  List<String> _allHashtags = [];
  List<HashtagGroup> _allGroups = [];

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
      debugPrint('[SearchableHashtagWidget] Collapsed due to focus loss');
    }
    widget.onFocusChanged?.call(isFocused);
    debugPrint('[SearchableHashtagWidget] Focus changed: $isFocused');
  }

  Future<void> _loadData() async {
    _isLoading.value = true;
    try {
      // Load hashtag groups
      _allGroups = await _hashtagGroupService.getAllGroupsHierarchical();

      // Load actual hashtags from AddMemoriesController if available
      try {
        final controller = Get.find<AddMemoriesController>();
        _allHashtags = List.from(controller.getAvailableHashtags);
      } catch (e) {
        debugPrint('[SearchableHashtagWidget] AddMemoriesController not found, using group names: $e');
        // Fallback: Extract hashtag names from groups (both main groups and subgroups)
        _allHashtags = [];
        for (final group in _allGroups) {
          _allHashtags.add(group.name);
          if (group.subgroups != null) {
            for (final subgroup in group.subgroups!) {
              _allHashtags.add(subgroup.name);
            }
          }
        }
      }

      // Load recent hashtags from SharedPreferences
      await _loadRecentHashtags();

    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error loading data: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> _loadRecentHashtags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentHashtagsJson = prefs.getStringList('recent_hashtags_filter') ?? [];

      // Load recent hashtags (individual hashtags)
      final recentHashtags = <String>[];
      for (final hashtagJson in recentHashtagsJson) {
        try {
          final hashtagData = json.decode(hashtagJson);
          if (hashtagData is Map<String, dynamic> && hashtagData.containsKey('name')) {
            recentHashtags.add(hashtagData['name']);
          }
        } catch (e) {
          debugPrint('[SearchableHashtagWidget] Error parsing recent hashtag: $e');
        }
      }

      // Load recent hashtag groups
      final recentGroupsJson = prefs.getStringList('recent_hashtag_groups_filter') ?? [];
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
          debugPrint('[SearchableHashtagWidget] Error parsing recent hashtag group: $e');
        }
      }

      // Combine recent hashtags and groups, prioritizing groups (max 6 items total)
      final combinedRecent = <String>[];
      final groupNames = <String>[];

      combinedRecent.addAll(recentGroups.take(6)); // Max 6 groups
      groupNames.addAll(mainCategoryGroups.take(6)); // Track which are MAIN CATEGORY groups (not subcategories)

      if (combinedRecent.length < 6) {
        combinedRecent.addAll(recentHashtags.take(6 - combinedRecent.length)); // Fill remaining with hashtags
      }

      _recentHashtags.value = combinedRecent;
      _recentHashtagGroups.value = groupNames; // Store which items are main category groups
      debugPrint('[SearchableHashtagWidget] Loaded ${combinedRecent.length} recent items (${groupNames.length} main category groups)');

    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error loading recent hashtags: $e');
      _recentHashtags.value = [];
      _recentHashtagGroups.value = [];
    }
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      _searchResults.clear();
      _groupResults.clear();
      return;
    }

    final lowerQuery = query.toLowerCase();
    
    // Search individual hashtags
    final hashtagResults = _allHashtags
        .where((hashtag) => hashtag.toLowerCase().contains(lowerQuery))
        .take(10)
        .toList();
    
    // Search groups (both main groups and subgroups)
    final groupResults = <HashtagGroup>[];
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
    
    _searchResults.value = hashtagResults;
    _groupResults.value = groupResults.take(5).toList();
  }

  Future<void> _selectHashtag(String hashtag, bool isGroup) async {
    if(!isGroup) {
      widget.onHashtagSelected(hashtag);
      _saveRecentHashtag(hashtag);
    } else {
      // Find the HashtagGroup object from _allGroups or fetch from database
      HashtagGroup? group = _allGroups.firstWhereOrNull((g) => g.name == hashtag);

      // If not found in _allGroups, fetch from database
      if (group == null) {
        final allGroups = await _hashtagGroupService.getAllGroupsHierarchical();
        group = allGroups.firstWhereOrNull((g) => g.name == hashtag);
      }

      if (group != null) {
        // Check if this is a main group or a subgroup
        if (group.isMainGroup && widget.onGroupSelected != null) {
          // Main group: fetch subgroups and call onGroupSelected
          if (group.id != null) {
            final subgroups = await _hashtagGroupService.getSubgroups(group.id!);
            // Update group with subgroups loaded
            group = group.copyWith(subgroups: subgroups);
          }
          widget.onGroupSelected!(group);
          _saveRecentHashtagGroup(group);
        } else {
          // Subgroup: treat as individual hashtag
          widget.onHashtagSelected(hashtag);
          _saveRecentHashtag(hashtag);
        }
      }
    }
    _searchController.clear();
    _showResults.value = false;
    _focusNode.unfocus();
  }

  void _selectGroup(HashtagGroup group) async {
    if (widget.onGroupSelected != null) {
      // If this is a main group, fetch subgroups to implement remove-before-add logic
      if (group.isMainGroup && group.id != null) {
        final subgroups = await _hashtagGroupService.getSubgroups(group.id!);
        // Update group with subgroups loaded
        group = group.copyWith(subgroups: subgroups);
      }
      widget.onGroupSelected!(group);
    }
    _saveRecentHashtagGroup(group);
    _searchController.clear();
    _showResults.value = false;
    _focusNode.unfocus();
  }

  Future<void> _saveRecentHashtag(String hashtag) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentHashtagsJson = prefs.getStringList('recent_hashtags_filter') ?? [];

      // Create hashtag data
      final hashtagData = {
        'name': hashtag,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Remove if already exists
      recentHashtagsJson.removeWhere((item) {
        try {
          final data = json.decode(item);
          return data['name'] == hashtag;
        } catch (e) {
          return false;
        }
      });

      // Add to beginning
      recentHashtagsJson.insert(0, json.encode(hashtagData));

      // Keep only last 10 items
      if (recentHashtagsJson.length > 10) {
        recentHashtagsJson.removeRange(10, recentHashtagsJson.length);
      }

      await prefs.setStringList('recent_hashtags_filter', recentHashtagsJson);
      debugPrint('[SearchableHashtagWidget] Saved recent hashtag: $hashtag');

    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error saving recent hashtag: $e');
    }
  }

  Future<void> _saveRecentHashtagGroup(HashtagGroup group) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentGroupsJson = prefs.getStringList('recent_hashtag_groups_filter') ?? [];

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

      await prefs.setStringList('recent_hashtag_groups_filter', recentGroupsJson);
      debugPrint('[SearchableHashtagWidget] Saved recent hashtag group: ${group.name}');

    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error saving recent hashtag group: $e');
    }
  }

  Widget _buildSearchField(UiController uiController) {
    return SizedBox(
      height: 20, // Fixed height to match icon height
      child: Obx(() => TextField(
      controller: _searchController,
      focusNode: _focusNode,
      style: AppFonts.medium(16, color: uiController.darkMode.value ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: widget.title,
        hintStyle: AppFonts.regular(16, color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 2), // Center text with 20px icon
        suffixIcon: (widget.isInFilterMode && _showResults.value) || _searchController.text.isNotEmpty ? GestureDetector(
          onTap: () {
            _searchController.clear();
            _showResults.value = false;
            _focusNode.unfocus();
          },
          child: Icon(
            Icons.clear,
            size: 18,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
          ),
        ) : null,
      ),
      onChanged: _performSearch,
    )),
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
        borderRadius: widget.borderRadius != null
            ? BorderRadius.circular(widget.borderRadius!)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                widget.iconPath ?? AppImages.tag,
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
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxHeight: widget.isInFilterMode ? 225 : 300),
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
    final hasRecent = _recentHashtags.isNotEmpty;

    final allItems = <Widget>[];

    if (hasSearchQuery && !hasResults) {
      // Show "No hashtags found" message
      allItems.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: const Text(
          'No hashtags found',
          style: TextStyle(color: Colors.grey),
        ),
      ));
    } else if (!hasSearchQuery && !hasRecent) {
      // Show "No recent hashtags" message
      allItems.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Text(
          'No recent hashtags',
          style: AppFonts.medium(
            14,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
        ),
      ));
    } else {
      // Add search results or recent hashtags
      if (hasSearchQuery) {
        // Group results
        for (int i = 0; i < _groupResults.length; i++) {
          allItems.add(_buildGroupItem(_groupResults[i], uiController));
          if (i < _groupResults.length - 1 || _searchResults.isNotEmpty) {
            allItems.add(Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)));
          }
        }
        // Individual hashtag results
        for (int i = 0; i < _searchResults.length; i++) {
          allItems.add(_buildHashtagItem(_searchResults[i], uiController));
          if (i < _searchResults.length - 1) {
            allItems.add(Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)));
          }
        }
      } else {
        // Recent hashtags
        for (int i = 0; i < _recentHashtags.length; i++) {
          allItems.add(_buildHashtagItem(_recentHashtags[i], uiController));
          if (i < _recentHashtags.length - 1) {
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

  Widget _buildHashtagItem(String hashtag, UiController uiController) {
    // Check if this item is a group (exists in _recentHashtagGroups)
    final isGroup = _recentHashtagGroups.contains(hashtag);

    return InkWell(
      onTap: () => 
      
      
      _selectHashtag(hashtag, isGroup),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
                          if(isGroup)

             Icon(
                Icons.folder_outlined,
                size: 16,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
              ),
              if(!isGroup)
            Text(
              '#',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: uiController.darkMode.value ? Colors.white : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hashtag,
                style: AppFonts.medium(18, color: uiController.darkMode.value ? Colors.white : Colors.black87),
              ),
            ),
            // Show folder icon for groups
           
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItem(HashtagGroup group, UiController uiController) {
    // Check if this is a main category (parentId is null)
    final isMainCategory = group.parentId == null;

    return InkWell(
      onTap: () => _selectGroup(group),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              '#',
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
    return Column(
      children: [
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)),
        InkWell(
          onTap: () async {
            // Convert previously selected hashtag strings to HashtagGroup objects
            List<HashtagGroup>? previouslySelected;
            if (widget.previouslySelectedHashtags != null && widget.previouslySelectedHashtags!.isNotEmpty) {
              previouslySelected = await _convertHashtagStringsToGroups(widget.previouslySelectedHashtags!);
              debugPrint('[SearchableHashtagWidget] Passing ${previouslySelected.length} previously selected hashtag groups to picker');
            }

            // Navigate to Hashtag Groups page in multiple selection mode
            final result = await Get.to(
              () => HashtagGroupsView(
                allowMultipleSelection: true,
                selectedHashtagGroups: previouslySelected,
                onMultipleHashtagGroupsSelected: (selectedGroups) {
                  // If we have a callback for replacing selection (filter mode), use it
                  if (widget.onMultipleGroupsSelectedFromPicker != null) {
                    widget.onMultipleGroupsSelectedFromPicker!(selectedGroups);
                    // Save each selected group to recents
                    for (final group in selectedGroups) {
                      _saveRecentHashtagGroup(group);
                    }
                    // Reload recent hashtags to update the UI
                    _loadRecentHashtags();
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
            if (result != null && result is List<HashtagGroup>) {
              // If we have a callback for replacing selection (filter mode), use it
              if (widget.onMultipleGroupsSelectedFromPicker != null) {
                widget.onMultipleGroupsSelectedFromPicker!(result);
                // Save each selected group to recents
                for (final group in result) {
                  _saveRecentHashtagGroup(group);
                }
                // Reload recent hashtags to update the UI
                _loadRecentHashtags();
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
                ?  const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 0)
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
    );
  }

  /// Convert hashtag strings to HashtagGroup objects
  Future<List<HashtagGroup>> _convertHashtagStringsToGroups(List<String> hashtagStrings) async {
    final List<HashtagGroup> groups = [];

    try {
      // Get all hashtag groups from the service
      final allGroups = await _hashtagGroupService.getAllGroupsHierarchical();

      for (final hashtagString in hashtagStrings) {
        // Find matching group in all groups (including subgroups)
        HashtagGroup? matchedGroup = _findGroupByName(allGroups, hashtagString);

        if (matchedGroup != null) {
          groups.add(matchedGroup);
          debugPrint('[SearchableHashtagWidget] Matched hashtag group: ${matchedGroup.name}');
        } else {
          debugPrint('[SearchableHashtagWidget] Could not find hashtag group for: $hashtagString');
        }
      }
    } catch (e) {
      debugPrint('[SearchableHashtagWidget] Error converting hashtag strings: $e');
    }

    return groups;
  }

  /// Recursively find a hashtag group by name in the hierarchical structure
  HashtagGroup? _findGroupByName(List<HashtagGroup> groups, String name) {
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
