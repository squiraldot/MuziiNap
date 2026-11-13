/// Distinguishes AudioHandler's initial empty media state from an actual
/// stop event. A null media item is only a stop after playback supplied a song.
class MediaItemLifecycleGuard {
  bool _hasReceivedMediaItem = false;

  bool shouldDismissFor(dynamic mediaItem) {
    if (mediaItem != null) {
      _hasReceivedMediaItem = true;
      return false;
    }
    return _hasReceivedMediaItem;
  }
}
