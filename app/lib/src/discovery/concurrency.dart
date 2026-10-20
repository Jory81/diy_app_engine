/// Runs [task] for every item with at most [concurrency] tasks in flight.
Future<void> forEachLimited<T>(
  Iterable<T> items,
  int concurrency,
  Future<void> Function(T item) task,
) async {
  final iterator = items.iterator;
  Future<void> worker() async {
    while (iterator.moveNext()) {
      await task(iterator.current);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
}
