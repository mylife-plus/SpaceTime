import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Popup dialog for adding or editing hashtag/contact groups and subgroups
class AddEditGroupPopup extends StatefulWidget {
  final bool isHashtagMode; // true for hashtags, false for contacts
  final String? initialName; // For editing or pre-filled name
  final int? editItemId; // If editing, the ID of the item
  final int? parentId; // For subgroups, the parent group ID
  final String? parentGroupName; // For subgroups, the parent group name
  final bool isMainGroup; // true for main groups, false for subgroups
  final Function(String name, int? parentId)? onSave; // Callback when saved
  final VoidCallback? onCancel; // Callback when cancelled

  const AddEditGroupPopup({
    super.key,
    required this.isHashtagMode,
    this.initialName,
    this.editItemId,
    this.parentId,
    this.parentGroupName,
    this.isMainGroup = false,
    this.onSave,
    this.onCancel,
  });

  @override
  State<AddEditGroupPopup> createState() => _AddEditGroupPopupState();
}

class _AddEditGroupPopupState extends State<AddEditGroupPopup> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    
    // Auto-focus name field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
      // Position cursor at the end
      _nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _nameController.text.length),
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _handleSave() {
    final name = _nameController.text.trim();
    
    if (name.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter a name',
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    widget.onSave?.call(name, widget.parentId);
    Navigator.of(context).pop();
  }

  void _handleCancel() {
    widget.onCancel?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();
    final prefixChar = widget.isHashtagMode ? '#' : '@';
    
    String title;
    if (widget.editItemId != null) {
      // Editing mode
      title = widget.isMainGroup
          ? '$prefixChar Edit ${widget.isHashtagMode ? 'Hashtag' : 'Contact'} Group'
          : '$prefixChar Edit ${widget.isHashtagMode ? 'Hashtag' : 'Contact'}';
    } else {
      // Adding mode
      title = widget.isMainGroup
          ? '$prefixChar New ${widget.isHashtagMode ? 'Hashtag' : 'Contact'} Group'
          : '$prefixChar New ${widget.isHashtagMode ? 'Hashtag' : 'Contact'}';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close and check buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close button
                GestureDetector(
                  onTap: _handleCancel,
                  child: const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 28,
                  ),
                ),
                // Title
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value ? Colors.white : Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Show parent group name when adding/editing a subgroup
                   
                  ],
                ),
                
                // Check button
                GestureDetector(
                  onTap: _handleSave,
                  child: const Icon(
                    Icons.check,
                    color: Colors.green,
                    size: 28,
                  ),
                ),
              ],
            ),
             if (!widget.isMainGroup && widget.parentGroupName != null)

                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4, right: 12),
                            child: Text(
                              '📁 ${widget.parentGroupName}',
                              style: GoogleFonts.kumbhSans(
                                color: uiController.darkMode.value ? Colors.white : Colors.black,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),

            const SizedBox(height: 8),

            // Name label
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  widget.isMainGroup
                      ? '${widget.isHashtagMode ? 'Hashtag' : 'Contact'} Group'
                      : widget.isHashtagMode ? 'Hashtag Name' : 'Contact Name',
                  style: GoogleFonts.kumbhSans(
                    fontSize: 15,
                    color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ),
            ),

            // Name input field
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextSelectionTheme(
                data: TextSelectionThemeData(
                  cursorColor: uiController.currentMainColor,
                  selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                  selectionHandleColor: uiController.currentMainColor,
                ),
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')), // Deny all whitespace
                  ],
                  style: GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.isMainGroup
                        ? '${widget.isHashtagMode ? 'Hashtag' : 'Contact'} Group Name'
                        : '${widget.isHashtagMode ? 'Hashtag' : 'Contact'} Name',
                    hintStyle: GoogleFonts.kumbhSans(
                      color: Colors.grey.shade400,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSave(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

