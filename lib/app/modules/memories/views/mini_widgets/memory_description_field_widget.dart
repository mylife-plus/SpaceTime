import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mention_tag_text_field/mention_tag_text_field.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../controllers/memory_controller.dart';
import 'mention_bottom_sheet_widget.dart';

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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isPopupOpen = false;
  ValueNotifier<String>? _searchNotifier;
  TagMentionController? _currentController;

  late MentionTagTextEditingController _mentionController;

  final List<String> _tags = [];
  final List<String> _mentions = [];

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
    final text = widget.controller.text;

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
    _mentionController = MentionTagTextEditingController();
    // Sync initial text from widget.controller to _mentionController
    if (widget.controller.text.isNotEmpty) {
      _mentionController.setText = widget.controller.text;
    }
    // Listen to _mentionController changes and sync to widget.controller
    _mentionController.addListener(() {
      if (widget.controller.text != _mentionController.text) {
        widget.controller.text = _mentionController.text;
      }
    });
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChange);
  }

  double? _scrollOffsetBeforeFocus;

  void _onFocusChange() {
    // if (_focusNode.hasFocus) {
    //   // When field gains focus, save current position and scroll up by 100 points
    //   if (widget.scrollController != null && widget.scrollController!.hasClients) {
    //     _scrollOffsetBeforeFocus = widget.scrollController!.offset;
    //     Future.delayed(const Duration(milliseconds: 300), () {
    //       if (mounted && widget.scrollController!.hasClients) {
    //         final currentOffset = widget.scrollController!.offset;
    //         final targetOffset = currentOffset + 150.0;
    //         widget.scrollController!.animateTo(
    //           targetOffset,
    //           duration: const Duration(milliseconds: 300),
    //           curve: Curves.easeOut,
    //         );
    //       }
    //     });
    //   }
    // } else {
    //   // When field loses focus, scroll back to original position
    //   if (widget.scrollController != null &&
    //       widget.scrollController!.hasClients &&
    //       _scrollOffsetBeforeFocus != null) {
    //     Future.delayed(const Duration(milliseconds: 100), () {
    //       if (mounted && widget.scrollController!.hasClients) {
    //         widget.scrollController!.animateTo(
    //           _scrollOffsetBeforeFocus!,
    //           duration: const Duration(milliseconds: 300),
    //           curve: Curves.easeOut,
    //         );
    //         _scrollOffsetBeforeFocus = null;
    //       }
    //     });
    //   }

    //   Future.delayed(const Duration(milliseconds: 100), () {
    //     if (!_focusNode.hasFocus && mounted) {
    //       try {
    //         final controller = Get.find<TagMentionController>();
    //         if (!controller.isEditing.value) {
    //           _removePopup();
    //         }
    //       } catch (_) {
    //         _removePopup();
    //       }
    //     }
    //   });
    // }
  }

  void _onTextChanged() {
    // Clean up tags and mentions that are no longer in the text
    _cleanupRemovedItems();

    // // Always rebuild the widget when text changes (even from external sources)
    if (mounted) {
      setState(() {});
    }

    // debugPrint('[_onTextChanged] Text: "${widget.controller.text}"');
    // debugPrint('[_onTextChanged] Cursor position: ${widget.controller.selection.baseOffset}');

    if (!_focusNode.hasFocus) {
      _removePopup();
      return;
    }

    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (selection.baseOffset <= 0 || text.isEmpty) {
      _removePopup();
      return;
    }

    final cursorPos = selection.baseOffset;
    final triggerIndex = _getLastTriggerIndex(text, cursorPos);

    debugPrint('[_onTextChanged] Trigger index: $triggerIndex, Cursor pos: $cursorPos');

    if (triggerIndex == -1 || triggerIndex >= cursorPos) {
      _removePopup();
      return;
    }

    final triggerChar = text[triggerIndex];
    final keyword = text.substring(triggerIndex + 1, cursorPos);

    if (keyword.contains(' ') || keyword.contains('\n')) {
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
    _removePopup();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    _isPopupOpen = true;
    widget.onPopupStateChanged?.call(true);
    _searchNotifier = ValueNotifier<String>(keyword);

    final position = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = screenHeight * 0.4;
    final topOffset = position.dy - popupHeight - 10;

    // Check if we're editing an existing tag (case-insensitive)
    final String? oldTag = keyword.isNotEmpty
        ? _tags.firstWhereOrNull((tag) => tag.toLowerCase() == keyword.toLowerCase())
        : null;
    final bool isEditingExisting = oldTag != null;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => Stack(
            children: [
              // Barrier to prevent closing when tapped outside
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // Do nothing - prevents closing on outside tap
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              // Popup content
              Positioned(
                left: 20,
                right: 20,
                top: 100,
                child: Material(
                  elevation: 8,
                  color: Colors.transparent,
                  child: TagMentionBottomSheet(
                    onEditingCancelled: _removeIncompleteTextAndClosePopup,
                onItemSelected: (item) {
                  // Remove old tag if we're replacing
                  if (oldTag != null) {
                    _tags.remove(oldTag);
                  }

                  _insertTextAtCursor(item);
                  final clean = item.substring(1);
                  widget.onTagAdded(clean);
                  _tags.add(clean); // ✅ Add to tag list
                  _forceRemovePopup();
                },
                isTagMode: true,
                initialKeyword: keyword,
                searchNotifier: _searchNotifier!,
                onEditingComplete: _removeIncompleteTextAndClosePopup,
                excludedItems: _tags, // Pass already added tags
                isEditingExisting: isEditingExisting, // Pass editing state
                  ),
                ),
              ),
            ],
          ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _showMentionPopup(String keyword) {
    _removePopup();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    _isPopupOpen = true;
    widget.onPopupStateChanged?.call(true);
    _searchNotifier = ValueNotifier<String>(keyword);

    final position = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = screenHeight * 0.4;
    final topOffset = position.dy - popupHeight - 10;

    // Check if we're editing an existing mention (case-insensitive)
    final String? oldMention = keyword.isNotEmpty
        ? _mentions.firstWhereOrNull((mention) => mention.toLowerCase() == keyword.toLowerCase())
        : null;
    final bool isEditingExisting = oldMention != null;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => Stack(
            children: [
              // Barrier to prevent closing when tapped outside
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // Do nothing - prevents closing on outside tap
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              // Popup content
              Positioned(
                left: 20,
                right: 20,
                top: 100,
                child: Material(
                  elevation: 8,
                  color: Colors.transparent,
                  child: TagMentionBottomSheet(
                onItemSelected: (item) {
                  // Remove old mention if we're replacing
                  if (oldMention != null) {
                    _mentions.remove(oldMention);
                  }

                  _insertTextAtCursor(item);
                  final clean = item.substring(1);
                  widget.onMentionAdded(clean);
                  _mentions.add(clean); // ✅ Add to mention list
                  _forceRemovePopup();
                },
                isTagMode: false,
                initialKeyword: keyword,
                searchNotifier: _searchNotifier!,
                onEditingComplete: _removeIncompleteTextAndClosePopup,
                onEditingCancelled: _removeIncompleteTextAndClosePopup,
                excludedItems: _mentions, // Pass already added mentions
                isEditingExisting: isEditingExisting, // Pass editing state
                  ),
                ),
              ),
            ],
          ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removePopup() {
    if (_overlayEntry != null) {
      try {
        final controller = Get.find<TagMentionController>();
        if (controller.isEditing.value) return;
      } catch (_) {}

      _forceRemovePopup();
    }
  }

  void _forceRemovePopup() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isPopupOpen = false;
    widget.onPopupStateChanged?.call(false);
    _searchNotifier?.dispose();
    _searchNotifier = null;
    _currentController = null;
    Get.delete<TagMentionController>();

    // Close the keyboard when bottom sheet is closed
    // FocusScope.of(context).unfocus();
  }

  void _closePopup() {
    _removePopup();
  }

  void _removeIncompleteTextAndClosePopup() {
    // Get current cursor position and remove text until last @ or #
    final text = _mentionController.text;
    final cursorPos = _mentionController.selection.baseOffset;
    final triggerIndex = _getLastTriggerIndex(text, cursorPos);

    if (triggerIndex != -1) {
      // Remove from trigger character to cursor position
      final newText = text.substring(0, triggerIndex) + text.substring(cursorPos);
      _mentionController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: triggerIndex),
      );
      // Sync to widget.controller
      widget.controller.text = newText;
    }

    _forceRemovePopup();
  }

  void _insertTextAtCursor(String text) {
    final currentText = _mentionController.text;
    final selection = _mentionController.selection;

    debugPrint('[_insertTextAtCursor] ===== START =====');
    debugPrint('[_insertTextAtCursor] Text to insert: "$text"');
    debugPrint('[_insertTextAtCursor] Current text: "$currentText"');
    debugPrint('[_insertTextAtCursor] Current cursor position: ${selection.baseOffset}');

    if (selection.baseOffset >= 0) {
      final triggerIndex = _getLastTriggerIndex(
        currentText,
        selection.baseOffset,
      );
      debugPrint('[_insertTextAtCursor] Trigger index: $triggerIndex');

      if (triggerIndex == -1) {
        debugPrint('[_insertTextAtCursor] No trigger found, returning');
        return;
      }

      // Determine if it's a hashtag or mention
      final trigger = currentText[triggerIndex];
      final isHashtag = trigger == '#';

      // Use MentionTagTextField's addMention method with custom styling
      _mentionController.addMention(
        label: text,
        data: text,
        stylingWidget: Text(
          text,
          style: GoogleFonts.kumbhSans(
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: isHashtag ? Colors.green : Colors.blue,
          ),
        ),
      );

      debugPrint('[_insertTextAtCursor] Added mention with ${isHashtag ? "green" : "blue"} color');
      debugPrint('[_insertTextAtCursor] ===== END =====');
    }
  }



  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _mentionController.dispose();
    _removePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return GestureDetector(
      // Outer gesture detector to handle taps outside and dismiss keyboard
      onTap: () {
        if (_focusNode.hasFocus) {
          _dismissKeyboard();
        }
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          onTap: () {
            // Focus the text field when tapping on it
            _requestFocusWithDelay();
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
            child: GestureDetector(
              // Additional tap handler for iOS - focus the text field
              onTap: () {
                _requestFocusWithDelay();
              },
              behavior:
                  HitTestBehavior.opaque, // Prevent parent from receiving tap
              child: MentionTagTextField(
                controller: _mentionController,
                focusNode: _focusNode,
                maxLines: 50,
                minLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.done,
                autocorrect: true,
                enableSuggestions: true,
                cursorColor: controller.primaryColor ?? Colors.blue,
                cursorWidth: 2.0,
                cursorHeight: 20.0,
                // onMention callback - triggered when @ or # is typed
                onMention: (value) async {
                  if (value != null) {
                    // Determine if it's a hashtag or mention
                    final text = _mentionController.text;
                    final selection = _mentionController.selection;
                    if (selection.baseOffset > 0) {
                      final triggerIndex = _getLastTriggerIndex(text, selection.baseOffset);
                      if (triggerIndex >= 0) {
                        final trigger = text[triggerIndex];
                        if (trigger == '#') {
                          _showTagPopup(value);
                        } else if (trigger == '@') {
                          _showMentionPopup(value);
                        }
                      }
                    }
                  } else {
                    // Mention ended, close popup
                    _closePopup();
                  }
                },
                mentionTagDecoration: MentionTagDecoration(
                  // Define list of symbols where mention will be triggered
                  mentionStart: ['@', '#'],
                  // The character which will be inserted automatically after the mention
                  mentionBreak: ' ',
                  // Enable removing mention decrementally instead of all at once
                  allowDecrement: true,
                  // Prevent mention triggering if mention symbol is embedded in the text
                  allowEmbedding: false,
                  // Show mention symbol with mentions in the textfield
                  showMentionStartSymbol: true,
                  // Max words a mention can have
                  maxWords: null,
                  // TextStyle for mentions - we'll use green as default
                  // Note: The library doesn't support different colors for @ and #
                  // We'll need to use custom styling widgets when adding mentions
                  mentionTextStyle: GoogleFonts.kumbhSans(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'my memory... ',
                  hintStyle: GoogleFonts.kumbhSans(
                    fontWeight: FontWeight.w500,
                    color: controller.darkMode.value
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.grey,
                    fontSize: 16,
                  ),
                ),
                style: GoogleFonts.kumbhSans(
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: controller.darkMode.value ? Colors.white : Colors.black,
                ),
                onSubmitted: (_) {
                  // Hide keyboard when done is pressed
                  _focusNode.unfocus();
                },
                onChanged: (text) {
                  setState(() {}); // Rebuild if needed
                  // Sync to widget.controller
                  if (widget.controller.text != text) {
                    widget.controller.text = text;
                  }
                },
                onTap: () {
                  // Additional focus handling for iOS
                  if (!_focusNode.hasFocus) {
                    _requestFocusWithDelay();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
