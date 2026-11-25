import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

@immutable
class ThemeWidgetPlaybackSnapshot {
  const ThemeWidgetPlaybackSnapshot({
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.revision,
  });

  final String title;
  final String artist;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final bool shuffleEnabled;
  final String repeatMode;
  final int revision;

  Map<String, Object> toChannelArguments() => <String, Object>{
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'shuffleEnabled': shuffleEnabled,
        'repeatMode': repeatMode,
        'revision': revision,
      };
}

typedef ThemeWidgetPublisher = Future<void> Function(
  ThemeWidgetPlaybackSnapshot snapshot,
);

/// Publishes AudioHandler state only. Album art is deliberately never read or sent.
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
  int _revision = 0;
  bool _started = false;
  bool _closed = false;

  static Future<void> _publishToAndroidWidget(
    ThemeWidgetPlaybackSnapshot snapshot,
  ) {
    return _channel.invokeMethod<void>(
      'updatePlayback',
      snapshot.toChannelArguments(),
    );
  }

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    _revision = DateTime.now().microsecondsSinceEpoch;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetActionAvailable') {
        await _applyWidgetAction(call.arguments as String?);
      }
    });
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
    unawaited(_consumePendingWidgetAction());
  }

  Future<void> _consumePendingWidgetAction() async {
    try {
      final command = await _channel.invokeMethod<String>('consumePendingWidgetAction');
      await _applyWidgetAction(command);
    } on PlatformException catch (error) {
      debugPrint('Could not consume native widget command: ${error.message}');
    } on MissingPluginException {
      // Theme music widgets are Android-only; other platforms have no native bridge.
    }
  }

  Future<void> _applyWidgetAction(String? command) async {
    if (command != 'shuffle' && command != 'repeat') return;
    try {
      final playback = _playbackState ??
          await _audioHandler.playbackState.first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => PlaybackState(),
          );
      if (command == 'shuffle') {
        final enabled = playback.shuffleMode != AudioServiceShuffleMode.none;
        await _audioHandler.setShuffleMode(
          enabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
        );
      } else {
        final next = switch (playback.repeatMode) {
          AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
          AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
          _ => AudioServiceRepeatMode.none,
        };
        await _audioHandler.setRepeatMode(next);
      }
    } catch (error) {
      debugPrint('Could not apply native widget command: $error');
    }
  }

  void _publish() {
    final playback = _playbackState;
    if (_closed || playback == null) return;
    final item = _mediaItem;
    final title = item?.title.trim().isNotEmpty == true
        ? item!.title.trim()
        : 'Nothing playing';
    final artist = item?.artist?.trim() ?? '';
    final durationMs = item?.duration?.inMilliseconds ?? 0;
    final positionMs = playback.updatePosition.inMilliseconds
        .clamp(0, durationMs > 0 ? durationMs : 0x7fffffffffffffff)
        .toInt();
    final shuffleEnabled =
        playback.shuffleMode != AudioServiceShuffleMode.none;
    final repeatMode = switch (playback.repeatMode) {
      AudioServiceRepeatMode.one => 'ONE',
      AudioServiceRepeatMode.all => 'ALL',
      _ => 'OFF',
    };
    final payload = [
      title,
      artist,
      playback.playing,
      positionMs,
      durationMs,
      shuffleEnabled,
      repeatMode,
    ].join('\u0000');
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    final snapshot = ThemeWidgetPlaybackSnapshot(
      title: title,
      artist: artist,
      isPlaying: playback.playing,
      positionMs: positionMs,
      durationMs: durationMs,
      shuffleEnabled: shuffleEnabled,
      repeatMode: repeatMode,
      revision: ++_revision,
    );

    _publishQueue = _publishQueue.then((_) async {
      if (_closed) return;
      await _publisher(snapshot);
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
