import 'package:audio_service/audio_service.dart';

import '../utils/song_sharing_config.dart';

typedef SharedSongResolver = Future<MediaItem?> Function(String videoId);
typedef SharedSongPlayer = Future<void> Function(MediaItem song);

/// Resolves canonical song-link requests without allowing stale metadata
/// responses to replace a more recent request.
class SongLinkPlaybackCoordinator {
  SongLinkPlaybackCoordinator({
    required SharedSongResolver resolveSong,
    required SharedSongPlayer playSong,
    void Function(Object error)? onFailure,
  })  : _resolveSong = resolveSong,
        _playSong = playSong,
        _onFailure = onFailure;

  final SharedSongResolver _resolveSong;
  final SharedSongPlayer _playSong;
  final void Function(Object error)? _onFailure;

  int _generation = 0;
  bool _disposed = false;

  Future<void> handle(String videoId) async {
    if (_disposed || !SongSharingConfig.isValidVideoId(videoId)) return;

    final requestGeneration = ++_generation;
    try {
      final song = await _resolveSong(videoId);
      if (_disposed || requestGeneration != _generation) return;
      if (song == null || song.id != videoId) {
        _reportFailure(StateError('Shared song metadata was unavailable.'));
        return;
      }
      await _playSong(song);
    } catch (error) {
      if (!_disposed && requestGeneration == _generation) {
        _reportFailure(error);
      }
    }
  }

  void _reportFailure(Object error) {
    try {
      _onFailure?.call(error);
    } catch (_) {
      // A UI notification failure must not escape the link event handler.
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
