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
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChange);
  }

  double? _scrollOffsetBeforeFocus;

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // When field gains focus, save current position and scroll up by 100 points
      if (widget.scrollController != null && widget.scrollController!.hasClients) {
        _scrollOffsetBeforeFocus = widget.scrollController!.offset;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && widget.scrollController!.hasClients) {
            final currentOffset = widget.scrollController!.offset;
            final targetOffset = currentOffset + 100.0;
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
            if (!controller.isEditing.value) {
              _removePopup();
            }
          } catch (_) {
            _removePopup();
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

    final text = widget.controller.text;
    final selection = widget.controller.selection;

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

    // Check if we're editing an existing tag
    final String? oldTag = keyword.isNotEmpty && _tags.contains(keyword) ? keyword : null;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              // Dismiss keyboard when tapping outside
              _focusNode.unfocus();
            },
            child: Positioned(
              left: 20,
              right: 20,
              top: 0, // Moved 150 points upward (was 150, now 0)
              child: GestureDetector(
                onTap: () {
                  // Prevent tap from propagating to parent
                },
                child: Material(
                  elevation: 8,
                  color: Colors.transparent,
                  child: TagMentionBottomSheet(
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
                    onEditingComplete: _forceRemovePopup,
                  ),
                ),
              ),
            ),
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

    // Check if we're editing an existing mention
    final String? oldMention = keyword.isNotEmpty && _mentions.contains(keyword) ? keyword : null;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              // Dismiss keyboard when tapping outside
              _focusNode.unfocus();
            },
            child: Positioned(
              left: 20,
              right: 20,
              top: 0, // Moved 150 points upward (was 150, now 0)
              child: GestureDetector(
                onTap: () {
                  // Prevent tap from propagating to parent
                },
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
                    onEditingComplete: _forceRemovePopup,
                  ),
                ),
              ),
            ),
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
  }

  void _insertTextAtCursor(String text) {
    final currentText = widget.controller.text;
    final selection = widget.controller.selection;

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

      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(
        offset: triggerIndex + text.length + 1,
      );
    }
  }

  List<TextSpan> _parseText(String text) {
    if (text.isEmpty) {
      return [TextSpan(text: '', style: _getDefaultStyle())];
    }

    final spans = <TextSpan>[];
    final defaultStyle = _getDefaultStyle();

    // Simple approach: split by spaces and check each word
    final words = text.split(' ');

    for (int i = 0; i < words.length; i++) {
      final word = words[i];

      if (word.startsWith('#') && word.length > 1) {
        // Check if this hashtag was actually selected/added from dropdown
        final tagName = word.substring(1); // Remove # prefix
        final isValidTag = _tags.contains(tagName);

        spans.add(
          TextSpan(
            text: word,
            style: isValidTag
                ? defaultStyle.copyWith(color: Colors.green)
                : defaultStyle, // Show as regular text if not selected
          ),
        );
      } else if (word.startsWith('@') && word.length > 1) {
        // Check if this mention was actually selected/added from dropdown
        final mentionName = word.substring(1); // Remove @ prefix
        final isValidMention = _mentions.contains(mentionName);

        spans.add(
          TextSpan(
            text: word,
            style: isValidMention
                ? defaultStyle.copyWith(color: Colors.blue)
                : defaultStyle, // Show as regular text if not selected
          ),
        );
      } else {
        // Regular word
        spans.add(TextSpan(text: word, style: defaultStyle));
      }

      // Add space after each word except the last one
      if (i < words.length - 1) {
        spans.add(TextSpan(text: ' ', style: defaultStyle));
      }
    }

    return spans;
  }

  TextStyle _getDefaultStyle() {
    final controller = Get.find<UiController>();
    return GoogleFonts.kumbhSans(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: controller.darkMode.value ? Colors.white : Colors.black,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
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
              child: Stack(
                children: [
                  // Show hint text when empty
                  if (widget.controller.text.isEmpty)
                    Text(
                      'my memory... ',
                      style: GoogleFonts.kumbhSans(
                        fontWeight: FontWeight.w500,
                        color:
                            controller.darkMode.value
                                ? Colors.white
                                : Colors.grey,
                        fontSize: 16,
                      ),
                    ),

                  // The visible rich text
                  if (widget.controller.text.isNotEmpty)
                    RichText(
                      text: TextSpan(
                        children: _parseText(widget.controller.text),
                      ),
                    ),

                  // The text field for input with visible cursor
                  TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLines: 50,
                    minLines: 8,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.done,
                    autocorrect: true,
                    enableSuggestions: true,
                    showCursor: true,
                    cursorColor: controller.primaryColor ?? Colors.blue,
                    cursorWidth: 2.0,
                    cursorHeight: 20.0,
                    cursorRadius: const Radius.circular(1.0),
                    onSubmitted: (_) {
                      // Hide keyboard when done is pressed
                      _focusNode.unfocus();
                    },
                    onChanged: (text) {
                      setState(() {}); // Rebuild to update RichText
                      _onTextChanged();
                    },
                    onTap: () {
                      // Additional focus handling for iOS
                      if (!_focusNode.hasFocus) {
                        _requestFocusWithDelay();
                      }
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '', // Empty hint to avoid conflicts
                    ),
                    style: GoogleFonts.kumbhSans(
                      fontSize: 16,
                      height: 1.5,
                      color: Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
