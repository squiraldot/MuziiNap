import 'dart:async';
import './constant.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';


import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';

import '../models/album.dart';
import '../models/playlist.dart';
import './equalizer.dart';
import './stream_service.dart';
import './device_adaptive_stream_selector.dart';
import './playback_circuit_breaker.dart';
import './music_service.dart';
import './innertube_session_manager.dart';
import './audio_cache_manager.dart';
import '../models/hm_streaming_data.dart';
import '../models/equalizer.dart';
import '../ui/player/player_controller.dart';
import '../ui/screens/Home/home_screen_controller.dart';
import './background_task.dart';
import './permission_service.dart';
import '../utils/helper.dart';
import '../models/media_Item_builder.dart';
import './utils.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../utils/home_history.dart';
import '../ui/screens/Library/library_controller.dart';

Future<AudioHandler> initAudioService() async {
  // Configure the shared Android audio session before AudioService creates
  // the player, so the first play request cannot race session initialization.
  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  } catch (error) {
    printINFO("Unable to configure music audio session: $error");
  }
  // Resolve device/network capabilities before the native player is created;
  // just_audio serializes AndroidLoadControl into the platform creation call.
  final deviceProfile = await DeviceAdaptiveStreamSelector().detect();
  return await AudioService.init(
    builder: () => MyAudioHandler(deviceProfile: deviceProfile),
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.mycompany.myapp.audio',
      androidNotificationChannelName: 'MuziiNap Notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with GetxServiceMixin {
  final DeviceStreamProfile _deviceStreamProfile;

  // ignore: prefer_typing_uninitialized_variables
  late final String _cacheDir;
  late final Future<void> _cacheDirReady;
  late AudioPlayer _player;
  late PlaybackCircuitBreaker _playbackCircuitBreaker;
  late MediaLibrary _mediaLibrary;
  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;
  String? currentSongUrl;
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = false;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;
  // Serialize audio-setting mutations so startup restoration and rapid user
  // toggles cannot complete out of order and overwrite each other.
  Future<void> _audioSettingsQueue = Future<void>.value();
  Future<void> _audioCacheTrimQueue = Future<void>.value();
  bool _backgroundResourcesReleased = false;
  Duration? _backgroundReleasedPosition;
  String? _lastCacheCleanupSongId;
  bool isSongLoading = true;
  int _playSessionId = 0;
  String? _playbackRecoverySongId;
  int? _activeEqualizerSessionId;
  double _baseOutputVolume = 1.0;
  bool _audioFocusDucked = false;
  int _volumeFadeGeneration = 0;
  int _manualPauseGeneration = 0;
  bool _isPlaybackRequested = false;
  Duration? _pendingPlaybackPosition;

  // One in-flight/ready stream lookup for the next queue item. Futures are
  // keyed by video ID so a rapid skip can safely reuse a completed lookup.
  final Map<String, Future<HMStreamingData>> _streamPrefetches = {};
  String? _autoAdvanceSongId;

  // Retain every player subscription so the app-scoped owner can cancel it.
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  EqualizerConfig _equalizerConfig = EqualizerConfig.graphic10Band();

  // list of shuffled queue songs ids
  List<String> shuffledQueue = [];

  MyAudioHandler({required DeviceStreamProfile deviceProfile})
      : _deviceStreamProfile = deviceProfile {
    _mediaLibrary = MediaLibrary();
    _player = AudioPlayer(
      // AudioPlaybackService owns the focus policy; disable just_audio's
      // built-in auto-duck/resume listeners to avoid double handling.
      handleInterruptions: false,
      useProxyForRequestHeaders: false,
      audioLoadConfiguration: AudioLoadConfiguration(
        androidLoadControl: _deviceStreamProfile.androidLoadControl,
      ),
    );
    final connectivity = Connectivity();
    _playbackCircuitBreaker = PlaybackCircuitBreaker(
      processingStateStream: _player.processingStateStream,
      playingStream: _player.playingStream,
      onlineStream: connectivity.onConnectivityChanged.map(_hasNetworkConnection),
      loadingIntentStream: playbackState.map((state) =>
          state.processingState == AudioProcessingState.loading ||
          state.processingState == AudioProcessingState.buffering),
      shouldMonitorPlayback: _shouldMonitorNetworkPlayback,
      checkOnline: () async => _hasNetworkConnection(await connectivity.checkConnectivity()),
      positionProvider: () => _player.playing ||
              _player.processingState == ProcessingState.buffering
          ? _player.position
          : (_pendingPlaybackPosition ?? _player.position),
      onFrozen: _recoverFrozenPlayback,
      onRetriesExhausted: _failFrozenPlayback,
    );
    unawaited(_playbackCircuitBreaker.start());
    _cacheDirReady = _createCacheDir();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    _listenForSequenceStateChanges();
    final appPrefsBox = Hive.box(appPrefsBoxName);
    _applyInitialSkipSilenceSetting(
      appPrefsBox.get("skipSilenceEnabled") ?? false,
    );
    loopModeEnabled = appPrefsBox.get("isLoopModeEnabled") ?? false;
    shuffleModeEnabled = appPrefsBox.get("isShuffleModeEnabled") ?? false;
    queueLoopModeEnabled =
        Hive.box(appPrefsBoxName).get("queueLoopModeEnabled") ?? false;
    loudnessNormalizationEnabled =
        appPrefsBox.get("loudnessNormalizationEnabled") ?? false;
    final savedEqualizer = appPrefsBox.get("equalizerConfig");
    if (savedEqualizer is String) {
      try {
        _equalizerConfig = EqualizerConfig.fromJson(
          Map<String, Object?>.from(jsonDecode(savedEqualizer) as Map),
        );
      } catch (_) {
        _equalizerConfig = EqualizerConfig.graphic10Band();
      }
    }
    _listenForDurationChanges();
    if (GetPlatform.isAndroid) {
      _listenSessionIdStream();
    }
  }

  Future<void> _serializeAudioSetting(Future<void> Function() operation) {
    final result = _audioSettingsQueue.then((_) => operation());
    // Keep the queue alive after a platform failure while preserving the
    // original error for the caller that requested this setting change.
    _audioSettingsQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        printERROR("Audio setting update failed: $error");
      },
    );
    return result;
  }

  Future<void> _applyInitialSkipSilenceSetting(bool enabled) async {
    try {
      await _serializeAudioSetting(() => _player.setSkipSilenceEnabled(enabled));
    } catch (e) {
      printERROR("Failed to restore skip-silence setting: $e");
    }
  }

  Future<void> _createCacheDir() async {
    _cacheDir = (await getTemporaryDirectory()).path;
    await Directory('$_cacheDir/cachedSongs').create(recursive: true);
  }

  /// Applies the user's output level while respecting temporary audio-focus
  /// ducking. The base level is never overwritten by an interruption.
  Future<void> _applyOutputVolume({bool smooth = false}) async {
    final target = (_baseOutputVolume * (_audioFocusDucked ? 0.2 : 1.0))
        .clamp(0.0, 1.0)
        .toDouble();
    final start = _player.volume;
    final generation = ++_volumeFadeGeneration;
    if (!smooth || (target - start).abs() < 0.001) {
      await _player.setVolume(target);
      return;
    }

    // Five short linear steps provide a brief fade without introducing a
    // timer that can outlive the app-scoped player.
    for (var step = 1; step <= 5; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (generation != _volumeFadeGeneration) return;
      final next = start + ((target - start) * step / 5);
      await _player.setVolume(next.clamp(0.0, 1.0).toDouble());
    }
  }

  Future<void> _setBaseOutputVolume(double volume) async {
    _baseOutputVolume = volume.clamp(0.0, 1.0).toDouble();
    await _applyOutputVolume(smooth: _audioFocusDucked);
  }

  Future<void> _duckForAudioFocus() async {
    if (_audioFocusDucked) return;
    _audioFocusDucked = true;
    await _applyOutputVolume(smooth: true);
  }

  Future<void> _restoreAfterAudioFocus() async {
    if (!_audioFocusDucked) return;
    _audioFocusDucked = false;
    await _applyOutputVolume(smooth: true);
  }

  Future<void> _pauseForAudioFocus() async {
    _manualPauseGeneration++;
    _isPlaybackRequested = false;
    _audioFocusDucked = false;
    await _applyOutputVolume(smooth: true);
    await _player.pause();
  }

  Future<void> _pauseForBecomingNoisy() async {
    _manualPauseGeneration++;
    _isPlaybackRequested = false;
    // Do not fade first: route removal should stop output immediately.
    _audioFocusDucked = false;
    _volumeFadeGeneration++;
    await _player.pause();
    await _player.setVolume(_baseOutputVolume);
  }

  /// Run cache cleanup serially so rapid skips cannot race file deletion.
  /// Files for every item still in the playback queue are protected because
  /// LockCachingAudioSource may still be downloading their .part files.
  void _scheduleAudioCacheTrim() {
    _audioCacheTrimQueue = _audioCacheTrimQueue.then((_) async {
      await _cacheDirReady;
      final protectedIds = queue.value.map((item) => item.id).toSet();
      // The currently audible item may temporarily be removed from the
      // editable queue. Keep its cache file protected until playback changes.
      final activeSongId = mediaItem.value?.id;
      if (activeSongId != null) protectedIds.add(activeSongId);
      final result = await AudioCacheManager.trimDirectory(
        Directory('$_cacheDir/cachedSongs'),
        protectedSongIds: protectedIds,
      );
      if (!result.withinLimit) {
        printINFO(
          'Audio cache remains above 100 MB because protected playback-queue files use ${result.totalBytes} bytes.',
        );
      }
    }).catchError((Object error, StackTrace stackTrace) {
      printERROR('Audio cache cleanup failed: $error');
    });
  }

  /// Release native decoders/resources for a paused source when the app leaves
  /// the foreground. just_audio has no public decoder-buffer-pool flush API;
  /// stop() is the supported resource-release operation. The Dart source is
  /// retained for reliable resume, using the saved position when Play is tapped.
  Future<void> releasePausedPlaybackResources() async {
    final index = currentIndex;
    if (_backgroundResourcesReleased ||
        _player.playing ||
        _player.processingState != ProcessingState.ready ||
        index is! int ||
        index < 0 ||
        index >= queue.value.length) {
      return;
    }

    _backgroundReleasedPosition = _player.position;
    _backgroundResourcesReleased = true;
    await _player.stop();

    final sessionId = _activeEqualizerSessionId;
    if (sessionId != null) {
      EqualizerService.endAudioEffect(sessionId);
      _activeEqualizerSessionId = null;
    }
    _scheduleAudioCacheTrim();
  }

  void _listenSessionIdStream() {
    _playerSubscriptions.add(_player.androidAudioSessionIdStream.listen((int? id) {
      if (id == null || id <= 0) return;

      final previousSessionId = _activeEqualizerSessionId;
      if (previousSessionId != null && previousSessionId != id) {
        EqualizerService.endAudioEffect(previousSessionId);
      }

      _activeEqualizerSessionId = id;
      // Keep session changes lightweight. DynamicsProcessing is initialized only
      // after playback starts so it cannot block startup or first-track loading.
      EqualizerService.initAudioEffect(id);
    }));
  }

  void _applyEqualizerAfterPlaybackStarts() {
    if (!GetPlatform.isAndroid) return;
    final sessionId = _activeEqualizerSessionId;
    if (sessionId == null || sessionId <= 0) return;

    // Give just_audio/ExoPlayer one event-loop turn to start native playback
    // before the synchronous JNI effect construction.
    Future<void>.delayed(Duration.zero, () {
      try {
        EqualizerService.applyConfig(sessionId, _equalizerConfig);
      } catch (e) {
        printINFO("Unable to apply equalizer without delaying playback: $e");
      }
    });
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _playerSubscriptions.add(_player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          // Use a custom close action so Android shows an X instead of the
          // default square stop glyph. The action also hides the in-app panel.
          MediaControl.custom(
            androidIcon: 'drawable/ic_close_24',
            label: 'Close player',
            name: 'dismiss_player',
          ),
        ],
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isSongLoading
            ? AudioProcessingState.loading
            : const {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[_player.processingState]!,
        repeatMode: const {
          LoopMode.off: AudioServiceRepeatMode.none,
          LoopMode.one: AudioServiceRepeatMode.one,
          LoopMode.all: AudioServiceRepeatMode.all,
        }[_player.loopMode]!,
        shuffleMode: (shuffleModeEnabled)
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: currentIndex,
      ));
    }, onError: (Object e, StackTrace st) async {
      if (e is PlayerException) {
        printERROR('Playback source error ${e.code}: ${e.message}');
      } else {
        printERROR('Playback stream error: $e');
      }
      await _recoverFromPlaybackError(e);
    }));
  }

  bool _shouldMonitorNetworkPlayback() {
    if (!_isPlaybackRequested || isPlayingUsingLockCachingSource) return false;
    final index = currentIndex;
    if (index is int && index >= 0 && index < queue.value.length) {
      final url = currentSongUrl ?? queue.value[index].extras?['url']?.toString();
      if (url != null && url.startsWith('file://')) return false;
    }
    return true;
  }

  static bool _hasNetworkConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  Future<void> _failFrozenPlayback() async {
    _playSessionId++;
    _isPlaybackRequested = false;
    _pendingPlaybackPosition = null;
    await _player.stop();
    _markPlaybackFailed(
      StateError('Playback stream remained frozen after two recovery attempts.'),
    );
  }

  /// Replaces a stream pipe that stopped making progress without emitting an error.
  Future<void> _recoverFrozenPlayback(Duration cachedPosition, int retryNumber) async {
    final index = currentIndex;
    if (index is! int || index < 0 || index >= queue.value.length ||
        (!_player.playing && !_isPlaybackRequested) ||
        isPlayingUsingLockCachingSource) {
      return;
    }
    final song = queue.value[index];
    if (mediaItem.value?.id != song.id) return;
    final currentUrl = currentSongUrl ?? song.extras?['url']?.toString();
    if (currentUrl != null && currentUrl.startsWith('file://')) return;
    final session = _playSessionId;
    final pauseGeneration = _manualPauseGeneration;
    printINFO('Playback pipe frozen for ${song.id}; recovery ${retryNumber}/2');
    await _player.stop();
    if (session != _playSessionId ||
        currentIndex != index ||
        mediaItem.value?.id != song.id) {
      return;
    }
    if (pauseGeneration != _manualPauseGeneration) {
      isSongLoading = false;
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.ready,
        updatePosition: cachedPosition,
      ));
      return;
    }
    currentSongUrl = null;
    final extras = song.extras;
    extras?.remove('url');
    extras?.remove('streamHeaders');
    isSongLoading = true;
    // Existing newUrl flow bypasses cache and promotes the ANDROID client;
    // legacy devices retain their WEB_REMIX compatibility policy.
    unawaited(customAction('playByIndex', {
      'index': index,
      'newUrl': true,
      'position': cachedPosition.inMilliseconds,
      'recoveryPauseGeneration': pauseGeneration,
    }).catchError((Object error, StackTrace stackTrace) {
      _markPlaybackFailed(error);
    }));
  }

  Future<void> _recoverFromPlaybackError(Object error) async {
    final index = currentIndex;
    if (index is! int || index < 0 || index >= queue.value.length) {
      _markPlaybackFailed(error);
      return;
    }

    final song = queue.value[index];
    if (_playbackRecoverySongId == song.id) {
      // Ignore duplicate error notifications while the single URL refresh is
      // still loading. Once loading has ended, this is a genuine retry failure.
      if (!isSongLoading) _markPlaybackFailed(error);
      return;
    }

    _playbackRecoverySongId = song.id;
    final position = _player.position;
    final forceCompatibleAudio =
        DeviceAdaptiveStreamSelector.isDecoderCompatibilityFailure(error);
    try {
      await _player.stop();

      if (isPlayingUsingLockCachingSource &&
          error.toString().contains("Connection closed while receiving data")) {
        await _player.seek(position, index: 0);
        await _player.play();
        return;
      }

      // Regenerate an expired/blocked URL once. Do not await customAction:
      // its play() future completes only when playback ends.
      unawaited(
        customAction("playByIndex", {
          'index': index,
          'newUrl': true,
          'position': position.inMilliseconds,
          'forceCompatibleAudio': forceCompatibleAudio,
        }).catchError((Object retryError, StackTrace stackTrace) {
          _markPlaybackFailed(retryError);
        }),
      );
    } catch (retryError) {
      _markPlaybackFailed(retryError);
    }
  }

  void _markPlaybackFailed(Object error) {
    _isPlaybackRequested = false;
    _pendingPlaybackPosition = null;
    currentSongUrl = null;
    isSongLoading = false;
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.error,
      errorCode: 500,
      errorMessage: error.toString(),
    ));
    try {
      if (Get.context != null) {
        Get.find<PlayerController>().notifyPlayError("networkError");
      }
    } catch (notifyError) {
      printERROR("Unable to show playback error: $notifyError");
    }
  }

  /// Pure threshold policy exposed for deterministic unit tests.
  static bool shouldPrefetchNextTrack(
    Duration position,
    Duration? duration,
  ) {
    if (duration == null || duration.inMilliseconds <= 0) return false;
    if (position.isNegative) return false;
    return position.inMilliseconds * 100 >= duration.inMilliseconds * 80;
  }

  int? _peekNextSongIndex() {
    final items = queue.value;
    final index = currentIndex;
    if (index is! int || index < 0 || index >= items.length) return null;

    if (shuffleModeEnabled) {
      final nextShuffleIndex = currentShuffleIndex + 1;
      if (nextShuffleIndex >= shuffledQueue.length) return null;
      final nextId = shuffledQueue[nextShuffleIndex];
      final nextIndex = items.indexWhere((item) => item.id == nextId);
      return nextIndex >= 0 ? nextIndex : null;
    }

    if (index + 1 < items.length) return index + 1;
    if (queueLoopModeEnabled && items.length > 1) return 0;
    return null;
  }

  void _prefetchNextSong() {
    final nextIndex = _peekNextSongIndex();
    if (nextIndex == null) return;

    final nextSong = queue.value[nextIndex];
    if (nextSong.id == mediaItem.value?.id ||
        _streamPrefetches.containsKey(nextSong.id)) {
      return;
    }

    // Keep at most one retained prefetch. Removing a Future does not pretend
    // to cancel the underlying HTTP request, but it releases our reference and
    // prevents stale results from being consumed by a later queue selection.
    _streamPrefetches.removeWhere((songId, _) => songId != nextSong.id);

    final future = checkNGetUrl(nextSong.id);
    _streamPrefetches[nextSong.id] = future;
    unawaited(future.then<void>(
      (result) {
        if (!result.playable &&
            identical(_streamPrefetches[nextSong.id], future)) {
          _streamPrefetches.remove(nextSong.id);
          printINFO("Next-track prefetch was not playable: ${nextSong.id}");
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_streamPrefetches[nextSong.id], future)) {
          _streamPrefetches.remove(nextSong.id);
        }
        printINFO("Next-track prefetch failed for ${nextSong.id}: $error");
      },
    ));
  }

  Future<HMStreamingData> _resolveStreamInfo(
    String songId, {
    bool generateNewUrl = false,
  }) {
    if (!generateNewUrl) {
      final prefetched = _streamPrefetches.remove(songId);
      if (prefetched != null) return prefetched;
    }
    return checkNGetUrl(songId, generateNewUrl: generateNewUrl);
  }

  void _listenToPlaybackForNextSong() {
    _playerSubscriptions.add(_player.positionStream.listen((position) {
      final duration = _player.duration;
      if (shouldPrefetchNextTrack(position, duration)) {
        _prefetchNextSong();
      }

      final currentId = mediaItem.value?.id;
      if (duration != null &&
          duration > Duration.zero &&
          position < duration &&
          currentId != null &&
          _autoAdvanceSongId == currentId) {
        _autoAdvanceSongId = null;
      }
      if (duration != null &&
          duration > Duration.zero &&
          position >= duration &&
          currentId != null &&
          _autoAdvanceSongId != currentId) {
        _autoAdvanceSongId = currentId;
        unawaited(_triggerNext());
      }
    }));
  }

  Future<void> _triggerNext() async {
    if (loopModeEnabled) {
      await _player.seek(Duration.zero);
      if (!_player.playing) {
        await _player.play();
      }
      return;
    }
    skipToNext();
  }

  void _listenForSequenceStateChanges() {
    _playerSubscriptions.add(
      _player.sequenceStateStream.listen((SequenceState? sequenceState) {
        final sequence = sequenceState?.effectiveSequence;
        if (sequence == null || sequence.isEmpty) return;

        // A new source/current queue index means the user changed tracks.
        // Run disk GC here, after just_audio has switched away from the old
        // source, while preserving every song still in the playback queue.
        final index = currentIndex;
        if (index is int && index >= 0 && index < queue.value.length) {
          final songId = queue.value[index].id;
          if (songId != _lastCacheCleanupSongId) {
            _lastCacheCleanupSongId = songId;
            _scheduleAudioCacheTrim();
          }
        }
      }),
    );
  }

  void _listenForDurationChanges() {
    _playerSubscriptions.add(_player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (currentIndex == null || currQueue.isEmpty || duration == null) return;
      final currentSong = queue.value[currentIndex];
      if (currentSong.duration == null || currentIndex == 0) {
        final newMediaItem = currentSong.copyWith(duration: duration);
        mediaItem.add(newMediaItem);
      }
    }));
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    // notify system
    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);

    if (shuffleModeEnabled) {
      final mediaItemsIds = mediaItems.toList().map((item) => item.id).toList();
      final notPlayedshuffledQueue = shuffledQueue.isNotEmpty
          ? shuffledQueue.toList().sublist(currentShuffleIndex + 1)
          : shuffledQueue;
      notPlayedshuffledQueue.addAll(mediaItemsIds);
      notPlayedshuffledQueue.shuffle();
      shuffledQueue.replaceRange(
          currentShuffleIndex, shuffledQueue.length, notPlayedshuffledQueue);
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    final newQueue = this.queue.value
      ..replaceRange(0, this.queue.value.length, queue);
    this.queue.add(newQueue);
    _scheduleAudioCacheTrim();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (shuffleModeEnabled) {
      shuffledQueue.add(mediaItem.id);
    }

    // notify system
    final newQueue = queue.value..add(mediaItem);
    queue.add(newQueue);
  }

  Future<AudioSource> _createAudioSource(MediaItem mediaItem) async {
    await _cacheDirReady;
    final originalUrl = mediaItem.extras!['url'] as String;
    final streamHeaders =
        (mediaItem.extras!['streamHeaders'] as Map?)?.cast<String, String>();

    // Android uses native request headers for the stream URL.
    final url = originalUrl;

    if (originalUrl.contains('/cache') ||
        (Get.find<SettingsScreenController>().cacheSongs.isTrue &&
            url.contains("http"))) {
      printINFO("Playing Using LockCaching");
      isPlayingUsingLockCachingSource = true;
      // ignore: experimental_member_use
      return LockCachingAudioSource(
        Uri.parse(url),
        headers: streamHeaders,
        cacheFile: File("$_cacheDir/cachedSongs/${mediaItem.id}.mp3"),
        tag: mediaItem,
      );
    }

    printINFO("Playing Using AudioSource.uri");
    isPlayingUsingLockCachingSource = false;
    
    // If it's a local file path, use Uri.file to prevent spaces from being converted to %20
    final uri = url.startsWith('http') 
        ? Uri.tryParse(url)! 
        : (url.startsWith('file://') ? Uri.parse(url) : Uri.file(url));

    return AudioSource.uri(
      uri,
      headers: streamHeaders,
      tag: mediaItem,
    );
  }

  @override
  // ignore: avoid_renaming_method_parameters
  Future<void> removeQueueItem(MediaItem mediaItem_) async {
    if (shuffleModeEnabled) {
      final id = mediaItem_.id;
      final itemIndex = shuffledQueue.indexOf(id);
      if (currentShuffleIndex > itemIndex) {
        currentShuffleIndex -= 1;
      }
      shuffledQueue.remove(id);
    }

    final currentQueue = queue.value;
    final currentSong = mediaItem.value;
    final itemIndex = currentQueue.indexOf(mediaItem_);
    if (currentIndex > itemIndex) {
      currentIndex -= 1;
    }
    currentQueue.remove(mediaItem_);
    queue.add(currentQueue);
    mediaItem.add(currentSong);
    _scheduleAudioCacheTrim();
  }

  @override
  Future<void> play() async {
    _isPlaybackRequested = true;
    if (_backgroundResourcesReleased) {
      final resumePosition = _backgroundReleasedPosition;
      _backgroundResourcesReleased = false;
      _backgroundReleasedPosition = null;
      // just_audio.stop() retains the source but releases native decoders.
      // Restore the exact position and reactivate that source without
      // re-resolving the YouTube URL or downloading it a second time.
      if (resumePosition != null) {
        await _player.seek(resumePosition);
      }
      await _player.play();
      return;
    }
    if (currentSongUrl == null) {
      await customAction("playByIndex", {'index': currentIndex});
      return;
    }
    // Workaround for network error pause in case of PlayingUsingLockCachingSource
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _manualPauseGeneration++;
    _isPlaybackRequested = false;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await customAction("playByIndex", {'index': index});
  }

  int _getNextSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex + 1 >= shuffledQueue.length) {
        shuffledQueue.shuffle();
        currentShuffleIndex = 0;
      } else {
        currentShuffleIndex += 1;
      }
      return queue.value
          .indexWhere((item) => item.id == shuffledQueue[currentShuffleIndex]);
    }

    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else if (queueLoopModeEnabled) {
      return 0;
    } else {
      return currentIndex;
    }
  }

  int _getPrevSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex - 1 < 0) {
        shuffledQueue.shuffle();
        currentShuffleIndex = shuffledQueue.length - 1;
      } else {
        currentShuffleIndex -= 1;
      }
      return queue.value
          .indexWhere((item) => item.id == shuffledQueue[currentShuffleIndex]);
    }

    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
    } else {
      return currentIndex;
    }
  }

  @override
  Future<void> skipToNext() async {
    final index = _getNextSongIndex();
    if (index != currentIndex) {
      if (_player.position != Duration.zero) _player.seek(Duration.zero);
      await customAction("playByIndex", {'index': index});
    } else {
      _player.seek(Duration.zero);
      _player.pause();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inMilliseconds > 5000) {
      _player.seek(Duration.zero);
      return;
    }
    _player.seek(Duration.zero);
    final index = _getPrevSongIndex();
    if (index != currentIndex) {
      await customAction("playByIndex", {'index': index});
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    if (repeatMode == AudioServiceRepeatMode.none) {
      loopModeEnabled = false;
    } else {
      loopModeEnabled = true;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      shuffleModeEnabled = false;
      shuffledQueue.clear();
    } else {
      _shuffleCmd(currentIndex);
      shuffleModeEnabled = true;
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'dismiss_player':
        // Stop clears AudioService metadata; also hide the attached Flutter
        // panel so stopping from the notification cannot reveal Player Screen.
        await stop();
        final playerController = Get.find<PlayerController>();
        playerController.isMiniPlayerDismissed.value = true;
        playerController.isPlayerpanelTopVisible.value = false;
        playerController.playerPaneOpacity.value = 0;
        playerController.isPanelGTHOpened.value = false;
        if (playerController.playerPanelController.isAttached) {
          await playerController.playerPanelController.hide();
        }
        break;

      case 'dispose':
        if (_activeEqualizerSessionId != null) {
          EqualizerService.endAudioEffect(_activeEqualizerSessionId!);
          _activeEqualizerSessionId = null;
        }
        // Cancel all Dart stream listeners before releasing the native player.
        for (final subscription in _playerSubscriptions) {
          await subscription.cancel();
        }
        _playerSubscriptions.clear();
        await _playbackCircuitBreaker.dispose();
        _streamPrefetches.clear();
        _autoAdvanceSongId = null;
        await _player.dispose();
        await super.stop();
        break;

      case 'playByIndex':
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        final isNewUrlReq = extras['newUrl'] ?? false;
        final requestPauseGeneration = extras['recoveryPauseGeneration'] is int
            ? extras['recoveryPauseGeneration'] as int
            : _manualPauseGeneration;
        if (!isNewUrlReq) _playbackRecoverySongId = null;
        final currentSong = queue.value[currentIndex];
        currentSongUrl = null;
        _isPlaybackRequested = extras['restoreSession'] != true;
        final requestedPosition = extras['position'];
        _pendingPlaybackPosition = requestedPosition is int
            ? Duration(milliseconds: requestedPosition)
            : Duration.zero;
        _playbackCircuitBreaker.setTrack(currentSong.id);
        _autoAdvanceSongId = currentSong.id;
        final currentSession = ++_playSessionId;
        isSongLoading = true;
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.loading));
        
        // Stop playing the old song immediately while loading the new one
        await _player.pause();

        // Run metadata publication and InnerTube resolution concurrently.
        // PlayerController's mediaItem listeners can start artwork/palette work
        // while the network/isolate resolver is still running.
        final preparation = Future.wait<dynamic>([
          _resolveStreamInfo(
            currentSong.id,
            generateNewUrl: isNewUrlReq,
          ),
          Future<void>.sync(() => mediaItem.add(currentSong)),
        ]);
        final bool restoreSession = extras['restoreSession'] ?? false;
        HMStreamingData streamInfo;
        try {
          final preparationResults = await preparation;
          streamInfo = preparationResults.first as HMStreamingData;
        } catch (streamError) {
          printERROR(
            "Stream resolution failed for first/current track $songIndex ($currentSong.id): $streamError",
          );
          if (songIndex != currentIndex || currentSession != _playSessionId) {
            return;
          }
          if (!isNewUrlReq) {
            await _recoverFromPlaybackError(streamError);
          } else {
            _markPlaybackFailed(streamError);
          }
          return;
        }
        if (songIndex != currentIndex || currentSession != _playSessionId) {
          return;
        }
        if (extras['forceCompatibleAudio'] == true) {
          // The adaptive resolver retains AAC in the low-quality slot on
          // capable devices. Use it after an actual native decoder failure.
          streamInfo.setQualityIndex(0);
        }
        if (!streamInfo.playable) {
          _isPlaybackRequested = false;
          _pendingPlaybackPosition = null;
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
          playbackState.add(playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorCode: 404,
              errorMessage: streamInfo.statusMSG));
          return;
        }
        currentSongUrl = currentSong.extras!['url'] = streamInfo.audio!.url;
        currentSong.extras!['streamHeaders'] = streamInfo.streamHeaders;
        playbackState
            .add(playbackState.value.copyWith(queueIndex: currentIndex));
        try {
          await _player.setAudioSource(await _createAudioSource(currentSong));
          if (currentSession != _playSessionId) return;
          _backgroundResourcesReleased = false;
          _backgroundReleasedPosition = null;
        } catch (sourceError) {
          // setAudioSource can throw before playbackEventStream emits an
          // error. Refresh the URL once here as well so the first tap is not
          // silently left in a failed/loading state.
          if (isNewUrlReq) {
            _markPlaybackFailed(sourceError);
          } else {
            await _recoverFromPlaybackError(sourceError);
          }
          return;
        }

        isSongLoading = false;
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          await _normalizeVolume(streamInfo.audio!.loudnessDb);
        }
        if (currentSession != _playSessionId) return;

        if (restoreSession) {
            final position = extras['position'];
            await _player.load();
            await _player.seek(
              Duration(
                milliseconds: position,
              ),
            );
            await _player.seek(
              Duration(
                milliseconds: position,
              ),
            );
            _applyEqualizerAfterPlaybackStarts();
        } else {
          final resumePosition = extras['position'];
          if (resumePosition is int && resumePosition > 0) {
            await _player.seek(Duration(milliseconds: resumePosition));
          }
          if (!_isPlaybackRequested ||
              requestPauseGeneration != _manualPauseGeneration) {
            isSongLoading = false;
            _pendingPlaybackPosition = null;
            playbackState.add(playbackState.value.copyWith(
              playing: false,
              processingState: AudioProcessingState.ready,
              updatePosition: _player.position,
            ));
            return;
          }
          final playFuture = _player.play();
          _pendingPlaybackPosition = null;
          _applyEqualizerAfterPlaybackStarts();
          await playFuture;

          final appPrefs = Hive.box(appPrefsBoxName);
          final isYouTubeAuthenticated =
              appPrefs.get('yt_logged_in', defaultValue: false) == true;

          if (isYouTubeAuthenticated) {
            try {
              await Get.find<MusicServices>()
                  .recordYouTubePlayback(currentSong.id);
              if (Get.isRegistered<HomeScreenController>()) {
                await Get.find<HomeScreenController>()
                    .onTrackPlayed(currentSong);
              }
            } catch (e) {
              printINFO("Unable to report YouTube playback: $e");
            }
          } else {
            try {
              await saveRecentlyPlayed(currentSong);
              if (Get.isRegistered<HomeScreenController>()) {
                await Get.find<HomeScreenController>()
                    .onTrackPlayed(currentSong);
              }
            } catch (e) {
              printINFO("Unable to persist local listening history: $e");
            }
          }
        }
        break;

      case 'checkWithCacheDb':
        if (isPlayingUsingLockCachingSource) {
          final song = extras!['mediaItem'] as MediaItem;
          final songsCacheBox = Hive.box("SongsCache");
          if (!songsCacheBox.containsKey(song.id) &&
              await File("$_cacheDir/cachedSongs/${song.id}.mp3").exists()) {
            song.extras!['url'] = currentSongUrl;
            song.extras!['date'] = DateTime.now().millisecondsSinceEpoch;
            final dbStreamData = Hive.box("SongsUrlCache").get(song.id);
            final jsonData = MediaItemBuilder.toJson(song);
            jsonData['duration'] = _player.duration!.inSeconds;
            // playbility status and info
            jsonData['streamInfo'] = dbStreamData != null
                ? [
                    true,
                    dbStreamData[
                        Hive.box(appPrefsBoxName).get('streamingQuality') == 0
                            ? 'lowQualityAudio'
                            : "highQualityAudio"]
                  ]
                : null;
            songsCacheBox.put(song.id, jsonData);
            LibrarySongsController librarySongsController =
                Get.find<LibrarySongsController>();
            if (!librarySongsController.isClosed) {
              librarySongsController.librarySongsList.value =
                  librarySongsController.librarySongsList.toList() + [song];
            }
          }
        }
        break;

      case 'setSourceNPlay':
        final currMed = (extras!['mediaItem'] as MediaItem);
        currentSongUrl = null;
        final sourcePauseGeneration = _manualPauseGeneration;
        _isPlaybackRequested = true;
        _pendingPlaybackPosition = Duration.zero;
        _playbackCircuitBreaker.setTrack(currMed.id);
        _autoAdvanceSongId = currMed.id;
        final currentSession = ++_playSessionId;
        isSongLoading = true;
        currentIndex = 0;
        
        // Stop playing the old song immediately while loading the new one
        await _player.pause();

        // Start UI metadata work and stream resolution in the same turn.
        final preparation = Future.wait<dynamic>([
          _resolveStreamInfo(currMed.id),
          Future<void>.sync(() => mediaItem.add(currMed)),
        ]);
        queue.add([currMed]);
        final preparationResults = await preparation;
        final streamInfo = preparationResults.first as HMStreamingData;
        if (currentSession != _playSessionId) {
          return;
        }
        if (!streamInfo.playable) {
          _isPlaybackRequested = false;
          _pendingPlaybackPosition = null;
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
          playbackState.add(playbackState.value
              .copyWith(processingState: AudioProcessingState.error));
          return;
        }
        currentSongUrl = currMed.extras!['url'] = streamInfo.audio!.url;
        currMed.extras!['streamHeaders'] = streamInfo.streamHeaders;

        await _player.setAudioSource(await _createAudioSource(currMed));
        if (currentSession != _playSessionId) return;
        _backgroundResourcesReleased = false;
        _backgroundReleasedPosition = null;
        isSongLoading = false;

        // Normalize audio
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          await _normalizeVolume(streamInfo.audio!.loudnessDb);
        }
        if (currentSession != _playSessionId) return;

        if (!_isPlaybackRequested ||
            sourcePauseGeneration != _manualPauseGeneration) {
          isSongLoading = false;
          _pendingPlaybackPosition = null;
          playbackState.add(playbackState.value.copyWith(
            playing: false,
            processingState: AudioProcessingState.ready,
            updatePosition: _player.position,
          ));
          return;
        }
        final playFuture = _player.play();
        _pendingPlaybackPosition = null;
        _applyEqualizerAfterPlaybackStarts();
        await playFuture;
        break;

      case 'toggleSkipSilence':
        final enable = (extras!['enable'] as bool);
        await _serializeAudioSetting(
          () => _player.setSkipSilenceEnabled(enable),
        );
        break;

      case 'toggleLoudnessNormalization':
        final enable = (extras!['enable'] as bool);
        await _serializeAudioSetting(() async {
          loudnessNormalizationEnabled = enable;
          if (!enable) {
            await _setBaseOutputVolume(1.0);
            return;
          }

          try {
            if (queue.value.isNotEmpty &&
                currentIndex != null &&
                currentIndex >= 0 &&
                currentIndex < queue.value.length) {
              final currentSongId = queue.value[currentIndex].id;
              if (Hive.box("SongsUrlCache").containsKey(currentSongId)) {
                final songJson = Hive.box("SongsUrlCache").get(currentSongId);
                final loudnessDb =
                    songJson["highQualityAudio"]?["loudnessDb"];
                if (loudnessDb is num) {
                  await _normalizeVolume(loudnessDb.toDouble());
                }
              } else if (Hive.box("SongDownloads").containsKey(currentSongId)) {
                final streamInfo =
                    Hive.box("SongDownloads").get(currentSongId)["streamInfo"];
                final loudnessDb = streamInfo is List && streamInfo.length > 1
                    ? streamInfo[1]["loudnessDb"]
                    : null;
                if (loudnessDb is num) {
                  await _normalizeVolume(loudnessDb.toDouble());
                }
              }
            }
          } catch (e) {
            printERROR(e);
          }
        });
        break;

      case 'shuffleQueue':
        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        currentQueue.remove(currentItem);
        currentQueue.shuffle();
        currentQueue.insert(0, currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        currentIndex = 0;
        break;

      case 'reorderQueue':
        final oldIndex = extras!['oldIndex'];
        int newIndex = extras['newIndex'];

        if (oldIndex < newIndex) {
          newIndex--;
        }

        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        final item = currentQueue.removeAt(
          oldIndex,
        );
        currentQueue.insert(newIndex, item);
        currentIndex = currentQueue.indexOf(currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        break;

      case 'addPlayNextItem':
        final song = extras!['mediaItem'] as MediaItem;
        final currentQueue = queue.value;
        currentQueue.insert(currentIndex + 1, song);
        queue.add(currentQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.insert(currentShuffleIndex + 1, song.id);
        }
        break;

      case 'applyEqualizerConfig':
        final configJson = extras?['config'];
        if (configJson is Map) {
          final config = EqualizerConfig.fromJson(
            Map<String, Object?>.from(configJson),
          );
          final sessionId = _activeEqualizerSessionId;
          if (sessionId != null) {
            EqualizerService.applyConfig(sessionId, config);
          }
        }
        break;

      case 'openEqualizer':
        final sessionId = _player.androidAudioSessionId;
        if (sessionId != null) {
          EqualizerService.openEqualizer(sessionId);
        }
        break;

      case 'setEqualizerConfig':
        final rawConfig = extras?['config'];
        if (rawConfig is Map) {
          try {
            _equalizerConfig = EqualizerConfig.fromJson(
              Map<String, Object?>.from(rawConfig),
            );
            await Hive.box(appPrefsBoxName).put(
              "equalizerConfig",
              jsonEncode(_equalizerConfig.toJson()),
            );
            final sessionId = _player.androidAudioSessionId;
            if (sessionId != null) {
              EqualizerService.applyConfig(sessionId, _equalizerConfig);
            }
          } catch (e) {
            printERROR("Invalid equalizer config: $e");
          }
        }
        break;

      case 'resetEqualizer':
        _equalizerConfig = EqualizerConfig.graphic10Band();
        await Hive.box(appPrefsBoxName).put(
          "equalizerConfig",
          jsonEncode(_equalizerConfig.toJson()),
        );
        final sessionId = _player.androidAudioSessionId;
        if (sessionId != null) {
          EqualizerService.applyConfig(sessionId, _equalizerConfig);
        }
        break;

      case 'saveSession':
        await saveSessionData();
        break;

      case 'releasePausedResources':
        await releasePausedPlaybackResources();
        break;

      case 'setVolume':
        final rawValue = extras!['value'];
        final value = (rawValue as num).toDouble().clamp(0.0, 100.0);
        await _setBaseOutputVolume(value / 100.0);
        break;

      case 'audioFocusDuck':
        await _duckForAudioFocus();
        break;

      case 'audioFocusRestore':
        await _restoreAfterAudioFocus();
        break;

      case 'audioFocusPause':
        await _pauseForAudioFocus();
        break;

      case 'audioFocusNoisy':
        await _pauseForBecomingNoisy();
        break;

      case 'shuffleCmd':
        final songIndex = extras!['index'];
        _shuffleCmd(songIndex);
        break;

      case 'upadateMediaItemInAudioService':
        //added to update media item from player controller
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        mediaItem.add(queue.value[currentIndex]);
        break;

      case 'toggleQueueLoopMode':
        queueLoopModeEnabled = extras!['enable'];
        break;

      case 'clearQueue':
        customAction("reorderQueue", {'oldIndex': currentIndex, 'newIndex': 0});
        final newQueue = queue.value;
        newQueue.removeRange(1, newQueue.length);
        queue.add(newQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.clear();
          shuffledQueue.add(newQueue[0].id);
          currentShuffleIndex = 0;
        }
        break;
      default:
        break;
    }
  }

  void _shuffleCmd(int index) {
    final queueIds = queue.value.toList().map((item) => item.id).toList();
    final currentSongId = queueIds.removeAt(index);
    queueIds.shuffle();
    queueIds.insert(0, currentSongId);
    shuffledQueue.replaceRange(0, shuffledQueue.length, queueIds);
    currentShuffleIndex = 0;
  }

  Future<void> _normalizeVolume(double currentLoudnessDb) async {
    final loudnessDifference = -5 - currentLoudnessDb;

    // Convert the dB difference to a linear volume multiplier.
    final volumeAdjustment = pow(10.0, loudnessDifference / 20.0);
    printINFO(
        "loudness:$currentLoudnessDb Normalized volume: $volumeAdjustment");
    await _setBaseOutputVolume(volumeAdjustment.toDouble().clamp(0, 1.0));
  }

  Future<void> saveSessionData() async {
    if (Get.find<SettingsScreenController>().restorePlaybackSession.isFalse) {
      return;
    }
    final currQueue = queue.value;
    if (currQueue.isNotEmpty) {
      final queueData =
          currQueue.map((e) => MediaItemBuilder.toJson(e)).toList();
      final currIndex = currentIndex ?? 0;
      final position = _player.position.inMilliseconds;
      final prevSessionData = await Hive.openBox("prevSessionData");
      await prevSessionData.clear();
      await prevSessionData.putAll(
          {"queue": queueData, "position": position, "index": currIndex});
      await prevSessionData.close();
      printINFO("Saved session data");
    }
  }

  /// Android Auto
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    return _mediaLibrary.getByRootId(parentMediaId);
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return Stream.fromFuture(
            _mediaLibrary.getByRootId(parentMediaId).then((items) => items))
        .map((_) => <String, dynamic>{})
        .shareValue();
  }

  // only for Android Auto
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    customEvent.add({
      'eventType': 'playFromMediaId',
      'songId': mediaId,
      'libraryId': extras!['libraryId'],
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    final stopForegroundService =
        Get.find<SettingsScreenController>().stopPlyabackOnSwipeAway.value;
    if (stopForegroundService) {
      await Get.find<HomeScreenController>().cachedHomeScreenData();
      await saveSessionData();
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    // Invalidate any in-flight stream lookup/source setup immediately. Without
    // this, a tap-to-play request can finish after dismissal and start audio
    // (and recreate the Android media notification) after stop() returns.
    _playSessionId++;
    _isPlaybackRequested = false;
    _pendingPlaybackPosition = null;
    _playbackCircuitBreaker.setTrack(null);
    _playbackRecoverySongId = null;
    _streamPrefetches.clear();
    _autoAdvanceSongId = null;
    isSongLoading = false;
    currentSongUrl = null;
    await _player.stop();
    mediaItem.add(null);
    queue.add(<MediaItem>[]);
    _backgroundResourcesReleased = false;
    _backgroundReleasedPosition = null;
    _scheduleAudioCacheTrim();
    playbackState.add(playbackState.value.copyWith(
      controls: const [],
      playing: false,
      processingState: AudioProcessingState.idle,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      queueIndex: null,
    ));
    await super.stop();
  }

// Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(String songId,
      {bool generateNewUrl = false, bool offlineReplacementUrl = false}) async {
    await _cacheDirReady;
    printINFO("Requested id : $songId");
    final songDownloadsBox = Hive.box("SongDownloads");
    if (!offlineReplacementUrl &&
        (await Hive.openBox("SongsCache")).containsKey(songId)) {
      printINFO("Got Song from cachedbox ($songId)");
      // if contains stream Info
      final streamInfo = Hive.box("SongsCache").get(songId)["streamInfo"];
      Audio? cacheAudioPlaceholder;
      if (streamInfo != null && streamInfo.isNotEmpty) {
        streamInfo[1]['url'] = "file://$_cacheDir/cachedSongs/$songId.mp3";
        cacheAudioPlaceholder = Audio.fromJson(streamInfo[1]);
      } else {
        cacheAudioPlaceholder = Audio(
            audioCodec: Codec.mp4a,
            bitrate: 0,
            loudnessDb: 0,
            duration: 0,
            size: 0,
            url: "file://$_cacheDir/cachedSongs/$songId.mp3",
            itag: 0);
      }

      return HMStreamingData(
          playable: true,
          statusMSG: "OK",
          lowQualityAudio: cacheAudioPlaceholder,
          highQualityAudio: cacheAudioPlaceholder);
    } else if (!offlineReplacementUrl && songDownloadsBox.containsKey(songId)) {
      final song = songDownloadsBox.get(songId);
      final streamInfoJson = song["streamInfo"];
      Audio? audio;
      final path = song['url'];
      if (streamInfoJson != null && streamInfoJson.isNotEmpty) {
        audio = Audio.fromJson(streamInfoJson[1]);
      } else {
        audio = Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 0,
            duration: 0,
            loudnessDb: 0,
            url: path,
            size: 0);
      }

      final streamInfo = HMStreamingData(
          playable: true,
          statusMSG: "OK",
          highQualityAudio: audio,
          lowQualityAudio: audio);

      bool fileExists = false;
      if (path.contains(
          "${Get.find<SettingsScreenController>().supportDirPath}/Music")) {
        fileExists = await File(path).exists();
      } else {
        //check file access and if file exist in storage
        final status = await PermissionService.getExtStoragePermission();
        if (status) {
          fileExists = await File(path).exists();
        }
      }

      if (fileExists) {
        return streamInfo;
      }
      
      //in case file doesnot found in storage, song will be played online
      return checkNGetUrl(songId, offlineReplacementUrl: true);
    } else {
      //check if song stream url is cached and allocate url accordingly
      final songsUrlCacheBox = Hive.box("SongsUrlCache");
      final qualityIndex = Hive.box(appPrefsBoxName).get('streamingQuality') ?? 1;
      HMStreamingData? streamInfo;
      // Re-check connectivity for every online resolution, but keep all plugin
      // calls on this root isolate. Cached URLs are profile-specific because
      // a previous network/device profile may have selected a different codec.
      final deviceProfile = await DeviceAdaptiveStreamSelector().detect();
      final deviceProfileJson = deviceProfile.toJson();
      if (songsUrlCacheBox.containsKey(songId) && !generateNewUrl) {
        final streamInfoJson = songsUrlCacheBox.get(songId);
        if (streamInfoJson.runtimeType.toString().contains("Map") &&
            streamInfoJson.containsKey('streamHeaders') &&
            !isExpired(url: (streamInfoJson['lowQualityAudio']['url'])) &&
            streamInfoJson['deviceProfile'] is Map &&
            DeviceStreamProfile.fromJson(
                  Map<String, Object?>.from(streamInfoJson['deviceProfile']),
                ) ==
                deviceProfile) {
          printINFO("Got cached Url ($songId)");
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        }
      }

      if (streamInfo == null) {
        final token = RootIsolateToken.instance;
        Map<String, String>? authenticatedHeaders;
        try {
          authenticatedHeaders = InnerTubeSessionManager()
              .getAuthenticatedHeaders('https://music.youtube.com');
        } on InnerTubeSessionException {
          // Anonymous extraction remains available when no account session exists.
        }
        // A first attempt uses WEB_REMIX. On URL/source refresh, promote
        // ANDROID so the retry changes client context instead of replaying
        // the same failed direct URL.
        final preferredClient = deviceProfile.isLegacyAndroid
            ? 'WEB_REMIX'
            : (generateNewUrl ? 'ANDROID' : 'WEB_REMIX');
        Map<String, dynamic>? streamInfoJson;
        try {
          streamInfoJson = await Isolate.run(
            () => getStreamInfo(
              songId,
              token,
              preferYoutubeExplode: generateNewUrl,
              preferredClient: preferredClient,
              authenticatedHeaders: authenticatedHeaders,
              deviceProfile: deviceProfileJson,
            ),
          );
        } catch (e) {
          printINFO("Isolate error (likely Hot Reload issue): \$e");
          streamInfoJson = await getStreamInfo(
            songId,
            token,
            preferYoutubeExplode: generateNewUrl,
            preferredClient: preferredClient,
            authenticatedHeaders: authenticatedHeaders,
            deviceProfile: deviceProfileJson,
          );
        }
        streamInfo = HMStreamingData.fromJson(streamInfoJson);
        if (streamInfo.playable) songsUrlCacheBox.put(songId, streamInfoJson);
      }

      streamInfo.setQualityIndex(qualityIndex as int);
      return streamInfo;
    }
  }
}

class UrlError extends Error {
  String message() => 'Unable to fetch url';
}


// for Android Auto
class MediaLibrary {
  static const albumsRootId = 'albums';
  static const songsRootId = 'songs';
  static const favoritesRootId = "LIBFAV";
  static const playlistsRootId = 'playlists';

  Future<List<MediaItem>> getByRootId(String id) async {
    switch (id) {
      case AudioService.browsableRootId:
        return Future.value(getRoot());
      case songsRootId:
        return getLibSongs("SongDownloads");
      case favoritesRootId:
        return getLibSongs("LIBFAV");
      case albumsRootId:
        return getAlbums();
      case playlistsRootId:
        return getPlaylists();
      case AudioService.recentRootId:
        return getLibSongs("LIBRP");
      default:
        return getLibSongs(id);
    }
  }

  List<MediaItem> getRoot() {
    return [
      MediaItem(
        id: songsRootId,
        title: "songs".tr,
        playable: false,
      ),
      MediaItem(
        id: favoritesRootId,
        title: "favorites".tr,
        playable: false,
      ),
      MediaItem(
        id: albumsRootId,
        title: "albums".tr,
        playable: false,
      ),
      MediaItem(
        id: playlistsRootId,
        title: "playlists".tr,
        playable: false,
      ),
    ];
  }

  Future<List<MediaItem>> getAlbums() async {
    final box = await Hive.openBox("LibraryAlbums");
    final albums =
        box.values.map((item) => Album.fromJson(item).toMediaItem()).toList();
    await box.close();
    return albums;
  }

  Future<List<MediaItem>> getPlaylists() async {
    final box = await Hive.openBox("LibraryPlaylists");
    final playlists = [
      ...LibraryPlaylistsController.initPlst.map((e) => e.toMediaItem()),
      ...(box.values
          .map((item) => Playlist.fromJson(item).toMediaItem())
          .toList())
    ];
    await box.close();
    return playlists;
  }

  Future<List<MediaItem>> getLibSongs(String libId) async {
    Box<dynamic> box;
    try {
      box = await Hive.openBox(libId);
    } catch (e) {
      box = await Hive.openBox(libId);
    }
    final songs = box.values.toList().map((e) {
      final song = MediaItemBuilder.fromJson(e);
      return MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        artUri: song.artUri,
        extras: {"libraryId": libId},
        playable: true,
      );
    }).toList();

    if (!libId.contains("SongDownloads")) {
      await box.close();
    }

    if (libId == "LIBRP") {
      return songs.reversed.toList();
    }

    return songs;
  }
}
