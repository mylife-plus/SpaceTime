import 'package:flutter/material.dart';

/// Helper class to track matches
class _Match {
  final int start;
  final int end;
  final String text;
  final _MatchType type;

  _Match({
    required this.start,
    required this.end,
    required this.text,
    required this.type,
  });
}

/// Type of match
enum _MatchType {
  mention,
  hashtag,
}

/// Custom TextEditingController that supports mentions (@) and hashtags (#)
/// with custom styling and zero-width space markers for tracking
class MentionHashtagTextController extends TextEditingController {
  // Zero-width space used to mark mentions/hashtags that were selected (not just typed)
  static const String _zeroWidthSpace = '\u200B';

  // Lists to track added mentions and hashtags
  final List<String> _mentions = [];
  final List<String> _hashtags = [];

  // Custom styles for mentions and hashtags
  final TextStyle? mentionStyle;
  final TextStyle? hashtagStyle;
  final TextStyle? defaultStyle;

  MentionHashtagTextController({
    this.mentionStyle,
    this.hashtagStyle,
    this.defaultStyle,
  });

  /// Get all mentions (without @ symbol)
  List<String> get mentions => List.unmodifiable(_mentions);

  /// Get all hashtags (without # symbol)
  List<String> get hashtags => List.unmodifiable(_hashtags);

  /// Regex to match mentions: @username followed by zero-width space
  /// Matches: @john\u200B or @alice_123\u200B
  static final RegExp _mentionRegex = RegExp(r'@(\w+)' + _zeroWidthSpace);

  /// Regex to match hashtags: #tag followed by zero-width space
  /// Matches: #work\u200B or #project_2024\u200B
  static final RegExp _hashtagRegex = RegExp(r'#(\w+)' + _zeroWidthSpace);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> spans = [];
    final String textValue = text;
    int lastMatchEnd = 0;

    // Find all mentions and hashtags with their positions
    final List<_Match> matches = [];

    // Find all mentions
    for (final match in _mentionRegex.allMatches(textValue)) {
      matches.add(_Match(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        type: _MatchType.mention,
      ));
    }

    // Find all hashtags
    for (final match in _hashtagRegex.allMatches(textValue)) {
      matches.add(_Match(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        type: _MatchType.hashtag,
      ));
    }

    // Sort matches by position
    matches.sort((a, b) => a.start.compareTo(b.start));

    // Build text spans
    for (final match in matches) {
      // Add normal text before this match
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: textValue.substring(lastMatchEnd, match.start),
          style: style ?? defaultStyle,
        ));
      }

      // Add styled mention/hashtag (without zero-width space for display)
      final displayText = match.text.replaceAll(_zeroWidthSpace, '');
      spans.add(TextSpan(
        text: displayText,
        style: match.type == _MatchType.mention
            ? (mentionStyle ?? style?.copyWith(color: Colors.blue))
            : (hashtagStyle ?? style?.copyWith(color: Colors.green)),
      ));

      lastMatchEnd = match.end;
    }

    // Add remaining normal text
    if (lastMatchEnd < textValue.length) {
      spans.add(TextSpan(
        text: textValue.substring(lastMatchEnd),
        style: style ?? defaultStyle,
      ));
    }

    // If no matches, return all text as normal
    if (spans.isEmpty) {
      return TextSpan(text: textValue, style: style ?? defaultStyle);
    }

    return TextSpan(children: spans, style: style ?? defaultStyle);
  }

  /// Add a mention at the current cursor position
  /// @param username - The username without @ symbol (e.g., "john")
  void addMention(String username) {
    _addItem('@', username, _mentions);
  }

  /// Add a hashtag at the current cursor position
  /// @param tag - The tag without # symbol (e.g., "work")
  void addHashtag(String tag) {
    _addItem('#', tag, _hashtags);
  }

  /// Internal method to add mention or hashtag
  void _addItem(String trigger, String label, List<String> trackingList) {
    final currentText = text;
    final cursorPos = selection.baseOffset;

    if (cursorPos < 0) return;

    // Find the last trigger character before cursor
    final triggerIndex = _findLastTriggerIndex(currentText, cursorPos, trigger);

    if (triggerIndex == -1) return;

    // Find end of incomplete word (if any)
    int endIndex = cursorPos;
    while (endIndex < currentText.length &&
           currentText[endIndex] != ' ' &&
           currentText[endIndex] != '\n') {
      endIndex++;
    }

    // Build new text: before + trigger + label + zero-width space + space + after
    final beforeTrigger = currentText.substring(0, triggerIndex);
    final afterWord = currentText.substring(endIndex);
    final itemText = '$trigger$label$_zeroWidthSpace ';
    final newText = beforeTrigger + itemText + afterWord;

    // Calculate new cursor position (after the inserted item)
    final newCursorPos = triggerIndex + itemText.length;

    // Update text and selection
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    // Track the mention/hashtag
    if (!trackingList.contains(label)) {
      trackingList.add(label);
    }
  }

  /// Find the last occurrence of trigger character before cursor position
  int _findLastTriggerIndex(String text, int cursorPos, String trigger) {
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == trigger) {
        // Check if it's at start or preceded by space/newline
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          return i;
        }
      } else if (text[i] == ' ' || text[i] == '\n') {
        // Hit a space before finding trigger, stop searching
        break;
      }
    }
    return -1;
  }

  /// Get parsed comment input as list of alternating text and mentions/hashtags
  /// Returns: ["normal text", "@john", " says ", "#hello", "!"]
  List<String> getCommentInput() {
    final List<String> result = [];
    final String textValue = text;
    int lastIndex = 0;

    // Find all mentions and hashtags
    final List<_Match> matches = [];

    for (final match in _mentionRegex.allMatches(textValue)) {
      matches.add(_Match(
        start: match.start,
        end: match.end,
        text: match.group(0)!.replaceAll(_zeroWidthSpace, ''),
        type: _MatchType.mention,
      ));
    }

    for (final match in _hashtagRegex.allMatches(textValue)) {
      matches.add(_Match(
        start: match.start,
        end: match.end,
        text: match.group(0)!.replaceAll(_zeroWidthSpace, ''),
        type: _MatchType.hashtag,
      ));
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    for (final match in matches) {
      // Add text before match
      if (match.start > lastIndex) {
        result.add(textValue.substring(lastIndex, match.start));
      }
      // Add mention/hashtag
      result.add(match.text);
      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < textValue.length) {
      result.add(textValue.substring(lastIndex).replaceAll(_zeroWidthSpace, ''));
    }

    return result;
  }

  /// Reconstruct controller text from saved comment input
  /// Input: ["normal text", "@john", " says ", "#hello", "!"]
  void createCommentInput(List<String> commentParts) {
    final buffer = StringBuffer();
    _mentions.clear();
    _hashtags.clear();

    for (final part in commentParts) {
      if (part.startsWith('@')) {
        // It's a mention
        final username = part.substring(1);
        buffer.write('@$username$_zeroWidthSpace');
        if (!_mentions.contains(username)) {
          _mentions.add(username);
        }
      } else if (part.startsWith('#')) {
        // It's a hashtag
        final tag = part.substring(1);
        buffer.write('#$tag$_zeroWidthSpace');
        if (!_hashtags.contains(tag)) {
          _hashtags.add(tag);
        }
      } else {
        // Normal text
        buffer.write(part);
      }
    }

    text = buffer.toString();
  }

  @override
  void clear() {
    super.clear();
    _mentions.clear();
    _hashtags.clear();
  }

  /// Remove a mention from tracking (when user deletes it)
  void removeMention(String username) {
    _mentions.remove(username);
  }

  /// Remove a hashtag from tracking (when user deletes it)
  void removeHashtag(String tag) {
    _hashtags.remove(tag);
  }

  /// Clean up mentions/hashtags that are no longer in the text
  void cleanupRemovedItems() {
    final currentText = text;

    // Check mentions
    _mentions.removeWhere((username) {
      final pattern = '@$username$_zeroWidthSpace';
      return !currentText.contains(pattern);
    });

    // Check hashtags
    _hashtags.removeWhere((tag) {
      final pattern = '#$tag$_zeroWidthSpace';
      return !currentText.contains(pattern);
    });
  }
}
