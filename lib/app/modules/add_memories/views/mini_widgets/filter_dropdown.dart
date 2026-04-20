import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../ui/controllers/ui_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

class FilterDropdown extends StatefulWidget {
  final String imagePath;
  final String hint;
  final List<String> items;
  final List<String> selectedItems;
  final Function(String) onItemSelected;
  final Function(String) onItemRemoved;

  const FilterDropdown({
    super.key,
    required this.imagePath,
    required this.hint,
    required this.items,
    required this.selectedItems,
    required this.onItemSelected,
    required this.onItemRemoved,
  });

  @override
  State<FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<FilterDropdown> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredItems = [];
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  @override
  void didUpdateWidget(FilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update filtered items if the items list changed
    if (oldWidget.items != widget.items) {
      _filteredItems = widget.items;
    }
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems =
            widget.items
                .where(
                  (item) => item.toLowerCase().contains(query.toLowerCase()),
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color:
                              uiController.darkMode.value
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.grey[600],
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

          // Selected items chips
          Builder(
            builder: (context) {
              final itemType =
                  widget.hint.contains('Hashtags') ? 'hashtags' : 'contacts';
              debugPrint(
                'FilterDropdown ($itemType): Building chips for ${widget.selectedItems.length} selected items: ${widget.selectedItems}',
              );

              if (widget.selectedItems.isEmpty) {
                return const SizedBox.shrink();
              }

              return Container(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children:
                      widget.selectedItems.map((item) {
                        return Chip(
                          label: Text(
                            widget.hint.contains('Hashtags')
                                ? '#$item'
                                : '@$item',
                            style: GoogleFonts.kumbhSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            debugPrint(
                              'Removing ${widget.hint.contains('Hashtags') ? 'hashtag' : 'contact'}: $item',
                            );
                            widget.onItemRemoved(item);
                          },
                          backgroundColor:
                              uiController.darkMode.value
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : uiController.currentMainColor.withValues(
                                    alpha: 0.1,
                                  ),
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
                        ? uiController.currentMainColor.withValues(alpha: 0.1)
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
                      style: GoogleFonts.kumbhSans(
                        color:
                            uiController.darkMode.value
                                ? Colors.white
                                : Colors.black,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w400,
                      ),

                      decoration: InputDecoration(
                        hintStyle: GoogleFonts.kumbhSans(
                          color:
                              uiController.darkMode.value
                                  ? Colors.white54
                                  : Colors.grey[600],
                          fontSize: 15.5,
                          fontWeight: FontWeight.w400,
                        ),
                        hintText: '${widget.hint}',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 4),
                          child: Icon(Icons.search, size: 18),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color:
                                uiController.darkMode.value
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.black,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color:
                                uiController.darkMode.value
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.black,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 8,
                        ),
                      ),
                      onChanged: _filterItems,
                    ),
                  ),

                  if (_filteredItems.length == 0)
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        trKey('text_no_widget_hint_replaceall', [
                          widget.hint.replaceAll(',', ''),
                        ]),
                        style: GoogleFonts.kumbhSans(
                          color:
                              uiController.darkMode.value
                                  ? Colors.white54
                                  : Colors.grey[600],
                          fontSize: 15.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),

                  // Items list
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final isSelected = widget.selectedItems.contains(item);

                        return ListTile(
                          dense: true,
                          title: Text(
                            widget.hint.contains('Hashtags')
                                ? '#$item'
                                : '@$item',
                            style: GoogleFonts.kumbhSans(
                              color:
                                  isSelected
                                      ? Colors.blue
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
                                    color: Colors.blue,
                                    size: 20,
                                  )
                                  : null,
                          onTap: () {
                            if (!isSelected) {
                              widget.onItemSelected(item);
                            }
                            setState(() {
                              _isExpanded = false;
                            });
                            _searchController.clear();
                            _filteredItems = widget.items;
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
