import '../../../services/constant.dart';
import '../../../utils/update_check_flag_file.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import '../../../services/permission_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/piped_service.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '../../../utils/helper.dart';
import '../../../services/music_service.dart';
import '../../player/player_controller.dart';
import '../Home/home_screen_controller.dart';
import '../../utils/theme_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'settings_preferences.dart';

class SettingsScreenController extends GetxController {
  late String _supportDir;
  final cacheSongs = false.obs;
  final setBox = Hive.box(appPrefsBoxName);
  final themeModetype = ThemeType.dynamic.obs;
  final skipSilenceEnabled = false.obs;
  final loudnessNormalizationEnabled = false.obs;
  final noOfHomeScreenContent = 11.obs;
  final streamingQuality = AudioQuality.High.obs;
  final playerUi = 0.obs;
  final slidableActionEnabled = true.obs;
  final isIgnoringBatteryOptimizations = false.obs;
  final autoOpenPlayer = false.obs;
  final discoverContentType = "QP".obs;
  final isNewVersionAvailable = false.obs;
  final isLinkedWithPiped = false.obs;
  final stopPlyabackOnSwipeAway = true.obs;
  final currentAppLanguageCode = "en".obs;
  final downloadLocationPath = "".obs;
  final exportLocationPath = "".obs;
  final downloadingFormat = "".obs;
  final autoDownloadFavoriteSongEnabled = false.obs;
  final isTransitionAnimationDisabled = false.obs;
  final isBottomNavBarEnabled = true.obs;
  final backgroundPlayEnabled = true.obs;
  final keepScreenAwake = false.obs;
  final restorePlaybackSession = false.obs;
  final cacheHomeScreenData = true.obs;
  String currentVersion = '1.0.0';

  @override
  void onInit() {
    super.onInit();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
      await _setInitValue();
      await _createInAppSongDownDir();
    } catch (e) {
      printERROR("Failed to initialize settings: $e");
    }
  }

  get currentVision => currentVersion;
  get isCurrentPathsupportDownDir =>
      "$_supportDir/Music" == downloadLocationPath.toString();
  String get supportDirPath => _supportDir;

  Future<String> _createInAppSongDownDir() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    final directory = Directory("$_supportDir/Music/");
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return "$_supportDir/Music";
  }

  Future<void> _setInitValue() async {
    final appLang = setBox.get('currentAppLanguageCode') ?? "en";
    currentAppLanguageCode.value = appLang == "zh_Hant"
        ? "zh-TW"
        : appLang == "zh_Hans"
            ? "zh-CN"
            : appLang;
    final storedBottomNavBarEnabled = setBox.get("isBottomNavBarEnabled");
    isBottomNavBarEnabled.value = resolveBottomNavBarPreference(
      storedValue: storedBottomNavBarEnabled,
    );
    final shouldPersistBottomNavDefault = storedBottomNavBarEnabled == null;
    noOfHomeScreenContent.value = setBox.get("noOfHomeScreenContent") ?? 11;
    isTransitionAnimationDisabled.value =
        setBox.get("isTransitionAnimationDisabled") ?? false;
    cacheSongs.value = setBox.get('cacheSongs') ?? false;
    themeModetype.value = ThemeType.values[setBox.get('themeModeType') ?? 0];
    skipSilenceEnabled.value = setBox.get("skipSilenceEnabled") ?? false;
    loudnessNormalizationEnabled.value =
        setBox.get("loudnessNormalizationEnabled") ?? false;
    autoOpenPlayer.value = (setBox.get("autoOpenPlayer") ?? false);
    restorePlaybackSession.value =
        setBox.get("restrorePlaybackSession") ?? false;
    cacheHomeScreenData.value = setBox.get("cacheHomeScreenData") ?? true;
    playerUi.value = setBox.get('playerUi') ?? 0;
    backgroundPlayEnabled.value = setBox.get("backgroundPlayEnabled") ?? true;
    keepScreenAwake.value = setBox.get("keepScreenAwake") ?? false;
    // Read synchronous preferences before the first await, so late
    // initialization cannot overwrite a user's tap with stale values.
    exportLocationPath.value =
        setBox.get("exportLocationPath") ?? "/storage/emulated/0/Music";
    downloadingFormat.value = setBox.get('downloadingFormat') ?? "m4a";
    discoverContentType.value = setBox.get('discoverContentType') ?? "QP";
    slidableActionEnabled.value = setBox.get('slidableActionEnabled') ?? true;
    if (setBox.containsKey("piped")) {
      isLinkedWithPiped.value = setBox.get("piped")['isLoggedIn'];
    }
    stopPlyabackOnSwipeAway.value =
        setBox.get('stopPlyabackOnSwipeAway') ?? true;
    autoDownloadFavoriteSongEnabled.value =
        setBox.get("autoDownloadFavoriteSongEnabled") ?? false;

    final storedQualityIndex = setBox.get('streamingQuality') ?? 1;
    final safeQualityIndex = storedQualityIndex is int &&
            storedQualityIndex >= 0 &&
            storedQualityIndex < AudioQuality.values.length
        ? storedQualityIndex
        : 1;
    streamingQuality.value = AudioQuality.values[safeQualityIndex];

    final storedDownloadPath = setBox.get('downloadLocationPath');
    final downloadPath = storedDownloadPath is String &&
            storedDownloadPath.isNotEmpty
        ? storedDownloadPath
        : await _createInAppSongDownDir();
    downloadLocationPath.value = downloadPath;

    if (GetPlatform.isAndroid) {
      isIgnoringBatteryOptimizations.value =
          await Permission.ignoreBatteryOptimizations.isGranted;
    }

    // Persist this migration default only after all synchronous preferences
    // have been loaded. Awaiting Hive here earlier yielded control while the
    // remaining Rx settings still held defaults, allowing early UI taps to be
    // overwritten by stale values later in initialization.
    if (shouldPersistBottomNavDefault) {
      await setBox.put("isBottomNavBarEnabled", true);
    }
  }

  Future<void> setAppLanguage(String? val) async {
    if (val == null || val.isEmpty) return;
    Get.updateLocale(Locale(val));
    final musicServices = Get.find<MusicServices>();
    musicServices.hlCode = val;
    final country = Get.deviceLocale?.countryCode ?? 'US';
    musicServices.glCode = country;
    currentAppLanguageCode.value = val;
    await setBox.put('currentAppLanguageCode', val);
    await setBox.put('contentLanguage', val);
    await setBox.put('contentCountryCode', country);
    await Get.find<HomeScreenController>().refreshHome();
  }

  Future<void> setContentNumber(int? no) async {
    noOfHomeScreenContent.value = no!;
    await setBox.put("noOfHomeScreenContent", no);
  }

  Future<void> setStreamingQuality(dynamic val) async {
    if (val is! AudioQuality) return;
    final index = AudioQuality.values.indexOf(val);
    if (index < 0) return;
    await setBox.put("streamingQuality", index);
    streamingQuality.value = val;
  }

  Future<void> setPlayerUi(dynamic val) async {
    final playerCon = Get.find<PlayerController>();
    await setBox.put("playerUi", val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
  }

  Future<void> enableBottomNavBar(bool val) async {
    final homeScrCon = Get.find<HomeScreenController>();
    final playerCon = Get.find<PlayerController>();
    if (val) {
      homeScrCon.onSideBarTabSelected(3);
      isBottomNavBarEnabled.value = true;
    } else {
      isBottomNavBarEnabled.value = false;
      homeScrCon.onSideBarTabSelected(5);
    }
    if (!playerCon.initFlagForPlayer &&
        !playerCon.isMiniPlayerDismissed.value) {
      playerCon.playerPanelMinHeight.value =
          val ? 75.0 : 75.0 + Get.mediaQuery.viewPadding.bottom;
    }
    await setBox.put("isBottomNavBarEnabled", val);
  }

  Future<void> toggleSlidableAction(bool val) async {
    await setBox.put("slidableActionEnabled", val);
    slidableActionEnabled.value = val;
  }

  Future<void> changeDownloadingFormat(String? val) async {
    await setBox.put("downloadingFormat", val);
    downloadingFormat.value = val!;
  }

  Future<void> setExportedLocation() async {
    try {
      // Use Android's system folder picker instead of requiring broad storage
      // access before the user can select an export destination.
      final pickedFolderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "Select export file folder",
      );
      if (pickedFolderPath == null ||
          pickedFolderPath.isEmpty ||
          pickedFolderPath == '/') {
        return;
      }
      final directory = Directory(pickedFolderPath);
      await directory.create(recursive: true);
      await setBox.put("exportLocationPath", pickedFolderPath);
      exportLocationPath.value = pickedFolderPath;
    } catch (e) {
      printERROR("Failed to select export folder: $e");
    }
  }

  Future<void> setDownloadLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select downloads folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    await setBox.put("downloadLocationPath", pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
  }

  Future<void> disableTransitionAnimation(bool val) async {
    await setBox.put('isTransitionAnimationDisabled', val);
    isTransitionAnimationDisabled.value = val;
  }

  Future<void> clearImagesCache() async {
    final tempImgDirPath =
        "${(await getApplicationCacheDirectory()).path}/libCachedImageData";
    final tempImgDir = Directory(tempImgDirPath);
    try {
      if (await tempImgDir.exists()) {
        await tempImgDir.delete(recursive: true);
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> resetDownloadLocation() async {
    final defaultPath = "$_supportDir/Music";
    await setBox.put("downloadLocationPath", defaultPath);
    downloadLocationPath.value = defaultPath;
  }

  Future<void> onThemeChange(dynamic val) async {
    await setBox.put('themeModeType', ThemeType.values.indexOf(val));
    themeModetype.value = val;
    Get.find<ThemeController>().changeThemeModeType(val);
  }

  Future<void> onContentChange(dynamic value) async {
    await setBox.put('discoverContentType', value);
    discoverContentType.value = value;
    Get.find<HomeScreenController>().changeDiscoverContent(value);
  }

  Future<void> toggleCachingSongsValue(bool value) async {
    await setBox.put("cacheSongs", value);
    cacheSongs.value = value;
  }

  Future<void> toggleSkipSilence(bool val) async {
    final playerController = Get.find<PlayerController>();
    // Apply the player setting before publishing it as enabled in Settings.
    await playerController.toggleSkipSilence(val);
    await setBox.put('skipSilenceEnabled', val);
    skipSilenceEnabled.value = val;
  }

  Future<void> toggleLoudnessNormalization(bool val) async {
    final playerController = Get.find<PlayerController>();
    // Wait for the audio service to apply the change so rapid toggles cannot
    // leave the UI and actual player in different states.
    await playerController.toggleLoudnessNormalization(val);
    await setBox.put("loudnessNormalizationEnabled", val);
    loudnessNormalizationEnabled.value = val;
  }

  Future<void> toggleRestorePlaybackSession(bool val) async {
    await setBox.put("restrorePlaybackSession", val);
    restorePlaybackSession.value = val;
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    // Persist first so Home refreshes observe the latest preference.
    await setBox.put("cacheHomeScreenData", val);
    cacheHomeScreenData.value = val;

    // homeScreenData is a shared Hive box used by HomeScreenController.
    // Never close it from Settings: a login-triggered Home refresh can be
    // using the same box concurrently, which made subsequent settings/cache
    // operations fail intermittently with a closed-box error.
    final box = await Hive.openBox("homeScreenData");
    if (!val) {
      await box.clear();
      return;
    }

    await Get.find<HomeScreenController>()
        .cachedHomeScreenData(updateAll: true);
  }

  Future<void> toggleAutoDownloadFavoriteSong(bool val) async {
    await setBox.put("autoDownloadFavoriteSongEnabled", val);
    autoDownloadFavoriteSongEnabled.value = val;
  }

  Future<void> toggleBackgroundPlay(bool val) async {
    await setBox.put('backgroundPlayEnabled', val);
    backgroundPlayEnabled.value = val;
  }

  Future<void> toggleKeepScreenAwake(bool val) async {
    try {
      final player = Get.find<PlayerController>();
      if (val && player.buttonState.value == PlayButtonState.playing) {
        await WakelockPlus.enable();
      } else if (!val) {
        await WakelockPlus.disable();
      }
      await setBox.put('keepScreenAwake', val);
      keepScreenAwake.value = val;
    } catch (e) {
      printERROR("Failed to update keep-screen-awake setting: $e");
      // Keep the preference usable even if the platform wakelock API fails.
      await setBox.put('keepScreenAwake', val);
      keepScreenAwake.value = val;
    }
  }

  Future<void> enableIgnoringBatteryOptimizations() async {
    await Permission.ignoreBatteryOptimizations.request();
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
  }

  Future<void> toggleAutoOpenPlayer(bool val) async {
    await setBox.put('autoOpenPlayer', val);
    autoOpenPlayer.value = val;
  }

  Future<void> unlinkPiped() async {
    Get.find<PipedServices>().logout();
    isLinkedWithPiped.value = false;
    Get.find<LibraryPlaylistsController>().removePipedPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    box.clear();
    ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(Get.context!, "unlinkAlert".tr, size: SanckBarSize.MEDIUM));
    box.close();
  }

  Future<void> resetAppSettingsToDefault() async {
    // Keep MuziiNap Music's Hive-backed preference model: reset the persisted
    // values first, then restore the same defaults consumed by _setInitValue.
    final pipedAccount = setBox.get('piped');
    await setBox.clear();
    await setBox.putAll({
      'currentAppLanguageCode': 'en',
      'noOfHomeScreenContent': 11,
      'isTransitionAnimationDisabled': false,
      'cacheSongs': false,
      'themeModeType': 0,
      'skipSilenceEnabled': false,
      'loudnessNormalizationEnabled': false,
      'autoOpenPlayer': false,
      'restrorePlaybackSession': false,
      'cacheHomeScreenData': true,
      'playerUi': 0,
      'backgroundPlayEnabled': true,
      'keepScreenAwake': false,
      'exportLocationPath': '/storage/emulated/0/Music',
      'downloadingFormat': 'm4a',
      'discoverContentType': 'QP',
      'slidableActionEnabled': true,
      'stopPlyabackOnSwipeAway': true,
      'autoDownloadFavoriteSongEnabled': false,
      'streamingQuality': 1,
      'lyricsFontFamily': 'Poppins',
      'activeLyricSize': 22.0,
      'boldActiveLyric': true,
      'isBottomNavBarEnabled': true,
      'themePrimaryColor': 4278199603,
      'newVersionVisibility': updateCheckFlag,
      if (pipedAccount != null) 'piped': pipedAccount,
    });

    // Reload every Settings observable from the same persisted defaults.
    await _setInitValue();
    await Get.find<PlayerController>().toggleSkipSilence(false);
    await Get.find<PlayerController>().toggleLoudnessNormalization(false);
    await Get.find<AudioHandler>().customAction("resetEqualizer");
    await toggleKeepScreenAwake(keepScreenAwake.value);
    Get.find<ThemeController>().changeThemeModeType(themeModetype.value);
    Get.find<HomeScreenController>()
        .changeDiscoverContent(discoverContentType.value);
  }

  Future<void> toggleStopPlyabackOnSwipeAway(bool val) async {
    await setBox.put('stopPlyabackOnSwipeAway', val);
    stopPlyabackOnSwipeAway.value = val;
  }

  Future<void> closeAllDatabases() async {
    await Hive.close();
  }

  Future<String> get dbDir async =>
      (await getApplicationDocumentsDirectory()).path;
}
