/// Concurrency helpers for bounded parallel work (e.g. parallel file I/O during
/// bulk media import) without spawning an unbounded number of in-flight futures.
library;

/// Runs [task] for every item in [items] with at most [concurrency] tasks
/// in flight at once, and returns the results in the SAME order as [items].
///
/// A fixed pool of [concurrency] workers pulls indices from a shared cursor, so
/// memory/peak-I/O stays bounded even for large inputs. The index read +
/// increment is synchronous (no `await` between them), so there is no race in
/// Dart's single-threaded event loop.
///
/// [task] receives the item and its original index. If [task] throws, the
/// error propagates out of this function (via the underlying `Future.wait`), so
/// callers that want per-item resilience should catch inside [task].
Future<List<R>> mapWithConcurrency<T, R>(
  List<T> items,
  int concurrency,
  Future<R> Function(T item, int index) task,
) async {
  if (items.isEmpty) return <R>[];

  final limit = concurrency < 1 ? 1 : concurrency;
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) break;
      results[i] = await task(items[i], i);
    }
  }

  final workerCount = limit < items.length ? limit : items.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));
  return results.cast<R>();
}
