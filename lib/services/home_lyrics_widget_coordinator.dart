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
  required bool forceReload,
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
/// streams to the UI isolate. The coordinator stays in that isolate, where the
/// existing MainActivity MethodChannel is available, while playback continues
/// in audio_service's background isolate.
class HomeLyricsWidgetCoordinator extends GetxService {
  HomeLyricsWidgetCoordinator({
    required AudioHandler audioHandler,
    Stream<Duration>? positionStream,
    WidgetLyricsLoader? lyricsLoader,
    WidgetLyricsPublisher? widgetPublisher,
    Future<int> Function(String songId)? offsetLoader,
    this.retryDelay = const Duration(seconds: 30),
    this.attemptDelay = const Duration(milliseconds: 500),
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
  final Duration retryDelay;
  final Duration attemptDelay;
  final Map<String, Future<Map<String, dynamic>?>> _inFlight = {};

  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  MediaItem? _activeSong;
  List<TimedLyricLine> _timeline = const [];
  Duration _position = Duration.zero;
  int _offsetMs = 0;
  int _generation = 0;
  int _requestRevision = 0;
  String? _lastPublishedPayload;
  int _lastPublishedIndex = -2;
  Timer? _retryTimer;
  bool _started = false;

  static Future<Map<String, dynamic>?> _defaultLyricsLoader(
    MediaItem song,
    int durationSeconds, {
    required bool forceReload,
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
    return value is num
        ? value.toInt().clamp(-10000, 10000).toInt()
        : 0;
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
      _retryTimer?.cancel();
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
      _retryTimer?.cancel();
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
    final generation = _generation;
    final requestedDuration = durationSeconds != null && durationSeconds > 0
        ? durationSeconds
        : (song.duration?.inSeconds ?? 0);
    final requestKey = '${song.id}#$generation#$requestedDuration';
    final existing = _inFlight[requestKey];
    if (existing != null) return existing;

    final requestRevision = ++_requestRevision;
    final future = _loadWithRetry(
      song,
      requestedDuration,
      generation,
      requestRevision,
      forceReload: forceReload,
    );
    _inFlight[requestKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[requestKey], future)) {
        _inFlight.remove(requestKey);
      }
    });
  }

  Future<Map<String, dynamic>?> _loadWithRetry(
    MediaItem song,
    int durationSeconds,
    int generation,
    int requestRevision, {
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
            Duration(milliseconds: attemptDelay.inMilliseconds * (attempt + 1)),
          );
        }
      }

      if (_activeSong?.id != song.id ||
          generation != _generation ||
          requestRevision != _requestRevision) {
        return result;
      }

      if (_hasSyncedLyrics(result)) {
        _timeline = LyricsTimeline.parse(result!['synced'].toString());
        _offsetMs = await _offsetLoader(song.id);
        if (_activeSong?.id == song.id &&
            generation == _generation &&
            requestRevision == _requestRevision) {
          _retryTimer?.cancel();
          _publishCurrentLine(force: true);
        }
      } else {
        _timeline = const [];
        _publishCurrentLine(force: true);
        _scheduleRetry(song, generation);
      }
      return result;
    } catch (error) {
      printINFO('Automatic widget lyrics lookup failed for ${song.id}: $error');
      if (_activeSong?.id == song.id &&
          generation == _generation &&
          requestRevision == _requestRevision) {
        _timeline = const [];
        _publishCurrentLine(force: true);
        _scheduleRetry(song, generation);
      }
      return null;
    }
  }

  void _scheduleRetry(MediaItem song, int generation) {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () {
      final activeSong = _activeSong;
      if (activeSong?.id == song.id && generation == _generation) {
        unawaited(loadLyricsForSong(activeSong!));
      }
    });
  }

  /// Apply the Player Screen's per-track offset to the widget timeline.
  void updateOffset(String songId, int offsetMs) {
    if (_activeSong?.id != songId) return;
    _offsetMs = offsetMs.clamp(-10000, 10000).toInt();
    _publishCurrentLine(force: true);
  }

  /// Keep manually imported LRC files on the same widget timeline.
  void updateLyricsForActiveSong(
    MediaItem song,
    Map<String, dynamic> lyrics,
  ) {
    if (_activeSong?.id != song.id) return;
    _timeline = _hasSyncedLyrics(lyrics)
        ? LyricsTimeline.parse(lyrics['synced'].toString())
        : const [];
    _publishCurrentLine(force: true);
  }

  static bool _hasSyncedLyrics(Map<String, dynamic>? result) {
    final synced = result?['synced']?.toString().trim() ?? '';
    return synced.isNotEmpty &&
        RegExp(r'\[\d{1,3}:\d{2}(?:\.\d{1,3})?\]').hasMatch(synced);
  }

  void _publishCurrentLine({bool force = false}) {
    if (_activeSong == null) return;
    final adjustedPosition =
        (_position.inMilliseconds - _offsetMs).clamp(0, 1 << 31).toInt();
    final activeIndex =
        LyricsTimeline.activeIndex(_timeline, adjustedPosition);
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
    _retryTimer?.cancel();
    unawaited(_mediaItemSubscription?.cancel() ?? Future<void>.value());
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playbackSubscription?.cancel() ?? Future<void>.value());
    super.onClose();
  }
}
