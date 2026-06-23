import 'package:spacetime/app/services/memory_db.dart';

/// Shared newest-first ordering (same rules as add-memories list).
class MemorySort {
  MemorySort._();

  static String memorySortKey(Map<String, dynamic> memory) {
    final created = memory['created_at'];
    if (created is String && created.isNotEmpty) return created;
    final updated = memory['updated_at'];
    if (updated is String && updated.isNotEmpty) return updated;
    final year = memory['year']?.toString() ?? '';
    final date = memory['date']?.toString() ?? '';
    final time = memory['time']?.toString() ?? '';
    return '$year|$date|$time';
  }

  static List<Map<String, dynamic>> memoriesNewestFirst(
    List<Map<String, dynamic>> memories,
  ) {
    final list = List<Map<String, dynamic>>.from(memories);
    list.sort((a, b) => memorySortKey(b).compareTo(memorySortKey(a)));
    return list;
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
