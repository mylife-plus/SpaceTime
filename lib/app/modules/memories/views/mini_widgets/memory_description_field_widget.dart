import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
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

  /// Rebuild colored spans after [validTags]/[validMentions] change.
  void refreshColoredSpans() => notifyListeners();

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
    // Match known @/# tokens greedily (supports multi-word contact names).
    // Word-splitting left the first spaced mention uncolored.
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (ch == '@' || ch == '#') {
        final list = ch == '@' ? validMentions : validTags;
        String? best;
        final rest = text.substring(i + 1);
        final restLower = rest.toLowerCase();
        for (final name in list) {
          if (name.isEmpty) continue;
          final nameLower = name.toLowerCase();
          if (!restLower.startsWith(nameLower)) continue;
          final end = i + 1 + name.length;
          final boundaryOk = end >= text.length ||
              text[end] == ' ' ||
              text[end] == '\n';
          if (!boundaryOk) continue;
          if (best == null || name.length > best.length) best = name;
        }
        if (best != null) {
          final token = text.substring(i, i + 1 + best.length);
          spans.add(
            TextSpan(
              text: token,
              style: defaultStyle.copyWith(
                color: ch == '@' ? Colors.blue : Colors.green,
              ),
            ),
          );
          i += token.length;
          continue;
        }
      }
      // Plain run until next trigger.
      var j = i + 1;
      while (j < text.length && text[j] != '@' && text[j] != '#') {
        j++;
      }
      spans.add(TextSpan(text: text.substring(i, j), style: defaultStyle));
      i = j;
    }

    return TextSpan(children: spans, style: defaultStyle);
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
  int _savedCursorPosition = 0;
  bool _preventAutoFocus = false;
  String _previousText = '';
  Timer? _cursorDebounceTimer;

  final List<String> _tags = [];
  final List<String> _mentions = [];

  late ColoredTextEditingController _coloredController;

  List<String> getTags() => _tags;
  List<String> getMentions() => _mentions;

  /// Initialize tags from existing data (for edit mode)
  void initializeTags(List<String> tags) {
    _tags.clear();
    _tags.addAll(tags);
    _coloredController.refreshColoredSpans();
    if (mounted) setState(() {});
  }

  /// Initialize mentions from existing data (for edit mode)
  void initializeMentions(List<String> mentions) {
    _mentions.clear();
    _mentions.addAll(mentions);
    _coloredController.refreshColoredSpans();
    if (mounted) setState(() {});
  }

  void _onTagAdded(String tag) {
    _tags.add(tag);
    widget.onTagAdded(tag);
  }

  void _onMentionAdded(String mention) {
    _mentions.add(mention);
    widget.onMentionAdded(mention);
  }

  /// True when [text] still contains `#name` / `@name` as a whole token.
  bool _textStillHasToken(String text, String triggerChar, String name) {
    if (name.isEmpty) return false;
    final needle = '$triggerChar${name.toLowerCase()}';
    final lower = text.toLowerCase();
    var from = 0;
    while (true) {
      final i = lower.indexOf(needle, from);
      if (i < 0) return false;
      final end = i + needle.length;
      final boundaryOk =
          end >= lower.length || lower[end] == ' ' || lower[end] == '\n';
      final startOk =
          i == 0 || lower[i - 1] == ' ' || lower[i - 1] == '\n';
      if (startOk && boundaryOk) return true;
      from = i + 1;
    }
  }

  /// Drop from the valid list only when no other occurrence remains in [text].
  /// Removing the last duplicate via X used to clear the list entry and strip
  /// color/functionality from every other identical @/# still in the field.
  void _unregisterTokenIfAbsent(
    String text,
    String triggerChar,
    String name,
  ) {
    if (_textStillHasToken(text, triggerChar, name)) return;
    if (triggerChar == '#') {
      _tags.removeWhere((t) => t.toLowerCase() == name.toLowerCase());
    } else if (triggerChar == '@') {
      _mentions.removeWhere((m) => m.toLowerCase() == name.toLowerCase());
    }
  }

  /// Clean up tags and mentions that are no longer present in the text
  void _cleanupRemovedItems() {
    final text = _coloredController.text;
    _tags.removeWhere((tag) => !_textStillHasToken(text, '#', tag));
    _mentions.removeWhere(
      (mention) => !_textStillHasToken(text, '@', mention),
    );
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
    _previousText = widget.controller.text;
    _coloredController.addListener(_onColoredControllerChanged);

    widget.controller.addListener(_onWidgetControllerChanged);

    _focusNode.addListener(_onFocusChange);
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.delete)) {
        if (_tryDeleteTokenWithBackspace()) {
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  void _onColoredControllerChanged() {
    final currentText = _coloredController.text;
    final textChanged = currentText != _previousText;

    if (textChanged) {
      if (_coloredController.text != widget.controller.text) {
        widget.controller.value = _coloredController.value;
      }
      _previousText = currentText;
      _cursorDebounceTimer?.cancel();
      _onTextChanged();
    }
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

  void _onCursorLanded() {
    if (!_focusNode.hasFocus || _isPopupOpen) return;

    final text = _coloredController.text;
    final selection = _coloredController.selection;
    if (!selection.isCollapsed || selection.baseOffset <= 0 || text.isEmpty) return;

    final cursorPos = selection.baseOffset;
    final triggerIndex = _findTriggerForWord(text, cursorPos);
    if (triggerIndex == -1) return;

    final triggerChar = text[triggerIndex];
    int endIndex = cursorPos;
    while (endIndex < text.length && text[endIndex] != ' ' && text[endIndex] != '\n') {
      endIndex++;
    }
    final keyword = text.substring(triggerIndex + 1, endIndex);
    if (keyword.isEmpty || keyword.contains(' ') || keyword.contains('\n')) return;

    if (triggerChar == '#' && _tags.any((t) => t.toLowerCase() == keyword.toLowerCase())) {
      _showTagPopup(keyword);
    } else if (triggerChar == '@' && _mentions.any((m) => m.toLowerCase() == keyword.toLowerCase())) {
      _showMentionPopup(keyword);
    }
  }

  int _findTriggerForWord(String text, int cursorPos) {
    int pos = cursorPos - 1;
    while (pos >= 0 && text[pos] != ' ' && text[pos] != '\n') {
      if (text[pos] == '#' || text[pos] == '@') {
        if (pos == 0 || text[pos - 1] == ' ' || text[pos - 1] == '\n') {
          return pos;
        }
      }
      pos--;
    }
    return -1;
  }

  void _onTextChanged() {
    _cleanupRemovedItems();

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

    if (triggerIndex > 0) {
      final charBeforeTrigger = text[triggerIndex - 1];
      if (charBeforeTrigger != ' ' && charBeforeTrigger != '\n') {
        _removePopup();
        return;
      }
    }

    final triggerChar = text[triggerIndex];
    final keyword = text.substring(triggerIndex + 1, cursorPos);

    if (keyword.contains(' ') || keyword.contains('\n')) {
      if (_isPopupOpen) {
        final lastChar = cursorPos > 0 ? text[cursorPos - 1] : '';

        if (lastChar == ' ' || lastChar == '\n') {
          showTrSnackbar(
            'snackbar_space_not_allowed',
            args: [triggerChar == '#' ? 'hashtags' : 'mentions'],
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
            snackPosition: SnackPosition.BOTTOM,
          );

          final newText = text.substring(0, cursorPos - 1) + text.substring(cursorPos);
          _coloredController.text = newText;
          _coloredController.selection = TextSelection.collapsed(
            offset: cursorPos - 1,
          );

          return;
        }
      }

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
    // Include the char under the caret so X works when the cursor sits on @/#.
    final end = cursorPos.clamp(0, text.length);
    final lastAt = text.lastIndexOf('@', end);
    final lastHash = text.lastIndexOf('#', end);
    if (lastAt < 0 && lastHash < 0) return -1;
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
      useRootNavigator: true,
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
                  final clean = item.substring(1);
                  // Register before insert so the first paint is already colored.
                  if (!_tags.any((t) => t.toLowerCase() == clean.toLowerCase())) {
                    _tags.add(clean);
                  }
                  widget.onTagAdded(clean);
                  _insertTextAtSavedCursor(item);
                  // If this occurrence was renamed, drop old name only when no
                  // other copies of it remain in the description.
                  if (oldTag != null &&
                      oldTag.toLowerCase() != clean.toLowerCase()) {
                    _unregisterTokenIfAbsent(
                      _coloredController.text,
                      '#',
                      oldTag,
                    );
                  }
                  _coloredController.refreshColoredSpans();
                  if (mounted) setState(() {});

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
                  if (keyword.isEmpty) {
                    _clearIncompleteText();
                  }
                  Navigator.of(context).pop();
                },
                onSeeListCancelled: () {
                  _clearIncompleteText();
                  _onDialogClosed();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) _focusNode.requestFocus();
                  });
                },
                excludedItems: _tags,
                isEditingExisting: isEditingExisting,
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
      useRootNavigator: true,
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
                  final clean = item.substring(1);
                  // Register before insert so the first paint is already colored.
                  if (!_mentions.any((m) => m.toLowerCase() == clean.toLowerCase())) {
                    _mentions.add(clean);
                  }
                  widget.onMentionAdded(clean);
                  _insertTextAtSavedCursor(item);
                  // If this occurrence was renamed, drop old name only when no
                  // other copies of it remain in the description.
                  if (oldMention != null &&
                      oldMention.toLowerCase() != clean.toLowerCase()) {
                    _unregisterTokenIfAbsent(
                      _coloredController.text,
                      '@',
                      oldMention,
                    );
                  }
                  _coloredController.refreshColoredSpans();
                  if (mounted) setState(() {});

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
                  if (keyword.isEmpty) {
                    _clearIncompleteText();
                  }
                  Navigator.of(context).pop();
                },
                onSeeListCancelled: () {
                  _clearIncompleteText();
                  _onDialogClosed();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) _focusNode.requestFocus();
                  });
                },
                excludedItems: _mentions,
                isEditingExisting: isEditingExisting,
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
    _clearIncompleteText();
    _forceRemovePopup();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _clearIncompleteText() {
    final currentText = _coloredController.text;
    // `_savedCursorPosition` may be 0 (valid) when the draft starts at offset 0.
    var cursorPos = _savedCursorPosition;
    if (cursorPos < 0) {
      cursorPos = _coloredController.selection.baseOffset;
    }
    cursorPos = cursorPos.clamp(0, currentText.length);

    if (currentText.isEmpty) return;

    // Prefer the token under/just before the caret (correct for last duplicate).
    // `_getLastTriggerIndex` alone can bind to the wrong @/# when the caret
    // sits on a trigger character.
    var triggerIndex = _findTriggerForWord(
      currentText,
      cursorPos == 0 ? 1 : cursorPos,
    );
    if (triggerIndex == -1 &&
        cursorPos < currentText.length &&
        (currentText[cursorPos] == '@' || currentText[cursorPos] == '#')) {
      triggerIndex = cursorPos;
    }
    if (triggerIndex == -1) {
      triggerIndex = _getLastTriggerIndex(currentText, cursorPos);
    }
    if (triggerIndex == -1) return;

    final triggerChar = currentText[triggerIndex];
    final list = triggerChar == '#' ? _tags : _mentions;

    // Prefer deleting a full known multi-word token when present.
    String? matchedName;
    final afterTrigger = currentText.substring(triggerIndex + 1);
    final afterLower = afterTrigger.toLowerCase();
    for (final name in list) {
      if (name.isEmpty) continue;
      if (!afterLower.startsWith(name.toLowerCase())) continue;
      final end = triggerIndex + 1 + name.length;
      final boundaryOk =
          end >= currentText.length ||
          currentText[end] == ' ' ||
          currentText[end] == '\n';
      if (!boundaryOk) continue;
      if (matchedName == null || name.length > matchedName.length) {
        matchedName = name;
      }
    }

    int endIndex;
    String word;
    if (matchedName != null) {
      endIndex = triggerIndex + 1 + matchedName.length;
      word = matchedName;
    } else {
      endIndex = cursorPos > triggerIndex ? cursorPos : triggerIndex + 1;
      while (endIndex < currentText.length &&
          currentText[endIndex] != ' ' &&
          currentText[endIndex] != '\n') {
        endIndex++;
      }
      word = currentText.substring(triggerIndex + 1, endIndex);
    }

    var deleteEnd = endIndex;
    if (deleteEnd < currentText.length && currentText[deleteEnd] == ' ') {
      deleteEnd++;
    }

    final newText = currentText.replaceRange(triggerIndex, deleteEnd, '');
    // Only drop from the valid list when no other copy remains — otherwise
    // deleting the last duplicate strips color from every earlier one.
    if (word.isNotEmpty && (triggerChar == '#' || triggerChar == '@')) {
      if (_textStillHasToken(newText, triggerChar, word)) {
        // Ensure remaining copies stay registered (deduped add).
        if (triggerChar == '#') {
          if (!_tags.any((t) => t.toLowerCase() == word.toLowerCase())) {
            _tags.add(word);
          }
        } else if (!_mentions.any((m) => m.toLowerCase() == word.toLowerCase())) {
          _mentions.add(word);
        }
      } else {
        _unregisterTokenIfAbsent(newText, triggerChar, word);
      }
    }

    _coloredController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: triggerIndex),
    );
    _previousText = newText;
    _coloredController.refreshColoredSpans();
    if (mounted) setState(() {});
  }

  /// Backspace/delete at/inside a confirmed `#tag` / `@mention` deletes the whole token.
  bool _tryDeleteTokenWithBackspace() {
    final selection = _coloredController.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    final text = _coloredController.text;
    final cursor = selection.baseOffset;
    if (text.isEmpty) return false;

    int start;
    int end;

    // Cursor sitting on the `#`/`@` of a token (or Delete with caret before it).
    if (cursor < text.length && (text[cursor] == '#' || text[cursor] == '@')) {
      start = cursor;
      end = cursor + 1;
      while (end < text.length && text[end] != ' ' && text[end] != '\n') {
        end++;
      }
    } else if (cursor > 0) {
      // Cursor after/inside a token — delete the token that owns the prior char.
      if (text[cursor - 1] == ' ' || text[cursor - 1] == '\n') return false;
      end = cursor;
      start = end - 1;
      while (start > 0 && text[start] != ' ' && text[start] != '\n') {
        start--;
      }
      if (text[start] == ' ' || text[start] == '\n') start++;
    } else {
      return false;
    }

    if (start >= end) return false;
    final token = text.substring(start, end);
    if (!token.startsWith('#') && !token.startsWith('@')) return false;
    final name = token.substring(1);
    // Lone `@` / `#` (popup open or just typed): delete trigger + close popup.
    if (name.isEmpty) {
      if (_isPopupOpen) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _removeIncompleteTextAndClosePopup();
        return true;
      }
      final newText = text.replaceRange(start, end, '');
      _coloredController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
      _previousText = newText;
      if (mounted) setState(() {});
      return true;
    }

    final isTag = token.startsWith('#');
    final isKnown = isTag
        ? _tags.any((t) => t.toLowerCase() == name.toLowerCase())
        : _mentions.any((m) => m.toLowerCase() == name.toLowerCase());
    if (!isKnown) return false;

    var deleteEnd = end;
    if (deleteEnd < text.length && text[deleteEnd] == ' ') deleteEnd++;

    final newText = text.replaceRange(start, deleteEnd, '');
    final triggerChar = isTag ? '#' : '@';
    if (_textStillHasToken(newText, triggerChar, name)) {
      if (isTag) {
        if (!_tags.any((t) => t.toLowerCase() == name.toLowerCase())) {
          _tags.add(name);
        }
      } else if (!_mentions.any((m) => m.toLowerCase() == name.toLowerCase())) {
        _mentions.add(name);
      }
    } else {
      _unregisterTokenIfAbsent(newText, triggerChar, name);
    }
    _coloredController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
    );
    _previousText = newText;
    _cleanupRemovedItems();
    _coloredController.refreshColoredSpans();
    if (mounted) setState(() {});
    return true;
  }

  void _insertTextAtCursor(String text) {
    final currentText = _coloredController.text;
    final selection = _coloredController.selection;

    if (selection.baseOffset >= 0) {
      final cursorPos = selection.baseOffset.clamp(0, currentText.length);
      final triggerIndex = _getLastTriggerIndex(
        currentText,
        cursorPos,
      );

      int startIndex;
      int endIndex;

      if (triggerIndex != -1 && triggerIndex < cursorPos) {
        startIndex = triggerIndex;
        endIndex = cursorPos;
        while (endIndex < currentText.length &&
               currentText[endIndex] != ' ' &&
               currentText[endIndex] != '\n') {
          endIndex++;
        }
      } else {
        startIndex = cursorPos;
        endIndex = cursorPos;
      }

      final hasTrailingSpace = endIndex < currentText.length && currentText[endIndex] == ' ';
      final suffix = hasTrailingSpace ? '' : ' ';

      final newText = currentText.replaceRange(
        startIndex,
        endIndex,
        '$text$suffix',
      );

      _coloredController.text = newText;
      _coloredController.selection = TextSelection.collapsed(
        offset: startIndex + text.length + suffix.length,
      );
    }
  }

  void _insertTextAtSavedCursor(String text) {
    final currentText = _coloredController.text;

    if (_savedCursorPosition >= 0) {
      final clampedPos = _savedCursorPosition.clamp(0, currentText.length);
      final triggerIndex = _getLastTriggerIndex(
        currentText,
        clampedPos,
      );

      int startIndex;
      int endIndex;

      if (triggerIndex != -1 && triggerIndex < clampedPos) {
        startIndex = triggerIndex;
        endIndex = clampedPos;
        while (endIndex < currentText.length &&
               currentText[endIndex] != ' ' &&
               currentText[endIndex] != '\n') {
          endIndex++;
        }
      } else {
        startIndex = clampedPos;
        endIndex = clampedPos;
      }

      final hasTrailingSpace = endIndex < currentText.length && currentText[endIndex] == ' ';
      final suffix = hasTrailingSpace ? '' : ' ';

      final newText = currentText.replaceRange(
        startIndex,
        endIndex,
        '$text$suffix',
      );

      _coloredController.text = newText;
      _coloredController.selection = TextSelection.collapsed(
        offset: startIndex + text.length + suffix.length,
      );
    }
  }

  @override
  void dispose() {
    _cursorDebounceTimer?.cancel();
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 350),
            child: TextField(
            controller: _coloredController,
            focusNode: _focusNode,
            maxLines: null,
            minLines: 8,
            scrollPhysics: const BouncingScrollPhysics(),
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            autocorrect: true,
            enableSuggestions: true,
            showCursor: true,
            cursorColor: controller.primaryColor ?? Colors.blue,
            cursorWidth: 2.0,
            cursorHeight: 20.0,
            cursorRadius: const Radius.circular(1.0),
            onChanged: (text) {
              _previousText = text;
              _cursorDebounceTimer?.cancel();
              setState(() {});
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
              hintText: 'hinttext_my_memory'.tr,
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
          ), // ConstrainedBox
        ), // Container
      // ), // GestureDetector
    );
  }
}
