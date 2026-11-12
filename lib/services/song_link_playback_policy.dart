/// Pure queue-ordering policy for incoming shared-song playback.
class SharedSongQueuePolicy {
  SharedSongQueuePolicy._();

  /// Places [target] first, reuses an existing queue instance with the same
  /// ID when present, removes duplicate copies of that ID, and preserves the
  /// relative order of every other queued item.
  static List<T> prioritize<T>(
    List<T> currentQueue,
    T target,
    String Function(T item) idOf,
  ) {
    final targetId = idOf(target);
    T selectedTarget = target;
    for (final item in currentQueue) {
      if (idOf(item) == targetId) {
        selectedTarget = item;
        break;
      }
    }
    return <T>[
      selectedTarget,
      ...currentQueue.where((item) => idOf(item) != targetId),
    ];
  }
}
