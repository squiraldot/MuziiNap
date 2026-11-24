import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

typedef ThemeWidgetPublisher = Future<void> Function(
  String title,
  String artist,
  bool isPlaying,
);

/// Publishes only playback metadata and transport state to Android widgets.
/// Artwork is intentionally excluded; native rendering uses bundled theme art.
class ThemeWidgetCoordinator extends GetxService {
  ThemeWidgetCoordinator({
    required AudioHandler audioHandler,
    ThemeWidgetPublisher? publisher,
  })  : _audioHandler = audioHandler,
        _publisher = publisher ?? _publishToAndroidWidget;

  static const MethodChannel _channel =
      MethodChannel('muziinap/theme_music_widget');

  final AudioHandler _audioHandler;
  final ThemeWidgetPublisher _publisher;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  MediaItem? _mediaItem;
  PlaybackState? _playbackState;
  Future<void> _publishQueue = Future<void>.value();
  String? _lastPayload;
  bool _started = false;
  bool _closed = false;

  static Future<void> _publishToAndroidWidget(
    String title,
    String artist,
    bool isPlaying,
  ) {
    return _channel.invokeMethod<void>(
      'updatePlayback',
      <String, Object>{
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
      },
    );
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _mediaItemSubscription = _audioHandler.mediaItem.listen(
      (item) {
        _mediaItem = item;
        _publish();
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Theme widget media-item stream failed: $error');
      },
    );
    _playbackSubscription = _audioHandler.playbackState.listen(
      (state) {
        _playbackState = state;
        _publish();
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Theme widget playback stream failed: $error');
      },
    );
  }

  void _publish() {
    if (_closed || _playbackState == null) return;
    final item = _mediaItem;
    final title = item?.title.trim().isNotEmpty == true
        ? item!.title.trim()
        : 'Nothing playing';
    final artist = item?.artist?.trim() ?? '';
    final isPlaying = _playbackState!.playing;
    final payload = '$title\u0000$artist\u0000$isPlaying';
    if (payload == _lastPayload) return;
    _lastPayload = payload;

    _publishQueue = _publishQueue.then((_) async {
      if (_closed) return;
      await _publisher(title, artist, isPlaying);
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('Theme widget update failed: $error');
    });
  }

  @override
  void onClose() {
    _closed = true;
    unawaited(_mediaItemSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playbackSubscription?.cancel() ?? Future<void>.value());
    _mediaItemSubscription = null;
    _playbackSubscription = null;
    super.onClose();
  }
}
