import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../ui/controllers/ui_controller.dart';

class CategoryFilterDropdown extends StatefulWidget {
  final String imagePath;
  final String hint;
  final List<String> categories;
  final List<String> selectedCategories;
  final Function(String) onCategorySelected;
  final Function(String) onCategoryRemoved;

  const CategoryFilterDropdown({
    super.key,
    required this.imagePath,
    required this.hint,
    required this.categories,
    required this.selectedCategories,
    required this.onCategorySelected,
    required this.onCategoryRemoved,
  });

  @override
  State<CategoryFilterDropdown> createState() => _CategoryFilterDropdownState();
}

class _CategoryFilterDropdownState extends State<CategoryFilterDropdown> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredCategories = [];
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _filteredCategories = widget.categories;
  }

  @override
  void didUpdateWidget(CategoryFilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update filtered categories if the categories list changed
    if (oldWidget.categories != widget.categories) {
      _filteredCategories = widget.categories;
    }
  }

  void _filterCategories(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCategories = widget.categories;
      } else {
        _filteredCategories =
            widget.categories
                .where(
                  (category) =>
                      category.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main dropdown field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  uiController.darkMode.value
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.white,
            ),
            child: Row(
              children: [
                Image.asset(
                  widget.imagePath,
                  width: 18,
                  height: 18,
                  color:
                      uiController.darkMode.value ? Colors.white : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        widget.hint,
                        style: GoogleFonts.kumbhSans(
                          color:
                              uiController.darkMode.value
                                  ? Colors.white70
                                  : Colors.grey[600],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color:
                      uiController.darkMode.value ? Colors.white : Colors.grey,
                ),
              ],
            ),
          ),

          // Selected categories chips
          Builder(
            builder: (context) {
              debugPrint(
                'CategoryFilterDropdown: Building chips for ${widget.selectedCategories.length} selected categories: ${widget.selectedCategories}',
              );

              if (widget.selectedCategories.isEmpty) {
                return const SizedBox.shrink();
              }

              return Container(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children:
                      widget.selectedCategories.map((category) {
                        return Chip(
                          label: Text(
                            category,
                            style: GoogleFonts.kumbhSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            debugPrint('Removing category: $category');
                            widget.onCategoryRemoved(category);
                          },
                          backgroundColor:
                              uiController.darkMode.value
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.green.withValues(alpha: 0.1),
                        );
                      }).toList(),
                ),
              );
            },
          ),

          // Dropdown content
          if (_isExpanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color:
                    uiController.darkMode.value
                        ? Colors.grey[800]
                        : Colors.white,
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search Place Categories...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: _filterCategories,
                    ),
                  ),

                  // Categories list
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredCategories.length,
                      itemBuilder: (context, index) {
                        final category = _filteredCategories[index];
                        final isSelected = widget.selectedCategories.contains(
                          category,
                        );

                        return ListTile(
                          dense: true,
                          title: Text(
                            category,
                            style: GoogleFonts.kumbhSans(
                              color:
                                  isSelected
                                      ? Colors.green
                                      : (uiController.darkMode.value
                                          ? Colors.white
                                          : Colors.black),
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w400,
                            ),
                          ),
                          trailing:
                              isSelected
                                  ? const Icon(
                                    Icons.check,
                                    color: Colors.green,
                                    size: 20,
                                  )
                                  : null,
                          onTap: () {
                            if (!isSelected) {
                              widget.onCategorySelected(category);
                            }
                            setState(() {
                              _isExpanded = false;
                            });
                            _searchController.clear();
                            _filteredCategories = widget.categories;
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
