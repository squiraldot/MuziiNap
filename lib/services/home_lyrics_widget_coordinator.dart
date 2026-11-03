import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../services/constant.dart';
import '../services/synced_lyrics_service.dart';
import '../utils/helper.dart';
import '../utils/lyrics_timeline.dart';

typedef WidgetLyricsLoader = Future<Map<String, dynamic>?> Function(
  MediaItem song,
  int durationSeconds, {
  bool forceReload,
});
typedef WidgetLyricsPublisher = Future<void> Function(
  String previous,
  String current,
  String next,
  int activeIndex,
);

/// Owns synchronized home-widget lyrics for the lifetime of the application.
///
/// AudioService exposes the background AudioHandler's media-item and playback
/// streams to the UI isolate. The coordinator therefore stays in the UI
/// isolate, where the existing MainActivity MethodChannel is available, while
/// playback itself continues in audio_service's background isolate.
class HomeLyricsWidgetCoordinator extends GetxService {
  HomeLyricsWidgetCoordinator({
    required AudioHandler audioHandler,
    Stream<Duration>? positionStream,
    WidgetLyricsLoader? lyricsLoader,
    WidgetLyricsPublisher? widgetPublisher,
    Future<int> Function(String songId)? offsetLoader,
  })  : _audioHandler = audioHandler,
        _positionStream = positionStream ?? AudioService.position,
        _lyricsLoader = lyricsLoader ?? _defaultLyricsLoader,
        _widgetPublisher = widgetPublisher ?? _publishToAndroidWidget,
        _offsetLoader = offsetLoader ?? _loadOffset;

  static const MethodChannel _channel =
      MethodChannel('muziinap/home_lyrics_widget');

  final AudioHandler _audioHandler;
  final Stream<Duration> _positionStream;
  final WidgetLyricsLoader _lyricsLoader;
  final WidgetLyricsPublisher _widgetPublisher;
  final Future<int> Function(String songId) _offsetLoader;
  final Map<String, Future<Map<String, dynamic>?>> _inFlight = {};
  final Map<String, Map<String, dynamic>> _resolved = {};

  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  MediaItem? _activeSong;
  List<TimedLyricLine> _timeline = const [];
  Duration _position = Duration.zero;
  int _offsetMs = 0;
  int _generation = 0;\n  int _requestRevision = 0;
  String? _lastPublishedPayload;
  int _lastPublishedIndex = -2;
  bool _started = false;\n  Timer? _retryTimer;\n  final Duration retryDelay;

  static Future<Map<String, dynamic>?> _defaultLyricsLoader(
    MediaItem song,
    int durationSeconds, {
    bool forceReload = false,
  }) =>
      SyncedLyricsService.getSyncedLyrics(
        song,
        durationSeconds,
        forceReload: forceReload,
      );

  static Future<void> _publishToAndroidWidget(
    String previous,
    String current,
    String next,
    int activeIndex,
  ) async {
    await _channel.invokeMethod<void>('updateLines', <String, Object>{
      'previous': previous,
      'current': current,
      'next': next,
      'activeIndex': activeIndex,
    });
  }

  static Future<int> _loadOffset(String songId) async {
    final box = Hive.box(appPrefsBoxName);
    final value = box.get('lyricsSyncOffset:$songId', defaultValue: 0);
    return value is num ? value.toInt().clamp(-10000, 10000) : 0;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _mediaItemSubscription = _audioHandler.mediaItem.listen(
      _handleMediaItem,
      onError: (Object error) =>
          printINFO('Widget lyrics media-item stream failed: $error'),
    );
    _positionSubscription = _positionStream.listen(
      (position) {
        _position = position;
        _publishCurrentLine();
      },
      onError: (Object error) =>
          printINFO('Widget lyrics position stream failed: $error'),
    );
    _playbackSubscription = _audioHandler.playbackState.listen(
      (state) {
        _position = state.updatePosition;
        _publishCurrentLine();
      },
      onError: (Object error) =>
          printINFO('Widget lyrics playback stream failed: $error'),
    );
  }

  Future<void> _handleMediaItem(MediaItem? song) async {
    if (song == null) {
      _generation++;
      _activeSong = null;
      _timeline = const [];
      _offsetMs = 0;
      _position = Duration.zero;
      _lastPublishedPayload = null;
      _lastPublishedIndex = -2;
      await _publishEmpty();
      return;
    }

    final previousSong = _activeSong;
    if (previousSong?.id != song.id) {
      _generation++;
      _activeSong = song;
      _timeline = const [];
      _offsetMs = 0;
      _position = Duration.zero;
      _lastPublishedPayload = null;
      _lastPublishedIndex = -2;
      await _publishEmpty();
      unawaited(loadLyricsForSong(song));
      return;
    }

    // Some sources publish their duration after the media item is first
    // announced. Retry the same track once usable duration metadata arrives.
    final durationWasMissing =
        (previousSong?.duration ?? Duration.zero) <= Duration.zero;
    _activeSong = song;
    if (durationWasMissing &&
        (song.duration ?? Duration.zero) > Duration.zero &&
        _timeline.isEmpty) {
      unawaited(loadLyricsForSong(song));
    }
  }

  Future<Map<String, dynamic>?> loadLyricsForSong(
    MediaItem song, {
    int? durationSeconds,
    bool forceReload = false,
  }) {
    final existing = _inFlight[song.id];
    if (existing != null) return existing;

    final generation = _generation;
    final duration = durationSeconds ??
        (song.duration?.inSeconds ?? 0);
    final future = _loadWithRetry(
      song,
      duration,
      generation,
      forceReload: forceReload,
    );
    _inFlight[song.id] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[song.id], future)) {
        _inFlight.remove(song.id);
      }
    });
  }

  Future<Map<String, dynamic>?> _loadWithRetry(
    MediaItem song,
    int durationSeconds,
    int generation, {
    required bool forceReload,
  }) async {
    try {
      Map<String, dynamic>? result;
      for (var attempt = 0; attempt < 3; attempt++) {
        result = await _lyricsLoader(
          song,
          durationSeconds,
          forceReload: forceReload || attempt > 0,
        );
        if (_hasSyncedLyrics(result)) break;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
        }
      }

      if (_activeSong?.id != song.id ||\n          generation != _generation ||\n          requestRevision != _requestRevision) {
        return result;
      }

      if (_hasSyncedLyrics(result)) {
        _resolved[song.id] = Map<String, dynamic>.from(result!);
        _timeline = LyricsTimeline.parse(result['synced'].toString());
        _offsetMs = await _offsetLoader(song.id);
        if (_activeSong?.id == song.id &&\n          generation == _generation &&\n          requestRevision == _requestRevision) {
          _publishCurrentLine(force: true);
        }
      } else {
        // Keep the song retryable: a later duration update or a new media-item
        // event can try again. Do not cache an empty/temporary failure here.
        _timeline = const [];
        _publishCurrentLine(force: true);
      }
      return result;
    } catch (error) {
      printINFO('Automatic widget lyrics lookup failed for ${song.id}: $error');
      if (_activeSong?.id == song.id && generation == _generation) {
        _timeline = const [];
        _publishCurrentLine(force: true);
      }
      return null;
    }
  }

  void _scheduleRetry(MediaItem song, int generation) {\n    _retryTimer?.cancel();\n    _retryTimer = Timer(retryDelay, () {\n      final activeSong = _activeSong;\n      if (activeSong?.id == song.id && generation == _generation) {\n        unawaited(loadLyricsForSong(activeSong!));\n      }\n    });\n  }\n\n  static bool _hasSyncedLyrics(Map<String, dynamic>? result) {
    final synced = result?['synced']?.toString().trim() ?? '';
    return synced.isNotEmpty &&
        RegExp(r'\[\d{1,3}:\d{2}(?:\.\d{1,3})?\]').hasMatch(synced);
  }

  void _publishCurrentLine({bool force = false}) {
    if (_activeSong == null) return;
    final activeIndex = LyricsTimeline.activeIndex(
      _timeline,
      (_position.inMilliseconds - _offsetMs).clamp(
        0,
        _activeSong?.duration?.inMilliseconds ?? 0,
      ).toInt(),
    );
    final previous =
        activeIndex > 0 ? _timeline[activeIndex - 1].text : '';
    final current = activeIndex >= 0 && activeIndex < _timeline.length
        ? _timeline[activeIndex].text
        : '';
    final next = activeIndex >= 0 && activeIndex + 1 < _timeline.length
        ? _timeline[activeIndex + 1].text
        : '';
    final payload = '${previous}\u0000${current}\u0000${next}';
    if (!force &&
        payload == _lastPublishedPayload &&
        activeIndex == _lastPublishedIndex) {
      return;
    }
    _lastPublishedPayload = payload;
    _lastPublishedIndex = activeIndex;
    unawaited(_widgetPublisher(previous, current, next, activeIndex).catchError(
      (Object error) =>
          printINFO('Home-screen lyrics widget update failed: $error'),
    ));
  }

  Future<void> _publishEmpty() async {
    _lastPublishedPayload = '\u0000\u0000';
    _lastPublishedIndex = -1;
    try {
      await _widgetPublisher('', '', '', -1);
    } catch (error) {
      printINFO('Unable to clear home-screen lyrics widget: $error');
    }
  }

  @override
  void onClose() {
    unawaited(_mediaItemSubscription?.cancel() ?? Future<void>.value());
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playbackSubscription?.cancel() ?? Future<void>.value());
    super.onClose();
  }
}
