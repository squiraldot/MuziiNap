import 'dart:async';
import './constant.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';


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
import './music_service.dart';
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
  return await AudioService.init(
    builder: () => MyAudioHandler(),
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
  // ignore: prefer_typing_uninitialized_variables
  late final _cacheDir;
  late AudioPlayer _player;
  late MediaLibrary _mediaLibrary;
  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;
  late String? currentSongUrl;
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = false;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;
  // Serialize audio-setting mutations so startup restoration and rapid user
  // toggles cannot complete out of order and overwrite each other.
  Future<void> _audioSettingsQueue = Future<void>.value();
  bool isSongLoading = true;
  int _playSessionId = 0;
  String? _playbackRecoverySongId;
  int? _activeEqualizerSessionId;
  EqualizerConfig _equalizerConfig = EqualizerConfig.graphic10Band();

  // list of shuffled queue songs ids
  List<String> shuffledQueue = [];



  MyAudioHandler() {
    _mediaLibrary = MediaLibrary();
    _player = AudioPlayer(
      useProxyForRequestHeaders: false,
      audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
      minBufferDuration: Duration(seconds: 10),
      maxBufferDuration: Duration(seconds: 30),
      bufferForPlaybackDuration: Duration(milliseconds: 250),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 1),
    )));
    _createCacheDir();
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
    if (!Directory("$_cacheDir/cachedSongs/").existsSync()) {
      Directory("$_cacheDir/cachedSongs/").createSync(recursive: true);
    }
  }

  void _listenSessionIdStream() {
    _player.androidAudioSessionIdStream.listen((int? id) {
      if (id == null || id <= 0) return;

      final previousSessionId = _activeEqualizerSessionId;
      if (previousSessionId != null && previousSessionId != id) {
        EqualizerService.endAudioEffect(previousSessionId);
      }

      _activeEqualizerSessionId = id;
      // Keep session changes lightweight. DynamicsProcessing is initialized only
      // after playback starts so it cannot block startup or first-track loading.
      EqualizerService.initAudioEffect(id);
    });
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
    _player.playbackEventStream.listen((PlaybackEvent event) {
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
    });
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
        }).catchError((Object retryError, StackTrace stackTrace) {
          _markPlaybackFailed(retryError);
        }),
      );
    } catch (retryError) {
      _markPlaybackFailed(retryError);
    }
  }

  void _markPlaybackFailed(Object error) {
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

  void _listenToPlaybackForNextSong() {
    const playerDurationOffset = 0;
    _player.positionStream.listen((value) async {
      if (_player.duration != null && _player.duration?.inSeconds != 0) {
        if (value.inMilliseconds >=
            (_player.duration!.inMilliseconds - playerDurationOffset)) {
          await _triggerNext();
        }
      }
    });
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
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
    });
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (currentIndex == null || currQueue.isEmpty || duration == null) return;
      final currentSong = queue.value[currentIndex];
      if (currentSong.duration == null || currentIndex == 0) {
        final newMediaItem = currentSong.copyWith(duration: duration);
        mediaItem.add(newMediaItem);
      }
    });
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
  }

  @override
  Future<void> play() async {
    if (currentSongUrl == null) {
      await customAction("playByIndex", {'index': currentIndex});
      return;
    }
    // Workaround for network error pause in case of PlayingUsingLockCachingSource
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

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
        await _player.dispose();
        super.stop();
        break;

      case 'playByIndex':
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        final isNewUrlReq = extras['newUrl'] ?? false;
        if (!isNewUrlReq) _playbackRecoverySongId = null;
        final currentSong = queue.value[currentIndex];
        final currentSession = ++_playSessionId;
        isSongLoading = true;
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.loading));
        
        // Stop playing the old song immediately while loading the new one
        await _player.pause();

        final futureStreamInfo =
            checkNGetUrl(currentSong.id, generateNewUrl: isNewUrlReq);
        final bool restoreSession = extras['restoreSession'] ?? false;


        mediaItem.add(currentSong);
        HMStreamingData streamInfo;
        try {
          streamInfo = await futureStreamInfo;
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
        } else if (!streamInfo.playable) {
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
          final playFuture = _player.play();
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
        final currentSession = ++_playSessionId;
        isSongLoading = true;
        currentIndex = 0;
        
        // Stop playing the old song immediately while loading the new one
        await _player.pause();

        final futureStreamInfo = checkNGetUrl(currMed.id);

        mediaItem.add(currMed);
        queue.add([currMed]);
        final streamInfo = (await futureStreamInfo);
        if (currentSession != _playSessionId) {
          return;
        }
        if (!streamInfo.playable) {
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
        isSongLoading = false;

        // Normalize audio
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          await _normalizeVolume(streamInfo.audio!.loudnessDb);
        }
        if (currentSession != _playSessionId) return;

        final playFuture = _player.play();
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
            await _player.setVolume(1.0);
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

      case 'setVolume':
        final rawValue = extras!['value'];
        final value = (rawValue as num).toDouble().clamp(0.0, 100.0);
        await _player.setVolume(value / 100.0);
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
    await _player.setVolume(volumeAdjustment.toDouble().clamp(0, 1.0));
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
    _playbackRecoverySongId = null;
    isSongLoading = false;
    currentSongUrl = null;
    await _player.stop();
    mediaItem.add(null);
    queue.add(<MediaItem>[]);
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
      if (songsUrlCacheBox.containsKey(songId) && !generateNewUrl) {
        final streamInfoJson = songsUrlCacheBox.get(songId);
        if (streamInfoJson.runtimeType.toString().contains("Map") &&
            streamInfoJson.containsKey('streamHeaders') &&
            !isExpired(url: (streamInfoJson['lowQualityAudio']['url']))) {
          printINFO("Got cached Url ($songId)");
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        }
      }

      if (streamInfo == null) {
        final token = RootIsolateToken.instance;
        Map<String, dynamic>? streamInfoJson;
        try {
          streamInfoJson = await Isolate.run(
            () => getStreamInfo(
              songId,
              token,
              preferYoutubeExplode: generateNewUrl,
            ),
          );
        } catch (e) {
          printINFO("Isolate error (likely Hot Reload issue): \$e");
          streamInfoJson = await getStreamInfo(
            songId,
            token,
            preferYoutubeExplode: generateNewUrl,
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
