import 'package:intl/intl.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'dart:isolate';

/// Shared newest-first ordering (same rules as add-memories list and map focus).
class MemorySort {
  MemorySort._();

  /// User-selected memory date/time from UI fields (`date`, `year`, `time`).
  /// Matches map timeline / camera focus ordering — not row insertion time.
  static DateTime? parseMemoryDateTime(Map<String, dynamic> memory) {
    final date = (memory['date'] as String?) ?? '';
    final year = (memory['year'] as String?) ?? '';
    final time = (memory['time'] as String?) ?? '';
    try {
      if (date.isNotEmpty && year.isNotEmpty) {
        if (time.isNotEmpty) {
          final format =
              time.toLowerCase().contains('am') ||
                      time.toLowerCase().contains('pm')
                  ? 'd. MMMM yyyy hh:mm a'
                  : 'd. MMMM yyyy HH:mm';
          return DateFormat(format).parse('$date $year $time');
        }
        return DateFormat('d. MMMM yyyy').parse('$date $year');
      }
      if (date.isNotEmpty) {
        final parsed = DateTime.tryParse(date);
        if (parsed != null) return parsed;
      }
    } catch (_) {
      // Fall through to created_at / legacy key.
    }
    return null;
  }

  static String memorySortKey(Map<String, dynamic> memory) {
    final when = parseMemoryDateTime(memory);
    if (when != null) return when.toUtc().toIso8601String();
    return _fallbackSortKey(memory);
  }

  static String _fallbackSortKey(Map<String, dynamic> memory) {
    final created = memory['created_at'];
    if (created is String && created.isNotEmpty) return created;
    final updated = memory['updated_at'];
    if (updated is String && updated.isNotEmpty) return updated;
    final year = memory['year']?.toString() ?? '';
    final date = memory['date']?.toString() ?? '';
    final time = memory['time']?.toString() ?? '';
    return '$year|$date|$time';
  }

  static int compareMemoriesNewestFirst(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final ad = parseMemoryDateTime(a);
    final bd = parseMemoryDateTime(b);
    if (ad != null && bd != null) return bd.compareTo(ad);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return memorySortKey(b).compareTo(memorySortKey(a));
  }

  static List<Map<String, dynamic>> memoriesNewestFirst(
    List<Map<String, dynamic>> memories,
  ) {
    final list = List<Map<String, dynamic>>.from(memories);
    final parsedDates = Map<Map<String, dynamic>, DateTime?>.identity();
    final fallbackKeys = Map<Map<String, dynamic>, String>.identity();
    for (final memory in list) {
      parsedDates[memory] = parseMemoryDateTime(memory);
      fallbackKeys[memory] = _fallbackSortKey(memory);
    }
    list.sort((a, b) {
      final ad = parsedDates[a];
      final bd = parsedDates[b];
      if (ad != null && bd != null) return bd.compareTo(ad);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return fallbackKeys[b]!.compareTo(fallbackKeys[a]!);
    });
    return list;
  }

  /// Sort off the UI isolate when the library is large.
  static Future<List<Map<String, dynamic>>> memoriesNewestFirstAsync(
    List<Map<String, dynamic>> memories, {
    int isolateThreshold = 80,
  }) async {
    if (memories.length < isolateThreshold) {
      return memoriesNewestFirst(memories);
    }
    return Isolate.run(() => memoriesNewestFirst(memories));
  }

  static List<T> sortedByWhenNewestFirst<T>(
    Iterable<T> items,
    DateTime Function(T) getWhen,
  ) {
    final list = [...items];
    list.sort((a, b) => getWhen(b).compareTo(getWhen(a)));
    return list;
  }

  static List<Map<String, dynamic>> trackLogItemsNewestFirst(
    Iterable<Map<String, dynamic>> items,
  ) {
    final list = [...items];
    list.sort((a, b) {
      final aw = DateTime.tryParse(
        (a[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString(),
      );
      final bw = DateTime.tryParse(
        (b[DatabaseHelper.columnTrackLogItemWhen] ?? '').toString(),
      );
      if (aw == null && bw == null) return 0;
      if (aw == null) return 1;
      if (bw == null) return -1;
      return bw.compareTo(aw);
    });
    return list;
  }

  static ({DateTime? from, DateTime? to}) whenRange(Iterable<DateTime> whens) {
    final list = whens.toList();
    if (list.isEmpty) return (from: null, to: null);
    var from = list.first;
    var to = list.first;
    for (final d in list) {
      if (d.isBefore(from)) from = d;
      if (d.isAfter(to)) to = d;
    }
    return (from: from, to: to);
  }
}
