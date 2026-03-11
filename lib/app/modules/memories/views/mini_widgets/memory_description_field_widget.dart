import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../controllers/memory_controller.dart';
import 'mention_bottom_sheet_widget.dart';

/// Custom TextEditingController that colors hashtags and mentions
class ColoredTextEditingController extends TextEditingController {
  final List<String> validTags;
  final List<String> validMentions;
  final bool isDarkMode;

  ColoredTextEditingController({
    required this.validTags,
    required this.validMentions,
    required this.isDarkMode,
    String? text,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;

    if (text.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final defaultStyle = style ?? _getDefaultStyle();

    // Split by spaces to process word by word
    final words = text.split(' ');
    final spans = <TextSpan>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];

      if (word.startsWith('#')) {
        final tag = word.substring(1);
        final color = validTags.contains(tag) ? Colors.green : null;
        spans.add(
          TextSpan(
            text: word,
            style: color != null ? defaultStyle.copyWith(color: color) : defaultStyle,
          ),
        );
      } else if (word.startsWith('@')) {
        final mention = word.substring(1);
        final color = validMentions.contains(mention) ? Colors.blue : null;
        spans.add(
          TextSpan(
            text: word,
            style: color != null ? defaultStyle.copyWith(color: color) : defaultStyle,
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: word,
            style: defaultStyle,
          ),
        );
      }

      // Add space after each word except the last one
      if (i < words.length - 1) {
        spans.add(
          TextSpan(
            text: ' ',
            style: defaultStyle,
          ),
        );
      }
    }

    return TextSpan(children: spans, style: style);
  }

  TextStyle _getDefaultStyle() {
    return GoogleFonts.kumbhSans(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: isDarkMode ? Colors.white : Colors.black,
    );
  }
}

class MemoryDescriptionField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> existingTags;
  final List<String> existingMentions;
  final Function(String) onTagAdded;
  final Function(String) onMentionAdded;
  final Function(bool)? onPopupStateChanged;
  final ScrollController? scrollController; // Add scroll controller parameter

  const MemoryDescriptionField({
    super.key,
    required this.controller,
    required this.existingTags,
    required this.existingMentions,
    required this.onTagAdded,
    required this.onMentionAdded,
    this.onPopupStateChanged,
    this.scrollController,
  });

  @override
  State<MemoryDescriptionField> createState() => MemoryDescriptionFieldState();
}

class MemoryDescriptionFieldState extends State<MemoryDescriptionField> {
  final FocusNode _focusNode = FocusNode();
  bool _isPopupOpen = false;
  ValueNotifier<String>? _searchNotifier;
  int _savedCursorPosition = 0; // Store cursor position when popup opens
  bool _preventAutoFocus = false; // Prevent auto-focus after navigation

  final List<String> _tags = [];
  final List<String> _mentions = [];

  late ColoredTextEditingController _coloredController;

  List<String> getTags() => _tags;
  List<String> getMentions() => _mentions;

  /// Initialize tags from existing data (for edit mode)
  void initializeTags(List<String> tags) {
    _tags.clear();
    _tags.addAll(tags);
    setState(() {}); // Trigger rebuild to show colors
  }

  /// Initialize mentions from existing data (for edit mode)
  void initializeMentions(List<String> mentions) {
    _mentions.clear();
    _mentions.addAll(mentions);
    setState(() {}); // Trigger rebuild to show colors
  }

  void _onTagAdded(String tag) {
    _tags.add(tag);
    widget.onTagAdded(tag);
  }

  void _onMentionAdded(String mention) {
    _mentions.add(mention);
    widget.onMentionAdded(mention);
  }

  /// Clean up tags and mentions that are no longer present in the text
  void _cleanupRemovedItems() {
    final text = _coloredController.text;

    // Remove tags that are no longer in the text
    _tags.removeWhere((tag) => !text.contains('#$tag'));

    // Remove mentions that are no longer in the text
    _mentions.removeWhere((mention) => !text.contains('@$mention'));
  }

  bool get isPopupOpen => _isPopupOpen;

  void closePopup() {
    if (_isPopupOpen) {
      _forceRemovePopup();
    }
  }

  /// Prevent auto-focus temporarily (e.g., after navigation)
  void preventAutoFocusTemporarily() {
    _preventAutoFocus = true;
    // Reset after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _preventAutoFocus = false;
      }
    });
  }

  // iOS-compatible focus request method
  void _requestFocusWithDelay() {
    // Check if we're on iOS and handle accordingly
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // iOS-specific focus handling
      _handleIOSFocus();
    } else {
      // Android and other platforms
      _handleStandardFocus();
    }
  }

  void _handleIOSFocus() {
    // Method 1: Immediate focus request
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    // Method 2: Delayed FocusScope request for iOS
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && !_focusNode.hasFocus) {
        try {
          FocusScope.of(context).requestFocus(_focusNode);
        } catch (e) {
          debugPrint('iOS focus error: $e');
        }
      }
    });

    // Method 3: Force keyboard to appear using SystemChannels (iOS specific)
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && !_focusNode.hasFocus) {
        // Last resort: unfocus everything first, then focus
        FocusManager.instance.primaryFocus?.unfocus();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    });
  }

  void _handleStandardFocus() {
    // Standard focus handling for Android and other platforms
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    // Backup method
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && !_focusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  // Method to dismiss keyboard
  void _dismissKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
      FocusScope.of(context).unfocus();

      // For iOS, sometimes we need to be more aggressive
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        FocusManager.instance.primaryFocus?.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    }
  }

  @override
  void initState() {
    super.initState();

    print('Init State Called: for child');
    // Create colored controller with initial text from widget controller
    final uiController = Get.find<UiController>();
    _coloredController = ColoredTextEditingController(
      validTags: _tags,
      validMentions: _mentions,
      isDarkMode: uiController.darkMode.value,
      text: widget.controller.text,
    );

    // Sync colored controller changes to widget controller
    _coloredController.addListener(_onColoredControllerChanged);

    // Sync widget controller changes to colored controller (for external updates)
    widget.controller.addListener(_onWidgetControllerChanged);

    _focusNode.addListener(_onFocusChange);
  }

  void _onColoredControllerChanged() {
    // Sync to widget controller
    if (_coloredController.text != widget.controller.text) {
      widget.controller.value = _coloredController.value;
    }

    // Handle text changes for popup logic
    _onTextChanged();
  }

  void _onWidgetControllerChanged() {
    // Sync from widget controller to colored controller (for external updates)
    if (_coloredController.text != widget.controller.text) {
      _coloredController.value = widget.controller.value;
    }
  }

  double? _scrollOffsetBeforeFocus;

  void _onFocusChange() {

    print('Init State Called: for child');
    if (_focusNode.hasFocus) {
      // When field gains focus, save current position and scroll up by 100 points
      if (widget.scrollController != null && widget.scrollController!.hasClients) {
        _scrollOffsetBeforeFocus = widget.scrollController!.offset;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && widget.scrollController!.hasClients) {
            final currentOffset = widget.scrollController!.offset;
            final targetOffset = currentOffset + 150.0;
            widget.scrollController!.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } else {
      // When field loses focus, scroll back to original position
      if (widget.scrollController != null &&
          widget.scrollController!.hasClients &&
          _scrollOffsetBeforeFocus != null) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && widget.scrollController!.hasClients) {
            widget.scrollController!.animateTo(
              _scrollOffsetBeforeFocus!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
            _scrollOffsetBeforeFocus = null;
          }
        });
      }

      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_focusNode.hasFocus && mounted) {
          try {
            final controller = Get.find<TagMentionController>();
            // Only remove popup if it's not open OR if user is not editing
            // This keeps popup visible when keyboard is dismissed via Done button
            if (!controller.isEditing.value && !_isPopupOpen) {
              _removePopup();
            }
          } catch (_) {
            // Only remove popup if it's not currently open
            if (!_isPopupOpen) {
              _removePopup();
            }
          }
        }
      });
    }
  }

  void _onTextChanged() {
    // Clean up tags and mentions that are no longer in the text
    _cleanupRemovedItems();

    // Always rebuild the widget when text changes (even from external sources)
    if (mounted) {
      setState(() {});
    }

    if (!_focusNode.hasFocus) {
      _removePopup();
      return;
    }

    final text = _coloredController.text;
    final selection = _coloredController.selection;

    if (selection.baseOffset <= 0 || text.isEmpty) {
      _removePopup();
      return;
    }

    final cursorPos = selection.baseOffset;
    final triggerIndex = _getLastTriggerIndex(text, cursorPos);

    if (triggerIndex == -1 || triggerIndex >= cursorPos) {
      _removePopup();
      return;
    }

    // Check if there's a valid character before the trigger
    // Trigger should only work if preceded by space, newline, or at start of text
    if (triggerIndex > 0) {
      final charBeforeTrigger = text[triggerIndex - 1];
      if (charBeforeTrigger != ' ' && charBeforeTrigger != '\n') {
        // There's text directly before @ or # (like "hello#" or "hello@")
        // Treat it as normal text, don't show popup
        _removePopup();
        return;
      }
    }

    final triggerChar = text[triggerIndex];
    final keyword = text.substring(triggerIndex + 1, cursorPos);

    // Check if keyword contains space or newline
    if (keyword.contains(' ') || keyword.contains('\n')) {
      // Only show snackbar if popup is currently open (user is actively searching)
      // Don't show snackbar if popup is not open (space added after item selection)
      if (_isPopupOpen) {
        // Check if the last character typed was a space (user just typed it)
        final lastChar = cursorPos > 0 ? text[cursorPos - 1] : '';

        if (lastChar == ' ' || lastChar == '\n') {
          // Show snackbar and remove the space
          Get.snackbar(
            'Space Not Allowed',
            'Spaces are not allowed in ${triggerChar == '#' ? 'hashtags' : 'mentions'}',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
            snackPosition: SnackPosition.BOTTOM,
          );

          // Remove the space from the text field
          final newText = text.substring(0, cursorPos - 1) + text.substring(cursorPos);
          _coloredController.text = newText;
          _coloredController.selection = TextSelection.collapsed(
            offset: cursorPos - 1,
          );

          return;
        }
      }

      // Close popup (either space wasn't just typed, or popup wasn't open)
      _removePopup();
      return;
    }

    if (cursorPos == triggerIndex + 1) {
      if (triggerChar == '@') {
        _showMentionPopup('');
      } else if (triggerChar == '#') {
        _showTagPopup('');
      }
      return;
    }

    if (cursorPos > triggerIndex + 1) {
      final trimmedKeyword = keyword.trim();

      if (_isPopupOpen && _searchNotifier != null) {
        _searchNotifier!.value = trimmedKeyword;
        return;
      }

      if (triggerChar == '@') {
        _showMentionPopup(trimmedKeyword);
      } else if (triggerChar == '#') {
        _showTagPopup(trimmedKeyword);
      }
      return;
    }

    _removePopup();
  }

  int _getLastTriggerIndex(String text, int cursorPos) {
    final lastAt = text.lastIndexOf('@', cursorPos - 1);
    final lastHash = text.lastIndexOf('#', cursorPos - 1);
    return lastAt > lastHash ? lastAt : lastHash;
  }

  void _showTagPopup(String keyword) {
    // Prevent opening popup if already open
    if (_isPopupOpen) return;

    // Save current cursor position
    _savedCursorPosition = _coloredController.selection.baseOffset;

    _removePopup();

    _isPopupOpen = true;
    widget.onPopupStateChanged?.call(true);
    _searchNotifier = ValueNotifier<String>(keyword);

    // Check if we're editing an existing tag (case-insensitive)
    final String? oldTag = keyword.isNotEmpty
        ? _tags.firstWhereOrNull((tag) => tag.toLowerCase() == keyword.toLowerCase())
        : null;
    final bool isEditingExisting = oldTag != null;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Material(
              elevation: 8,
              color: Colors.transparent,
              child: TagMentionBottomSheet(
                onItemSelected: (item) {
                  // Remove old tag if we're replacing
                  if (oldTag != null) {
                    _tags.remove(oldTag);
                  }

                  _insertTextAtSavedCursor(item);
                  final clean = item.substring(1);
                  widget.onTagAdded(clean);
                  _tags.add(clean); // ✅ Add to tag list

                  // Always try to pop - if dialog is already closed, this will fail silently
                  try {
                    Navigator.of(context).pop();
                  } catch (e) {
                    // Dialog already closed (e.g., after "See list" navigation)
                  }
                  _onDialogClosed();

                  // Refocus the input field after a short delay
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      _focusNode.requestFocus();
                    }
                  });
                },
                isTagMode: true,
                initialKeyword: keyword,
                searchNotifier: _searchNotifier!,
                onEditingComplete: () {
                  Navigator.of(context).pop();
                  _removeIncompleteTextAndClosePopup();
                },
                onSeeListTapped: () {
                  // If initialKeyword is empty, remove text from trigger to cursor
                  if (keyword.isEmpty) {
                    _clearIncompleteText();
                  }
                  // Close popup without removing text
                  Navigator.of(context).pop();
                  // Don't call _onDialogClosed() here - let the .then() handler do it
                },
                excludedItems: _tags, // Pass already added tags
                isEditingExisting: isEditingExisting, // Pass editing state
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // Ensure cleanup happens when dialog is dismissed
      if (_isPopupOpen) {
        _onDialogClosed();
      }
    });
  }

  void _showMentionPopup(String keyword) {
    // Prevent opening popup if already open
    if (_isPopupOpen) return;

    // Save current cursor position
    _savedCursorPosition = _coloredController.selection.baseOffset;

    _removePopup();

    _isPopupOpen = true;
    widget.onPopupStateChanged?.call(true);
    _searchNotifier = ValueNotifier<String>(keyword);

    // Check if we're editing an existing mention (case-insensitive)
    final String? oldMention = keyword.isNotEmpty
        ? _mentions.firstWhereOrNull((mention) => mention.toLowerCase() == keyword.toLowerCase())
        : null;
    final bool isEditingExisting = oldMention != null;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Material(
              elevation: 8,
              color: Colors.transparent,
              child: TagMentionBottomSheet(
                onItemSelected: (item) {
                  // Remove old mention if we're replacing
                  if (oldMention != null) {
                    _mentions.remove(oldMention);
                  }

                  _insertTextAtSavedCursor(item);
                  final clean = item.substring(1);
                  widget.onMentionAdded(clean);
                  _mentions.add(clean); // ✅ Add to mention list

                  // Always try to pop - if dialog is already closed, this will fail silently
                  try {
                    Navigator.of(context).pop();
                  } catch (e) {
                    // Dialog already closed (e.g., after "See list" navigation)
                  }
                  _onDialogClosed();

                  // Refocus the input field after a short delay
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      _focusNode.requestFocus();
                    }
                  });
                },
                isTagMode: false,
                initialKeyword: keyword,
                searchNotifier: _searchNotifier!,
                onEditingComplete: () {
                  Navigator.of(context).pop();
                  _removeIncompleteTextAndClosePopup();
                },
                onSeeListTapped: () {
                  // If initialKeyword is empty, remove text from trigger to cursor
                  if (keyword.isEmpty) {
                    _clearIncompleteText();
                  }
                  // Close popup without removing text
                  Navigator.of(context).pop();
                  // Don't call _onDialogClosed() here - let the .then() handler do it
                },
                excludedItems: _mentions, // Pass already added mentions
                isEditingExisting: isEditingExisting, // Pass editing state
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // Ensure cleanup happens when dialog is dismissed
      if (_isPopupOpen) {
        _onDialogClosed();
      }
    });
  }

  void _onDialogClosed() {
    _isPopupOpen = false;
    widget.onPopupStateChanged?.call(false);
    _searchNotifier?.dispose();
    _searchNotifier = null;
    Get.delete<TagMentionController>();
  }

  void _removePopup() {
    // No longer needed with showDialog, but kept for compatibility
    if (_isPopupOpen) {
      try {
        final controller = Get.find<TagMentionController>();
        if (controller.isEditing.value) return;
      } catch (_) {}

      _onDialogClosed();
    }
  }

  void _forceRemovePopup() {
    // No longer needed with showDialog, but kept for compatibility
    _onDialogClosed();
  }

  void _removeIncompleteTextAndClosePopup() {
    // Clear the incomplete text from trigger character to cursor
    _clearIncompleteText();

    // Then close the popup
    _forceRemovePopup();

    // Refocus the input field
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _clearIncompleteText() {
    final currentText = _coloredController.text;
    final selection = _coloredController.selection;

    if (selection.baseOffset >= 0) {
      final triggerIndex = _getLastTriggerIndex(
        currentText,
        selection.baseOffset,
      );
      if (triggerIndex == -1) return;

      // Find the end of the current word (tag/mention) to remove the entire incomplete word
      int endIndex = selection.baseOffset;
      while (endIndex < currentText.length &&
             currentText[endIndex] != ' ' &&
             currentText[endIndex] != '\n') {
        endIndex++;
      }

      // Remove the incomplete text from trigger to end of word
      final newText = currentText.replaceRange(
        triggerIndex,
        endIndex,
        '',
      );

      _coloredController.text = newText;
      _coloredController.selection = TextSelection.collapsed(
        offset: triggerIndex,
      );
    }
  }

  void _insertTextAtCursor(String text) {
    final currentText = _coloredController.text;
    final selection = _coloredController.selection;

    if (selection.baseOffset >= 0) {
      final triggerIndex = _getLastTriggerIndex(
        currentText,
        selection.baseOffset,
      );
      if (triggerIndex == -1) return;

      // Find the end of the current word (tag/mention) to replace the entire word
      int endIndex = selection.baseOffset;
      while (endIndex < currentText.length &&
             currentText[endIndex] != ' ' &&
             currentText[endIndex] != '\n') {
        endIndex++;
      }

      final newText = currentText.replaceRange(
        triggerIndex,
        endIndex,
        '$text ',
      );

      _coloredController.text = newText;
      _coloredController.selection = TextSelection.collapsed(
        offset: triggerIndex + text.length + 1,
      );
    }
  }

  void _insertTextAtSavedCursor(String text) {
    final currentText = _coloredController.text;

    if (_savedCursorPosition >= 0) {
      final triggerIndex = _getLastTriggerIndex(
        currentText,
        _savedCursorPosition,
      );
      if (triggerIndex == -1) return;

      // Find the end of the current word (tag/mention) to replace the entire word
      int endIndex = _savedCursorPosition;
      while (endIndex < currentText.length &&
             currentText[endIndex] != ' ' &&
             currentText[endIndex] != '\n') {
        endIndex++;
      }

      final newText = currentText.replaceRange(
        triggerIndex,
        endIndex,
        '$text ',
      );

      _coloredController.text = newText;
      _coloredController.selection = TextSelection.collapsed(
        offset: triggerIndex + text.length + 1,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onWidgetControllerChanged);
    _coloredController.removeListener(_onColoredControllerChanged);
    _coloredController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return GestureDetector(
      onTap: () {
        // Only focus if not already focused and auto-focus is not prevented
        // This prevents auto-focus on rebuild after returning from pickers
        if (!_focusNode.hasFocus && !_preventAutoFocus) {
          _requestFocusWithDelay();
        }
      },
      // Prevent the outer GestureDetector from receiving this tap
      behavior: HitTestBehavior.opaque,
      child: Container(
          decoration: BoxDecoration(
            color:
                controller.darkMode.value
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.white,
            borderRadius: BorderRadius.circular(0),
          ),
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _coloredController,
            focusNode: _focusNode,
            maxLines: 50,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            autocorrect: true,
            enableSuggestions: true,
            showCursor: true,
            cursorColor: controller.primaryColor ?? Colors.blue,
            cursorWidth: 2.0,
            cursorHeight: 20.0,
            cursorRadius: const Radius.circular(1.0),
            onSubmitted: (_) {
              // Allow newline to be inserted
            },
            onChanged: (text) {
              setState(() {}); // Rebuild to update colors
              _onTextChanged();
            },
            onTap: () {
              // Additional focus handling for iOS
              if (!_focusNode.hasFocus && !_preventAutoFocus) {
                _requestFocusWithDelay();
              }
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: 'my memory... ',
              hintStyle: GoogleFonts.kumbhSans(
                fontWeight: FontWeight.w500,
                color: controller.darkMode.value ? Colors.white : Colors.grey,
                fontSize: 16,
              ),
            ),
            style: GoogleFonts.kumbhSans(
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: controller.darkMode.value ? Colors.white : Colors.black,
            ),
          ), // TextField
        ), // Container
      // ), // GestureDetector
    );
  }
}
