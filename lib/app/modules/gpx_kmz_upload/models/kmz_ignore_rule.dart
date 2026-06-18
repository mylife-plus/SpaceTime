/// What KML/KMZ field the ignore rule targets.
enum KmzIgnoreTagKey {
  styleUrl,
  lineOrIconColor,
  trackPointTime,
  dynamicTag,
}

/// How [value] is compared (text rules) or how the track time is compared to the threshold (date rules).
enum KmzIgnoreCondition {
  textContains,
  textEquals,
  textStartsWith,
  dateIgnoreAfter,
  dateIgnoreBefore,
  dateIgnoreOnOrAfter,
  dateIgnoreOnOrBefore,
}

class KmzIgnoreRule {
  KmzIgnoreRule({
    String? id,
    required this.tag,
    required this.value,
    required this.condition,
    this.tagKey,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}';

  final String id;
  final KmzIgnoreTagKey tag;
  /// Used when [tag] is [KmzIgnoreTagKey.dynamicTag].
  final String? tagKey;
  /// Style fragment, 8-char KML aabbggrr color, or ISO-8601 threshold for date rules.
  final String value;
  final KmzIgnoreCondition condition;

  List<String> parsedValues() {
    return value
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<KmzIgnoreCondition> conditionsForTag(KmzIgnoreTagKey tag) {
    switch (tag) {
      case KmzIgnoreTagKey.styleUrl:
      case KmzIgnoreTagKey.lineOrIconColor:
      case KmzIgnoreTagKey.dynamicTag:
        return const [
          KmzIgnoreCondition.textEquals,
        ];
      case KmzIgnoreTagKey.trackPointTime:
        return const [
          KmzIgnoreCondition.dateIgnoreAfter,
          KmzIgnoreCondition.dateIgnoreBefore,
          KmzIgnoreCondition.dateIgnoreOnOrAfter,
          KmzIgnoreCondition.dateIgnoreOnOrBefore,
        ];
    }
  }

  String summaryLabel() {
    final vals = parsedValues();
    final primary = vals.isEmpty ? value : vals.first;
    final v = primary.length > 24 ? '${primary.substring(0, 21)}…' : primary;
    final suffix = vals.length > 1 ? ' +${vals.length - 1}' : '';
    switch (tag) {
      case KmzIgnoreTagKey.styleUrl:
        return 'style:$v$suffix';
      case KmzIgnoreTagKey.lineOrIconColor:
        return 'color:$v$suffix';
      case KmzIgnoreTagKey.trackPointTime:
        return 'time:$v$suffix';
      case KmzIgnoreTagKey.dynamicTag:
        final k = (tagKey == null || tagKey!.trim().isEmpty)
            ? 'tag'
            : tagKey!.trim();
        return '$k:$v$suffix';
    }
  }

  /// Timestamp/date/time fields are excluded from the ignore-rule tag picker.
  static const Set<String> _excludedDateTimeTagKeys = {
    'when',
    'timestamp',
    'created',
    'creationtime',
    'datetime',
    'date',
    'time',
    'begin',
    'end',
    'start',
    'stop',
    'started',
    'ended',
  };

  static bool isExcludedDateTimeTagKey(String key) {
    final k = key.trim().toLowerCase();
    if (k.isEmpty) return true;
    if (_excludedDateTimeTagKeys.contains(k)) return true;
    if (k.endsWith('time') || k.endsWith('date') || k.endsWith('timestamp')) {
      return true;
    }
    if (k.contains('timestamp') || k.contains('datetime')) return true;
    return false;
  }
}
