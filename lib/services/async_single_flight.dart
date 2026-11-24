/// Shares one in-flight asynchronous operation among concurrent callers.
/// Once it completes (successfully or with an error), the next caller may retry.
class AsyncSingleFlight<T> {
  Future<T>? _pending;

  Future<T> run(Future<T> Function() operation) {
    final existing = _pending;
    if (existing != null) return existing;

    late final Future<T> pending;
    pending = Future<T>.sync(operation).whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
    _pending = pending;
    return pending;
  }
}
