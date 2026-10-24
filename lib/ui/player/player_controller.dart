import '../../models/equalizer.dart';

import '../../services/constant.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_lyric/lyric_ui/lyric_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import '../navigator.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/playling_from.dart';
import '../../services/downloader.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '../../services/synced_lyrics_service.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../utils/helper.dart';
import '../../utils/lyrics_timeline.dart';
import '../../utils/home_history.dart';
import '../../models/media_Item_builder.dart';
import '../screens/Home/home_screen_controller.dart';
import '../widgets/sliding_up_panel.dart';
import '../../models/durationstate.dart';
import '../../services/music_service.dart';
import '../widgets/keyboard_shortcuts_menu.dart';
import '../widgets/lyrics_dialog.dart';
class PlayerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final _audioHandler = Get.find<AudioHandler>();
  final _musicServices = Get.find<MusicServices>();
  final currentQueue = <MediaItem>[].obs;

  final playerPaneOpacity = (1.0).obs;
  // Prevent route and media updates from resurrecting a dismissed mini player.
  final isMiniPlayerDismissed = false.obs;
  final isPlayerpanelTopVisible = true.obs;
  final isPanelGTHOpened = false.obs;
  final playerPanelMinHeight = 0.0.obs;
  bool initFlagForPlayer = true;
  final isQueueReorderingInProcess = false.obs;
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  String? radioContinuationParam;
  dynamic radioInitiatorItem;
  Timer? sleepTimer;
  int timerDuration = 0;
  final timerDurationLeft = 0.obs;
  final isSleepTimerActive = false.obs;
  final isSleepEndOfSongActive = false.obs;
  final volume = 100.obs;

  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;

  final currentSongIndex = (0).obs;
  final isFirstSong = true;
  final isLastSong = true;
  final isQueueLoopModeEnabled = false.obs;
  final isLoopModeEnabled = false.obs;
  final isShuffleModeEnabled = false.obs;
  final currentSong = Rxn<MediaItem>();
  final isCurrentSongFav = false.obs;
  final playinfrom = PlaylingFrom(type: PlaylingFromType.SELECTION).obs;
  final showLyricsflag = false.obs;
  final isLyricsLoading = false.obs;
  final lyricsMode = 0.obs;
  bool isLyricsDialogOpen = false;
  // 0 for play, 1 for pause, 2 for blank
  final gesturePlayerVisibleState = 2.obs;
  final lyricFontFamily = 'Poppins'.obs;
  final activeLyricSize = 22.0.obs;
  final boldActiveLyric = true.obs;
  final lyricsStyleRevision = 0.obs;
  late final MuziiNapLyricUI lyricUi = MuziiNapLyricUI(
    highlight: true, defaultSize: activeLyricSize.value, defaultExtSize: 12,
    fontFamily: lyricFontFamily.value,
    boldActiveLyric: boldActiveLyric.value,
  );
  RxMap<String, dynamic> lyrics =
      <String, dynamic>{"synced": "", "plainLyrics": ""}.obs;
  static const MethodChannel _homeLyricsWidgetChannel =
      MethodChannel('muziinap/home_lyrics_widget');
  List<TimedLyricLine> _homeWidgetTimeline = const <TimedLyricLine>[];
  String? _lastHomeWidgetPayload;
  int _lastHomeWidgetLyricIndex = -2;
  Worker? _homeWidgetLyricsWorker;
  Worker? _homeWidgetSongWorker;

  void _publishCurrentLyricToHomeWidget() {
    if (!GetPlatform.isAndroid) return;
    final activeIndex = LyricsTimeline.activeIndex(
      _homeWidgetTimeline,
      effectiveLyricsPositionMs,
    );
    final previous = activeIndex > 0
        ? _homeWidgetTimeline[activeIndex - 1].text
        : '';
    final current = activeIndex >= 0 && activeIndex < _homeWidgetTimeline.length
        ? _homeWidgetTimeline[activeIndex].text
        : '';
    final next = activeIndex >= 0 && activeIndex + 1 < _homeWidgetTimeline.length
        ? _homeWidgetTimeline[activeIndex + 1].text
        : '';
    // Only redraw when the visible three-line window changes, not on every
    // audio-position tick. The native widget handles the visual cross-fade.
    final payloadKey = jsonEncode(<String>[previous, current, next]);
    if (payloadKey == _lastHomeWidgetPayload && activeIndex == _lastHomeWidgetLyricIndex) return;
    _lastHomeWidgetPayload = payloadKey;
    _lastHomeWidgetLyricIndex = activeIndex;
    unawaited(
      _homeLyricsWidgetChannel.invokeMethod<void>(
        'updateLines',
        <String, Object>{
          'previous': previous,
          'current': current,
          'next': next,
          'activeIndex': activeIndex,
        },
      ).catchError((Object error) {
        printINFO('Home-screen lyrics widget update failed: $error');
      }),
    );
  }

  @override
  void onClose() {
    _homeWidgetLyricsWorker?.dispose();
    _homeWidgetSongWorker?.dispose();
    super.onClose();
  }

  ScrollController scrollController = ScrollController();
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  final buttonState = PlayButtonState.paused.obs;

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;

  var _newSongFlag = true;
  final isCurrentSongBuffered = false.obs;

  late StreamSubscription<bool> keyboardSubscription;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  @override
  void onReady() {
    _restorePrevSession();
    super.onReady();
  }

  void _init() async {
    _listenForChangesInPlayerState();
    _listenForChangesInPosition();
    _homeWidgetLyricsWorker = ever(lyrics, (_) {
      _homeWidgetTimeline = LyricsTimeline.parse(
        lyrics['synced']?.toString() ?? '',
      );
      _lastHomeWidgetPayload = null;
      _lastHomeWidgetLyricIndex = -2;
      _publishCurrentLyricToHomeWidget();
    });
    _homeWidgetSongWorker = ever(currentSong, (_) {
      _homeWidgetTimeline = const <TimedLyricLine>[];
      _lastHomeWidgetPayload = null;
      _lastHomeWidgetLyricIndex = -2;
      _publishCurrentLyricToHomeWidget();
    });
    _listenForChangesInBufferedPosition();
    _listenForChangesInDuration();
    _listenForPlaylistChange();
    _listenForKeyboardActivity();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _setInitLyricsMode();
    final appPrefs = Hive.box(appPrefsBoxName);
    final savedFont = appPrefs.get('lyricsFontFamily');
    lyricFontFamily.value = lyricFontFamilies.contains(savedFont) ? savedFont as String : 'Poppins';
    final savedSize = appPrefs.get('activeLyricSize');
    activeLyricSize.value = savedSize is num && savedSize >= 16 && savedSize <= 36 ? savedSize.toDouble() : 22.0;
    boldActiveLyric.value = appPrefs.get('boldActiveLyric') is bool ? appPrefs.get('boldActiveLyric') as bool : true;
    lyricUi.fontFamily = lyricFontFamily.value == 'System' ? null : lyricFontFamily.value;
    lyricUi.defaultSize = activeLyricSize.value;
    lyricUi.boldActiveLyric = boldActiveLyric.value;
    isLoopModeEnabled.value = appPrefs.get("isLoopModeEnabled") ?? false;
    isShuffleModeEnabled.value = appPrefs.get("isShuffleModeEnabled") ?? false;
    isQueueLoopModeEnabled.value =
        appPrefs.get("queueLoopModeEnabled") ?? false;

    if ((appPrefs.get("playerUi") ?? 0) == 1) {
      initGesturePlayerStateAnimationController();
    }

    // only for android auto
    if (GetPlatform.isAndroid) {
      _listenForCustomEvents();
    }
  }

  void initGesturePlayerStateAnimationController() {
    gesturePlayerStateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    gesturePlayerStateAnimation = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
            parent: gesturePlayerStateAnimationController!,
            curve: Curves.easeIn));
  }

  // Focus scope nodes for Tab navigation
  final FocusScopeNode sidePanelFocus = FocusScopeNode(debugLabel: 'sidePanel');
  final FocusScopeNode centerPanelFocus = FocusScopeNode(debugLabel: 'centerPanel');
  final FocusScopeNode playerFocus = FocusScopeNode(debugLabel: 'player');
  final FocusScopeNode miniPlayerFocus = FocusScopeNode(debugLabel: 'miniPlayer');
  final FocusScopeNode searchFocus = FocusScopeNode(debugLabel: 'search');

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final focusContext = FocusManager.instance.primaryFocus?.context;
      final isTextFieldFocused = focusContext != null && 
          (focusContext.widget is EditableText || focusContext.findAncestorWidgetOfExactType<TextField>() != null);

      if (isTextFieldFocused) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          FocusManager.instance.primaryFocus?.unfocus();
          return true;
        }
        if (event.logicalKey != LogicalKeyboardKey.tab) {
          return false;
        }
      }

      if (event.logicalKey == LogicalKeyboardKey.tab) {
        if (playerFocus.hasFocus || playerFocus.children.any((node) => node.hasFocus) ||
            miniPlayerFocus.hasFocus || miniPlayerFocus.children.any((node) => node.hasFocus)) {
          centerPanelFocus.requestFocus();
        } else {
          if (playerPanelController.isPanelOpen) {
            playerFocus.requestFocus();
          } else {
            miniPlayerFocus.requestFocus();
          }
        }
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        searchFocus.requestFocus();
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyM) {
        sidePanelFocus.requestFocus();
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyL) {
        if (!playerPanelController.isPanelOpen) {
          if (isLyricsDialogOpen) {
            Get.back();
            return true;
          }
          if (!showLyricsflag.value) {
            showLyrics();
          } else if (lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) {
            showLyricsflag.value = false;
            showLyrics();
          }
          Get.dialog(const LyricsDialog()).whenComplete(() {
            isLyricsDialogOpen = false;
            showLyricsflag.value = false;
          });
          isLyricsDialogOpen = true;
        } else {
          showLyrics();
        }
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        if (playerPanelController.isPanelOpen) {
          playerFocus.requestFocus();
        } else {
          miniPlayerFocus.requestFocus();
        }
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        if (isMiniPlayerDismissed.value) return true;
        if (playerPanelController.isPanelOpen) {
          playerPanelController.close();
        } else {
          playerPanelController.open();
        }
        return true;
      }

      if (event.character == '?' || (event.logicalKey == LogicalKeyboardKey.slash && HardwareKeyboard.instance.isShiftPressed)) {
        showKeyboardShortcutsDialog(homeScaffoldkey.currentState!.context);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // Let the native Flutter dialog handler take care of Escape key for dialogs
        if (Get.isDialogOpen == true || Get.isBottomSheetOpen == true) {
          return false; 
        }
        
        if (playerPanelController.isPanelOpen) {
          playerPanelController.close();
          return true;
        }
        
        final innerNav = Get.nestedKey(ScreenNavigationSetup.id)?.currentState;
        if (innerNav != null && innerNav.canPop()) {
          innerNav.pop();
          return true;
        } 
        
        // Prevent generic Escape from closing the app
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
        playPause();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyN || event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
        next();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyB || event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
        prev();
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        if (queuePanelController.isPanelOpen) {
          queuePanelController.close();
        } else {
          queuePanelController.open();
        }
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (playerPanelController.isPanelOpen) {
          seekForward();
          return true;
        }
        return false;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (playerPanelController.isPanelOpen) {
          seekBackward();
          return true;
        }
        return false;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (playerPanelController.isPanelOpen) {
          volumeUp();
          return true;
        }
        return false;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (playerPanelController.isPanelOpen) {
          volumeDown();
          return true;
        }
        return false;
      }
    }
    return false;
  }

  static const lyricFontFamilies = <String>["Poppins","System","Bold","Classic","Directional","Elegant","Gujarati Bold","Gujarati Thin","Hindi Bold","Hindi Thin","Journal","Meme","Modern","Neon","PermanentMaker","Rosalia","SFProDisplay","SFProMedium","Strong","Typewriter","iOS Bold","iOS Comic Sans","iOS Cursive italic","iOS Hindi Bold","iOS Hindi Light","iOS New Money","iOS Semibold","iOS Strong","iOS Typewriter","literature"];

  /// Positive values delay lyric highlighting; negative values advance it.
  final lyricsSyncOffsetMs = 0.obs;

  int get effectiveLyricsPositionMs {
    final audioMs = progressBarStatus.value.current.inMilliseconds;
    final totalMs = progressBarStatus.value.total.inMilliseconds;
    return (audioMs - lyricsSyncOffsetMs.value).clamp(0, totalMs > 0 ? totalMs : 0).toInt();
  }

  Future<void> loadLyricsSyncOffsetForCurrentSong() async {
    final songId = currentSong.value?.id;
    if (songId == null) {
      lyricsSyncOffsetMs.value = 0;
      return;
    }
    final value = Hive.box(appPrefsBoxName).get('lyricsSyncOffset:$songId', defaultValue: 0);
    lyricsSyncOffsetMs.value = value is num ? value.toInt().clamp(-10000, 10000) : 0;
  }

  Future<void> setLyricsSyncOffset(int milliseconds) async {
    final safeValue = milliseconds.clamp(-10000, 10000).toInt();
    lyricsSyncOffsetMs.value = safeValue;
    final songId = currentSong.value?.id;
    if (songId != null) {
      await Hive.box(appPrefsBoxName).put('lyricsSyncOffset:$songId', safeValue);
    }
  }

  Future<void> resetLyricsSyncOffset() => setLyricsSyncOffset(0);

  Future<void> setLyricFontFamily(String value) async {
    if (!lyricFontFamilies.contains(value)) return;
    lyricFontFamily.value = value;
    lyricUi.fontFamily = value == 'System' ? null : value;
    lyricsStyleRevision.value++;
    await Hive.box(appPrefsBoxName).put('lyricsFontFamily', value);
  }

  Future<void> setActiveLyricSize(double value) async {
    final size = value.clamp(16.0, 36.0).toDouble();
    activeLyricSize.value = size;
    lyricUi.defaultSize = size;
    lyricsStyleRevision.value++;
    await Hive.box(appPrefsBoxName).put('activeLyricSize', size);
  }

  Future<void> setBoldActiveLyric(bool value) async {
    boldActiveLyric.value = value;
    lyricUi.boldActiveLyric = value;
    lyricsStyleRevision.value++;
    await Hive.box(appPrefsBoxName).put('boldActiveLyric', value);
  }

  void _setInitLyricsMode() {
    lyricsMode.value = Hive.box(appPrefsBoxName).get("lyricsMode") ?? 0;
  }

  /// Fully hide the player panel and stop playback until a song is selected again.
  Future<void> dismissMiniPlayer() async {
    if (isMiniPlayerDismissed.value) return;

    // Mark dismissal first so slide/media callbacks cannot resurrect the UI.
    isMiniPlayerDismissed.value = true;
    isPlayerpanelTopVisible.value = false;
    playerPaneOpacity.value = 0;
    isPanelGTHOpened.value = false;

    // Stop immediately, before waiting for the panel animation. A stream URL
    // request may otherwise finish during the hide animation and start playback.
    // AudioHandler.stop() invalidates the in-flight play session synchronously.
    final stopFuture = _audioHandler.stop();

    // close() only collapses to minHeight; hide() removes the panel itself.
    if (playerPanelController.isAttached) {
      await playerPanelController.hide();
    }
    await stopFuture;

    // Keep minHeight as layout configuration; dismissal is controlled by the
    // panel's hidden state and the dismissal flag, not by mutating its size.
    isPlayerpanelTopVisible.value = false;
    playerPaneOpacity.value = 0;
    isPanelGTHOpened.value = false;
  }

  void panellistener(double x) {
    // PanelController.close() emits slide callbacks while dismissMiniPlayer is
    // animating. Do not let those callbacks restore the header/opacity after
    // the user explicitly dismissed the mini player.
    if (!isMiniPlayerDismissed.value) {
      if (x >= 0 && x <= 0.2) {
        playerPaneOpacity.value = 1 - (x * 5);
        isPlayerpanelTopVisible.value = true;
      } else if (x > 0.2) {
        isPlayerpanelTopVisible.value = false;
      }
    } else {
      playerPaneOpacity.value = 0;
      isPlayerpanelTopVisible.value = false;
    }

    if (x > 0.6) {
      isPanelGTHOpened.value = true;
    } else {
      isPanelGTHOpened.value = false;
    }
  }

  void _listenForKeyboardActivity() {
    final keyboardVisibilityController = KeyboardVisibilityController();
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen((bool visible) {
      if (!playerPanelController.isAttached) return;
      if (visible) {
        playerPanelController.hide();
      } else if (!isMiniPlayerDismissed.value) {
        // Keyboard dismissal must not undo an explicit Mini Player dismissal.
        playerPanelController.show();
      }
    });
  }

  void _listenForChangesInPlayerState() {
    _audioHandler.playbackState.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      if (processingState == AudioProcessingState.loading) {
        buttonState.value = PlayButtonState.loading;
      } else if (processingState == AudioProcessingState.buffering) {
        buttonState.value = PlayButtonState.loading;
      } else if (!isPlaying || processingState == AudioProcessingState.error) {
        buttonState.value = PlayButtonState.paused;
      } else if (processingState != AudioProcessingState.completed) {
        buttonState.value = PlayButtonState.playing;
      } else {
        _audioHandler.seek(Duration.zero);
        _audioHandler.pause();
      }

      final settings = Get.find<SettingsScreenController>();
      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable = settings.keepScreenAwake.isTrue && isPlaying;
      _setWakelock(shouldEnable);
    });
  }

  Future<void> _setWakelock(bool enable) async {
    if (_wakelockActive == enable) return;

    try {
      if (enable) {
        printINFO("Enabling wakelock");
        await WakelockPlus.enable();
      } else {
        printINFO("Disabling wakelock");
        await WakelockPlus.disable();
      }
      _wakelockActive = enable;
    } catch (e) {
      printERROR("Failed to update wakelock: $e");
    }
  }

  void _listenForChangesInPosition() {
    AudioService.position.listen((position) {
      final oldState = progressBarStatus.value;
      if (isSleepEndOfSongActive.isTrue) {
        timerDurationLeft.value = oldState.total.inSeconds - position.inSeconds;
        if (timerDurationLeft.value == 1) {
          pause();
          cancelSleepTimer();
        }
      }
      progressBarStatus.update((val) {
        val!.current = position;
        val.buffered = oldState.buffered;
        val.total = oldState.total;
      });
      _publishCurrentLyricToHomeWidget();
    });
  }

  void _listenForChangesInBufferedPosition() {
    _audioHandler.playbackState.listen((playbackState) {
      final oldState = progressBarStatus.value;
      if (progressBarStatus.value.total.inSeconds != 0 &&
          playbackState.bufferedPosition.inSeconds /
                  progressBarStatus.value.total.inSeconds >=
              0.98) {
        if (_newSongFlag) {
          _audioHandler.customAction(
              "checkWithCacheDb", {'mediaItem': currentSong.value!});
          _newSongFlag = false;
        }
      }
      progressBarStatus.update((val) {
        val!.buffered = playbackState.bufferedPosition;
        val.current = oldState.current;
        val.total = oldState.total;
      });
    });
  }

  void _listenForChangesInDuration() {
    _audioHandler.mediaItem.listen((mediaItem) async {
      final oldState = progressBarStatus.value;
      progressBarStatus.update((val) {
        val!.total = mediaItem?.duration ?? Duration.zero;
        val.current = oldState.current;
        val.buffered = oldState.buffered;
      });
      if (mediaItem == null) {
        // AudioService.stop() (including the notification's dismiss action)
        // clears the media item. Keep the in-app mini player in sync.
        isMiniPlayerDismissed.value = true;
        currentSong.value = null;
        isPlayerpanelTopVisible.value = false;
        playerPaneOpacity.value = 0;
        isPanelGTHOpened.value = false;
      } else {
        final dismissed = isMiniPlayerDismissed.value;
        // A mediaItem event is emitted for every Next/Previous action. The
        // panel's header is attached to the top of the expanded player, so
        // showing it unconditionally duplicates the Mini Player over Player.
        // Derive header visibility from the actual panel position instead.
        final panelIsExpanded = playerPanelController.isAttached &&
            playerPanelController.panelPosition > 0.2;
        final showMiniPlayerHeader = !dismissed && !panelIsExpanded;
        isPlayerpanelTopVisible.value = showMiniPlayerHeader;
        playerPaneOpacity.value = showMiniPlayerHeader ? 1 : 0;
        final miniPlayerHeight = Get.size.width > 800 ? 105.0 : 75.0;
        final settings = Get.find<SettingsScreenController>();
        if (!dismissed) {
          playerPanelMinHeight.value =
              (settings.isBottomNavBarEnabled.isFalse ||
                      getCurrentRouteName() != '/homeScreen')
                  ? miniPlayerHeight + Get.mediaQuery.viewPadding.bottom
                  : miniPlayerHeight;
        }
        printINFO(mediaItem.title);
        _newSongFlag = true;
        isCurrentSongBuffered.value = false;
        currentSong.value = mediaItem;
        await loadLyricsSyncOffsetForCurrentSong();
        currentSongIndex.value = currentQueue
            .indexWhere((element) => element.id == currentSong.value!.id);
        await _checkFav();
        final appPrefs = Hive.box(appPrefsBoxName);
        final isYouTubeAuthenticated =
            appPrefs.get('yt_logged_in', defaultValue: false) == true;
        if (!isYouTubeAuthenticated) {
          await _addToRP(currentSong.value!);
          await saveRecentlyPlayed(currentSong.value!);
        }
        if (isRadioModeOn && (currentSong.value!.id == currentQueue.last.id)) {
          await _addRadioContinuation(radioInitiatorItem!);
        }
        lyrics.value = {"synced": "", "plainLyrics": ""};
        showLyricsflag.value = false;
        if (isLyricsDialogOpen) {
          Navigator.pop(Get.context!);
        }

        // reset player visible state when player is in gesture mode
        if (Get.find<SettingsScreenController>().playerUi.value == 1) {
          gesturePlayerVisibleState.value = 2;
        }
      }
    });
  }

  void _listenForPlaylistChange() {
    _audioHandler.queue.listen((queue) {
      currentQueue.value = queue;
      currentQueue.refresh();
    });
  }

  Future<void> _restorePrevSession() async {
    final restrorePrevSessionEnabled =
        Hive.box(appPrefsBoxName).get("restrorePlaybackSession") ?? false;
    if (restrorePrevSessionEnabled) {
      final prevSessionData = await Hive.openBox("prevSessionData");
      if (prevSessionData.keys.isNotEmpty) {
        final songList = (prevSessionData.get("queue") as List)
            .map((e) => MediaItemBuilder.fromJson(e))
            .toList();
        final int currentIndex = prevSessionData.get("index");
        final int position = prevSessionData.get("position");
        prevSessionData.close();
        await _audioHandler.addQueueItems(songList);
        await _playerPanelCheck(restoreSession: true);
        await _audioHandler.customAction("playByIndex", {
          "index": currentIndex,
          "position": position,
          "restoreSession": true
        });
      }
    }
  }

  void _listenForCustomEvents() {
    _audioHandler.customEvent.listen((event) {
      if (event['eventType'] == 'playFromMediaId') {
        _playViaAndroidAuto(event['songId'], event['libraryId']);
      }
    });
  }

  ///pushSongToPlaylist method clear previous song queue, plays the tapped song and push related
  ///songs into Queue
  Future<void> pushSongToQueue(MediaItem? mediaItem,
      {String? playlistid, bool radio = false}) async {
    /// update playing from value
    playinfrom.value = PlaylingFrom(
        type: PlaylingFromType.SELECTION,
        name: radio ? "randomRadio".tr : "randomSelection".tr);

    /// set global radio mode flag
    isRadioModeOn = radio;

    Future.delayed(
      Duration.zero,
      () async {
        final content = await _musicServices.getWatchPlaylist(
            videoId: mediaItem?.id ?? "", radio: radio, playlistId: playlistid);
        radioContinuationParam = content['additionalParamsForNext'];
        await _audioHandler
            .updateQueue(List<MediaItem>.from(content['tracks']));
        if (isShuffleModeEnabled.isTrue) {
          await _audioHandler.customAction("shuffleCmd", {"index": 0});
        }

        // added here to broadcast current mediaitem via Audio Service as list is updated
        // if radio is started on current playing song
        if (radio && (currentSong.value?.id == mediaItem?.id)) {
          _audioHandler
              .customAction("upadateMediaItemInAudioService", {"index": 0});
        }
      },
    ).then((value) async {
      if (playlistid != null) {
        await _playerPanelCheck();
        await _audioHandler.customAction("playByIndex", {"index": 0});
      } else {
        if (Hive.box(appPrefsBoxName).get("discoverContentType") == "BOLI") {
          Get.find<HomeScreenController>()
              .changeDiscoverContent("BOLI", songId: mediaItem!.id);
        }
      }
    });

    if (playlistid != null ||
        (radio && (currentSong.value?.id == mediaItem?.id))) {
      return;
    }

    await _playerPanelCheck();
    await _audioHandler
        .customAction("setSourceNPlay", {'mediaItem': mediaItem});

    // disable queue loop mode when radio is started
    if (radio &&
        isQueueLoopModeEnabled.isTrue &&
        isShuffleModeEnabled.isFalse) {
      toggleQueueLoopMode();
    }
  }

  Future<void> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom}) async {
    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playinfrom.value =
        playfrom ?? PlaylingFrom(type: PlaylingFromType.SELECTION);

    //for changing home content based on last interation
    Future.delayed(const Duration(seconds: 3), () {
      if (Hive.box(appPrefsBoxName).get("discoverContentType") == "BOLI") {
        Get.find<HomeScreenController>()
            .changeDiscoverContent("BOLI", songId: mediaItems[index].id);
      }
    });

    await _playerPanelCheck();
    await _audioHandler.updateQueue(mediaItems);
    if (isShuffleModeEnabled.value) {
      await _audioHandler.customAction("shuffleCmd", {"index": index});
    }
    await _audioHandler.customAction("playByIndex", {"index": index});
  }

  Future<void> startRadio(MediaItem? mediaItem, {String? playlistid}) async {
    radioInitiatorItem = mediaItem ?? playlistid;
    await pushSongToQueue(mediaItem, playlistid: playlistid, radio: true);
  }

  Future<void> _addRadioContinuation(dynamic item) async {
    final isSong = item.runtimeType.toString() == "MediaItem";
    final content = await _musicServices.getWatchPlaylist(
        videoId: isSong ? item.id : "",
        radio: true,
        limit: 24,
        playlistId: isSong ? null : item,
        additionalParamsNext: radioContinuationParam);
    radioContinuationParam = content['additionalParamsForNext'];
    await enqueueSongList(List<MediaItem>.from(content['tracks']));
  }

  ///enqueueSong   append a song to current queue
  ///if current queue is empty, push the song into Queue and play that song
  Future<void> enqueueSong(MediaItem mediaItem) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong([mediaItem], 0);
      return;
    }
    //check if song is available in queue and if not add it to queue
    if (!currentQueue.contains(mediaItem)) {
      _audioHandler.addQueueItem(mediaItem);
    }
  }

  ///enqueueSongList method add song List to current queue
  Future<void> enqueueSongList(List<MediaItem> mediaItems) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong(mediaItems, 0);
      return;
    }
    final listToEnqueue = <MediaItem>[];
    for (MediaItem item in mediaItems) {
      if (!currentQueue.contains(item)) {
        listToEnqueue.add(item);
      }
    }
    _audioHandler.addQueueItems(listToEnqueue);
  }

  void _playViaAndroidAuto(String songId, String libraryId) {
    Hive.openBox(libraryId).then((box) {
      List<MediaItem> songList = [];
      final songJson = box.values.toList();
      int songIndex = 0;
      for (int i = 0; i < box.length; i++) {
        final song = MediaItemBuilder.fromJson(songJson[i]);
        if (song.id == songId) {
          songIndex = i;
        }
        songList.add(song);
      }
      playPlayListSong(songList, songIndex);
      if (libraryId != "SongDownloads") {
        box.close();
      }
    });
  }

  void playNext(MediaItem song) {
    if (currentQueue.isEmpty) {
      enqueueSong(song);
      return;
    }
    int index = -1;
    for (int i = 0; i < currentQueue.length; i++) {
      if (song.id == (currentQueue[i]).id) {
        index = i;
        break;
      }
    }
    final currentIndx = currentSongIndex.value;
    if (index == currentIndx) {
      return;
    }
    if (index != -1) {
      if (currentQueue.length == 1 ||
          (currentQueue.length == 2 && index == 1)) {
        return;
      }
      int newIndex = currentSongIndex.value + 1;
      if (index < newIndex) {
        newIndex--;
      }
      onReorder(index, newIndex);
    } else {
      //Will add song just below the current song
      (currentIndx == currentQueue.length - 1)
          ? enqueueSong(song)
          : _audioHandler.customAction("addPlayNextItem", {"mediaItem": song});
    }
  }

  Future<void> _playerPanelCheck({bool restoreSession = false}) async {
    // Only a deliberate new song selection clears a user-requested dismissal.
    final wasDismissed = isMiniPlayerDismissed.value;
    if (!restoreSession && wasDismissed) {
      isMiniPlayerDismissed.value = false;
      // A dismissed panel was hidden at the widget level. Restore it before
      // any optional auto-open, otherwise open() animates an invisible panel.
      if (playerPanelController.isAttached) {
        await playerPanelController.show();
      }
    }

    final isWideScreen = Get.size.width > 800;
    final autoOpenPlayer = Hive.box(appPrefsBoxName).get("autoOpenPlayer") ?? false;
    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      await playerPanelController.open();
    }

    if (initFlagForPlayer) {
      final miniPlayerHeight = isWideScreen ? 105.0 : 75.0;
      if (!isMiniPlayerDismissed.value) {
        if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isFalse ||
            getCurrentRouteName() != '/homeScreen') {
          playerPanelMinHeight.value =
              miniPlayerHeight + Get.mediaQuery.viewPadding.bottom;
        } else {
          playerPanelMinHeight.value = miniPlayerHeight;
        }
      }
      initFlagForPlayer = false;
    }
  }

  void removeFromQueue(MediaItem song) {
    _audioHandler.removeQueueItem(song);
  }

  void clearQueue() {
    _audioHandler.customAction("clearQueue");
  }

  void shuffleQueue() {
    _audioHandler.customAction("shuffleQueue");
  }

  Future<void> toggleShuffleMode() async {
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    shuffleModeEnabled
        ? _audioHandler.setShuffleMode(AudioServiceShuffleMode.none)
        : _audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    isShuffleModeEnabled.value = !shuffleModeEnabled;
    await Hive.box(appPrefsBoxName).put("isShuffleModeEnabled", !shuffleModeEnabled);
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value = true;
    } else if (isShuffleModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value =
          Hive.box(appPrefsBoxName).get("queueLoopModeEnabled", defaultValue: false);
    }
  }

  void onReorder(int oldIndex, int newIndex) {
    _audioHandler.customAction(
        "reorderQueue", {"oldIndex": oldIndex, "newIndex": newIndex});
  }

  void onReorderStart(int index) {
    isQueueReorderingInProcess.value = true;
  }

  void onReorderEnd(int index) {
    isQueueReorderingInProcess.value = false;
  }

  void play() {
    _audioHandler.play();
  }

  void pause() {
    _audioHandler.pause();
  }

  void playPause() {
    if (initFlagForPlayer) return;
    _audioHandler.playbackState.value.playing ? pause() : play();
    // for gesture player
    if (Get.find<SettingsScreenController>().playerUi.value == 1) {
      gesturePlayerVisibleState.value =
          _audioHandler.playbackState.value.playing ? 0 : 1;
      gesturePlayerStateAnimationController?.reset();
      gesturePlayerStateAnimationController?.forward();
    }
  }

  void prev() {
    _audioHandler.skipToPrevious();
  }

  Future<void> next() async {
    await _audioHandler.skipToNext();
  }

  void seek(Duration position) {
    _audioHandler.seek(position);
  }

  void seekByIndex(int index) {
    _audioHandler.customAction("playByIndex", {"index": index});
  }

  Future<void> toggleSkipSilence(bool enable) async {
    await _audioHandler.customAction("toggleSkipSilence", {"enable": enable});
  }

  Future<void> toggleLoudnessNormalization(bool enable) async {
    await _audioHandler
        .customAction("toggleLoudnessNormalization", {"enable": enable});
  }

  Future<void> toggleLoopMode() async {
    isLoopModeEnabled.isFalse
        ? _audioHandler.setRepeatMode(AudioServiceRepeatMode.one)
        : _audioHandler.setRepeatMode(AudioServiceRepeatMode.none);
    isLoopModeEnabled.value = !isLoopModeEnabled.value;
    await Hive.box(appPrefsBoxName)
        .put("isLoopModeEnabled", isLoopModeEnabled.value);
  }

  Future<void> toggleQueueLoopMode({bool showMessage = true}) async {
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isTrue) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "queueLoopNotDisMsg1".tr,
          size: SanckBarSize.BIG, duration: const Duration(seconds: 2)));
      return;
    }

    if (isRadioModeOn && isQueueLoopModeEnabled.isFalse) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "queueLoopNotDisMsg2".tr,
          size: SanckBarSize.BIG, duration: const Duration(seconds: 2)));
      return;
    }

    isQueueLoopModeEnabled.value = !isQueueLoopModeEnabled.value;
    await _audioHandler.customAction(
        "toggleQueueLoopMode", {"enable": isQueueLoopModeEnabled.value});
    await Hive.box(appPrefsBoxName)
        .put("queueLoopModeEnabled", isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    final safeValue = value.clamp(0, 100).toInt();
    await _audioHandler.customAction("setVolume", {"value": safeValue});
    await Hive.box(appPrefsBoxName).put("volume", safeValue);
    volume.value = safeValue;
  }

  void volumeUp() {
    int v = volume.value + 5;
    if (v > 100) v = 100;
    setVolume(v);
  }

  void volumeDown() {
    int v = volume.value - 5;
    if (v < 0) v = 0;
    setVolume(v);
  }

  void seekForward() {
    final newPosition = progressBarStatus.value.current + const Duration(seconds: 5);
    seek(newPosition > progressBarStatus.value.total ? progressBarStatus.value.total : newPosition);
  }

  void seekBackward() {
    final newPosition = progressBarStatus.value.current - const Duration(seconds: 5);
    seek(newPosition.isNegative ? Duration.zero : newPosition);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = await Hive.box(appPrefsBoxName).get("volume", defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await Hive.box(appPrefsBoxName).put("volume", vol);
      }
    }
    await _audioHandler.customAction("setVolume", {"value": vol!});
    await Hive.box(appPrefsBoxName).put("volume", vol);
    volume.value = vol;
  }

  Future<void> _checkFav() async {
    isCurrentSongFav.value =
        (await Hive.openBox("LIBFAV")).containsKey(currentSong.value!.id);
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value!;
    final box = await Hive.openBox("LIBFAV");
    isCurrentSongFav.isFalse
        ? box.put(currMediaItem.id, MediaItemBuilder.toJson(currMediaItem))
        : box.delete(currMediaItem.id);
    try {
      final playlistController = Get.find<PlaylistScreenController>(
          tag: const Key("LIBFAV").hashCode.toString());
      isCurrentSongFav.isFalse
          ? playlistController.addNRemoveItemsinList(currMediaItem,
              action: 'add', index: 0)
          : playlistController.addNRemoveItemsinList(currMediaItem,
              action: 'remove');

      // ignore: empty_catches
    } catch (e) {}
    isCurrentSongFav.value = !isCurrentSongFav.value;
    if (Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue &&
        isCurrentSongFav.isTrue) {
      Get.find<Downloader>().download(currMediaItem);
    }
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final box = await Hive.openBox("LIBRP");
      String? removedSongId;
      if (box.keys.length >= 30) {
        removedSongId = box.getAt(0)['videoId'];
        box.deleteAt(0);
      }
      final valuesCopy = box.values.toList();
      for (int i = valuesCopy.length - 1; i >= 0; i--) {
        if (valuesCopy[i]['videoId'] == mediaItem.id) {
          box.deleteAt(i);
        }
      }
      box.add(MediaItemBuilder.toJson(mediaItem));
      try {
        final playlistController = Get.find<PlaylistScreenController>(
            tag: const Key("LIBRP").hashCode.toString());
        if (removedSongId != null) {
          playlistController.songList
              .removeWhere((element) => element.id == removedSongId);
        }
        // removes current duplicate item from list
        playlistController.songList
            .removeWhere((element) => element.id == mediaItem.id);
        // adds current item to list
        playlistController.addNRemoveItemsinList(mediaItem,
            action: 'add', index: 0);

        // ignore: empty_catches
      } catch (e) {}
    }
    recentItem = mediaItem;
  }

  Future<void> showLyrics() async {
    showLyricsflag.value = !showLyricsflag.value;
    if ((lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) &&
        showLyricsflag.value) {
      isLyricsLoading.value = true;
      try {
        final Map<String, dynamic>? lyricsR =
            await SyncedLyricsService.getSyncedLyrics(
                currentSong.value!, progressBarStatus.value.total.inSeconds);
        if (lyricsR != null) {
          lyrics.value = lyricsR;
          isLyricsLoading.value = false;
          return;
        }
        
        // --- YouTube Fallback Commented Out ---
        /*
        final related = await _musicServices.getWatchPlaylist(
            videoId: currentSong.value!.id, onlyRelated: true);
        final relatedLyricsId = related['lyrics'];
        if (relatedLyricsId != null) {
          final lyrics_ = await _musicServices.getLyrics(relatedLyricsId);
          lyrics.value = {"synced": "", "plainLyrics": lyrics_};
        } else {
          lyrics.value = {"synced": "", "plainLyrics": "NA"};
        }
        */
        
        // If not found in lrclib, just set to NA
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
      } catch (e) {
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
      }
      isLyricsLoading.value = false;
    }
  }

  Future<void> reloadLyrics() async {
    final song = currentSong.value;
    if (song == null) return;

    // Keep the currently displayed lyrics visible while a refresh is running.
    final previousLyrics = Map<String, dynamic>.from(lyrics);
    isLyricsLoading.value = true;
    try {
      final Map<String, dynamic>? lyricsR =
          await SyncedLyricsService.getSyncedLyrics(
              song, progressBarStatus.value.total.inSeconds, forceReload: true);
      if (lyricsR != null &&
          ((lyricsR["synced"]?.toString().trim().isNotEmpty ?? false) ||
              (lyricsR["plainLyrics"]?.toString().trim().isNotEmpty ?? false))) {
        lyrics.value = lyricsR;
        isLyricsLoading.value = false;
        return;
      }
      
      // --- YouTube Fallback Commented Out ---
      /*
      final related = await _musicServices.getWatchPlaylist(
          videoId: currentSong.value!.id, onlyRelated: true);
      final relatedLyricsId = related['lyrics'];
      if (relatedLyricsId != null) {
        final lyrics_ = await _musicServices.getLyrics(relatedLyricsId);
        lyrics.value = {"synced": "", "plainLyrics": lyrics_};
      } else {
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
      }
      */
      
      // A failed refresh should not erase lyrics that were already available.
      lyrics.value = previousLyrics;
    } catch (e) {
      lyrics.value = previousLyrics;
    } finally {
      isLyricsLoading.value = false;
    }
  }

  Future<void> translateLyrics() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        isLyricsLoading.value = true;
        File file = File(result.files.single.path!);
        String fileContent = await file.readAsString();
        
        bool hasTimestamps = fileContent.contains(RegExp(r'\[\d+:\d+\.\d+\]'));
        
        lyrics.value = {
          "synced": hasTimestamps ? fileContent : "",
          "plainLyrics": hasTimestamps ? "" : fileContent
        };
        lyricsMode.value = hasTimestamps ? 0 : 1; 
      }
    } catch (e) {
      printERROR(e);
    }
    isLyricsLoading.value = false;
  }

  void changeLyricsMode(int? val) {
    Hive.box(appPrefsBoxName).put("lyricsMode", val);
    lyricsMode.value = val!;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
  }

  void startSleepTimer(int minutes) {
    timerDuration = minutes * 60;
    isSleepTimerActive.value = true;
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          pause();
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
        }
      });
    }
  }

  void addFiveMinutes() {
    timerDuration += 300;
  }

  void cancelSleepTimer() {
    if (isSleepEndOfSongActive.isTrue) {
      isSleepEndOfSongActive.value = false;
    }
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  Future<void> applyEqualizerConfig(EqualizerConfig config) async {
    await _audioHandler.customAction(
      "applyEqualizerConfig",
      {'config': config.toJson()},
    );
  }

  Future<void> setEqualizerConfig(EqualizerConfig config) async {
    await _audioHandler.customAction(
      "setEqualizerConfig",
      {'config': config.toJson()},
    );
  }

  Future<void> resetEqualizer() async {
    await _audioHandler.customAction("resetEqualizer");
  }

  /// Called from audio handler in case audio is not playable
  /// or returned streamInfo null due to network error
  void notifyPlayError(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
        Get.context!, message == "networkError" ? message.tr : message,
        size: SanckBarSize.MEDIUM));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _audioHandler.customAction('dispose');
    keyboardSubscription.cancel();
    scrollController.dispose();
    gesturePlayerStateAnimationController?.dispose();
    sleepTimer?.cancel();
    // ensure wakelock disabled when player controller disposed
    try {
      _setWakelock(false);
    } catch (e) {
      printERROR(e);
    }
    super.dispose();
  }
}

enum PlayButtonState { paused, playing, loading }

class MuziiNapLyricUI extends LyricUI {
  double defaultSize;
  final double defaultExtSize;
  final double otherMainSize;
  final double bias;
  final double lineGap;
  final double inlineGap;
  final LyricAlign lyricAlign;
  final LyricBaseLine lyricBaseLine;
  final bool highlight;
  final HighlightDirection highlightDirection;
  String? fontFamily;
  bool boldActiveLyric;

  MuziiNapLyricUI({
    this.defaultSize = 20,
    this.defaultExtSize = 12,
    this.otherMainSize = 16,
    this.bias = 0.5,
    this.lineGap = 25,
    this.inlineGap = 25,
    this.lyricAlign = LyricAlign.CENTER,
    this.lyricBaseLine = LyricBaseLine.CENTER,
    this.highlight = true,
    this.highlightDirection = HighlightDirection.LTR,
    this.fontFamily = 'Poppins',
    this.boldActiveLyric = true,
  });

  TextStyle _fontStyle({
    required Color? color,
    required double size,
    FontWeight? weight,
  }) {
    if (fontFamily == null || fontFamily == 'System') {
      return TextStyle(color: color, fontSize: size, fontWeight: weight);
    }
    if (fontFamily == 'Poppins') {
      return GoogleFonts.poppins(color: color, fontSize: size, fontWeight: weight);
    }
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      fontFamily: fontFamily,
    );
  }

  @override
  TextStyle getPlayingExtTextStyle() =>
      _fontStyle(color: Colors.grey[300], size: defaultExtSize);

  @override
  TextStyle getOtherExtTextStyle() =>
      _fontStyle(color: Colors.grey[300], size: defaultExtSize);

  @override
  TextStyle getOtherMainTextStyle() =>
      _fontStyle(color: Colors.white.withOpacity(0.45), size: otherMainSize);

  @override
  TextStyle getPlayingMainTextStyle() => _fontStyle(
        color: Colors.white,
        size: defaultSize,
        weight: boldActiveLyric ? FontWeight.bold : FontWeight.normal,
      );

  @override
  double getInlineSpace() => inlineGap;

  @override
  double getLineSpace() => lineGap;

  @override
  double getPlayingLineBias() => bias;

  @override
  LyricAlign getLyricHorizontalAlign() => lyricAlign;

  @override
  LyricBaseLine getBiasBaseLine() => lyricBaseLine;

  @override
  bool enableHighlight() => highlight;

  @override
  HighlightDirection getHighlightDirection() => highlightDirection;
}
