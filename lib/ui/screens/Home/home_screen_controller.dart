import 'dart:async';
import '../../../services/constant.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../models/media_Item_builder.dart';
import '../../player/player_controller.dart';
import '../../../utils/helper.dart';
import '../../../models/album.dart';
import '../../../models/playlist.dart';
import '../../../models/quick_picks.dart';
import '../../../utils/home_history.dart';
import '../../../utils/youtube_auth.dart';
import '../../../models/home_mood.dart';
import '../../../services/music_service.dart';
import '../Settings/settings_screen_controller.dart';

class HomeScreenController extends GetxController with WidgetsBindingObserver {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;
  bool _homeRefreshInProgress = false;
  String _homeContextSignature = '';
  List<HomeMood> homeMoods = <HomeMood>[];
  /// Reactive snapshot of the currently authenticated YouTube account.
  ///
  /// Home used to read Hive directly from the widget tree. That made the UI
  /// race the login/account hydration path and could leave the fallback
  /// "YouTube Music" label visible even though the session was authenticated.
  final youtubeAccount = <String, dynamic>{}.obs;

  @override
  onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _homeContextSignature = _currentHomeContextSignature();
    loadContent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && tabIndex.value == 0) {
      final signature = _currentHomeContextSignature();
      final contextChanged = signature != _homeContextSignature;
      if (contextChanged) _homeContextSignature = signature;
      refreshHome(showLoading: contextChanged);
    }
  }

  Future<void> refreshHome({bool showLoading = true}) async {
    if (_homeRefreshInProgress) return;
    _homeRefreshInProgress = true;
    if (showLoading) {
      isContentFetched.value = false;
    }
    try {
      await loadContentFromNetwork(silent: false);
      // Authentication state is persisted by the login flow; Home refresh
      // itself does not need to track a separate timestamp.
    } finally {
      _homeRefreshInProgress = false;
    }
  }

  Future<void> loadContent() async {
    final box = Hive.box(appPrefsBoxName);
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    final hasYouTubeSession =
        box.get('yt_logged_in', defaultValue: false) == true;
    if (hasYouTubeSession) {
      // Account-scoped home must never reuse anonymous/stale cached shelves.
      await loadContentFromNetwork();
      return;
    }
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();

      if (loaded) {
        final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 8) {
          loadContentFromNetwork(silent: true);
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType = homeScreenData.get("quickPicksType");
      final List quickPicksData = homeScreenData.get("quickPicks");
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      fixedContent.value = fixedContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  String _currentHomeContextSignature() {
    final settings = Get.find<SettingsScreenController>();
    final language = settings.currentAppLanguageCode.value;
    final country = Get.deviceLocale?.countryCode ?? 'US';
    return YouTubeHomeContextSignature.build(
      language: language,
      country: country,
    );
  }

  Future<void> _ensureActiveYouTubeAccountInfo() async {
    final box = Hive.box(appPrefsBoxName);
    final stored = box.get('yt_accounts');

    final accounts = <String, dynamic>{};
    if (stored is Map) {
      accounts.addAll(
        stored.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }

    var activeKey = box.get('yt_active_account_key')?.toString();
    Map<String, dynamic> current = <String, dynamic>{};

    if (activeKey != null && accounts[activeKey] is Map) {
      current = Map<String, dynamic>.from(accounts[activeKey] as Map);
    } else {
      // Recover older/single-account sessions which have cookies but no
      // account-record key. This is the important compatibility path for
      // users who logged in before multi-account persistence was introduced.
      final cookies = box.get('yt_cookies')?.toString();
      if (cookies != null && cookies.trim().isNotEmpty) {
        final identity = YouTubeSessionIdentity.fromDataSyncId(
          box.get('yt_data_sync_id')?.toString(),
          authUser: box.get('yt_auth_user')?.toString(),
        );
        activeKey = identity.accountKey;
        current = <String, dynamic>{
          'cookies': cookies,
          'visitorData': box.get('yt_visitor_data')?.toString(),
          'dataSyncId': box.get('yt_data_sync_id')?.toString(),
          'authUser': identity.authUser,
          'identityToken': box.get('yt_identity_token')?.toString(),
        };
        accounts[activeKey] = current;
        await box.put('yt_accounts', accounts);
        await box.put('yt_active_account_key', activeKey);
      }
    }

    if (activeKey == null) {
      youtubeAccount.clear();
      return;
    }

    // Keep the same account metadata keys used by the reference implementation.
    // This also upgrades older installs where profile data was stored outside
    // the multi-account map.
    final legacyName = box.get('AccountName')?.toString().trim() ??
        box.get('yt_account_name')?.toString().trim() ??
        '';
    final legacyPhoto = box.get('AccountThumbUrl')?.toString().trim() ??
        box.get('yt_account_photo_url')?.toString().trim() ??
        '';
    if (current['accountName']?.toString().trim().isNotEmpty != true &&
        legacyName.isNotEmpty) {
      current['accountName'] = legacyName;
    }
    if (current['accountPhotoUrl']?.toString().trim().isNotEmpty != true &&
        legacyPhoto.isNotEmpty) {
      current['accountPhotoUrl'] = legacyPhoto;
    }

    final currentName = current['accountName']?.toString().trim() ?? '';
    final currentPhoto = current['accountPhotoUrl']?.toString().trim() ?? '';

    if (currentName.isNotEmpty && currentPhoto.isNotEmpty) {
      youtubeAccount.assignAll(current);
      return;
    }

    try {
      // MusicServices restores the active cookie/session before this call.
      // account/account_menu is the same authenticated source used by the
      // reference implementation to obtain the signed-in profile.
      final info = await _musicServices.getYouTubeAccountInfo();
      final updated = <String, dynamic>{
        ...current,
        if (info['accountName']?.toString().trim().isNotEmpty == true)
          'accountName': info['accountName'],
        if (info['channelHandle']?.toString().trim().isNotEmpty == true)
          'channelHandle': info['channelHandle'],
        if (info['accountPhotoUrl']?.toString().trim().isNotEmpty == true)
          'accountPhotoUrl': info['accountPhotoUrl'],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      accounts[activeKey] = updated;
      await box.put('yt_accounts', accounts);
      await box.put('yt_active_account_key', activeKey);

      final accountName = updated['accountName']?.toString().trim() ?? '';
      final accountPhoto = updated['accountPhotoUrl']?.toString().trim() ?? '';
      if (accountName.isNotEmpty) {
        await box.put('AccountName', accountName);
      }
      if (accountPhoto.isNotEmpty) {
        await box.put('AccountThumbUrl', accountPhoto);
      }

      youtubeAccount.assignAll(updated);
    } catch (e) {
      // Keep whatever metadata was already persisted. The session itself is
      // still valid, so the Home screen should not crash or hide the account.
      youtubeAccount.assignAll(current);
      printINFO('YouTube account profile unavailable: $e');
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box(appPrefsBoxName);
    String contentType = box.get("discoverContentType") ?? "QP";

    networkError.value = false;
    try {
      List middleContentTemp = [];
      final isAuthenticatedHome =
          box.get('yt_logged_in', defaultValue: false) == true;

      if (isAuthenticatedHome) {
        // Profile details are only needed for the welcome header; do not put
        // that optional request in front of the first Home content response.
        unawaited(_ensureActiveYouTubeAccountInfo().catchError(
          (Object error, StackTrace stackTrace) {
            printINFO('YouTube account header refresh failed: $error');
          },
        ));
      } else {
        // Do not leave the previous signed-in account visible after logout.
        youtubeAccount.clear();
      }

      // Signed-in users already get personalized shelves from FEmusic_home.
      // For anonymous Home, start the public shelves and the main Home request
      // together instead of waiting for three API calls before requesting Home.
      List<dynamic> newReleaseSections = <dynamic>[];
      List<dynamic> chartSections = <dynamic>[];
      // Moods & Genres are a public discovery section, not part of the
      // personalized authenticated Home feed. Load them for signed-in users
      // independently so a non-empty personalized feed cannot hide the chips.
      final authenticatedMoodsFuture = isAuthenticatedHome
          ? _musicServices
              .getMoodsAndGenres()
              .catchError((_) => <dynamic>[])
          : Future<List<dynamic>>.value(<dynamic>[]);

      final independentSourcesFuture = isAuthenticatedHome
          ? Future<List<dynamic>>.value(<dynamic>[])
          : Future.wait<dynamic>([
              _musicServices.getNewReleases(limit: 12)
                  .catchError((_) => <dynamic>[]),
              _musicServices.getHomeCharts(country: 'TR')
                  .catchError((_) => <dynamic>[]),
              _musicServices.getMoodsAndGenres()
                  .catchError((_) => <dynamic>[]),
            ]);

      final homeContentListMap = await _musicServices.getHome(
        limit: Get.find<SettingsScreenController>()
            .noOfHomeScreenContent
            .value,
        allSections: isAuthenticatedHome,
        onInitialResults: isAuthenticatedHome
            ? _applyAuthenticatedHomeSections
            : null,
      );

      if (isAuthenticatedHome) {
        final authenticatedMoods = await authenticatedMoodsFuture;
        homeMoods = authenticatedMoods.whereType<HomeMood>().toList();
      }

      if (!isAuthenticatedHome) {
        final independentSources = await independentSourcesFuture;
        newReleaseSections = independentSources[0] is List
            ? List<dynamic>.from(independentSources[0] as List)
            : <dynamic>[];
        chartSections = independentSources[1] is List
            ? List<dynamic>.from(independentSources[1] as List)
            : <dynamic>[];
        homeMoods = independentSources[2] is List
            ? (independentSources[2] as List).whereType<HomeMood>().toList()
            : <HomeMood>[];
      }

      // After YouTube login, Listen again must be account-scoped and
      // server-backed. Do not merge local Hive history into the signed-in
      // account: that can leak another account/device's listening history.
      if (isAuthenticatedHome) {
        try {
          final remoteHistory =
              await _musicServices.getYouTubeHistory(limit: recentlyPlayedLimit);

          if (remoteHistory.isNotEmpty) {
            final listenAgainIndex = homeContentListMap.indexWhere((section) {
              if (section is! Map) return false;
              final title = (section["title"] ?? "").toString().toLowerCase();
              return title.contains("listen again") ||
                  title.contains("speed dial");
            });

            final historySection = {
              "title": "Listen again",
              "contents": remoteHistory,
            };

            if (listenAgainIndex >= 0) {
              homeContentListMap[listenAgainIndex] = historySection;
            } else {
              homeContentListMap.insert(
                homeContentListMap.isEmpty ? 0 : 1,
                historySection,
              );
            }
          }
        } catch (e) {
          printINFO("YouTube history unavailable: $e");
        }
      }

      // For a signed-in YouTube Music account, use the complete personalized
      // Home feed exactly as returned by FEmusic_home. This includes every
      // shelf returned through section continuations (Quick picks, Listen
      // again, mixes, community playlists, new releases, videos, regional
      // shelves, and any account-specific shelves YouTube adds later).
      if (isAuthenticatedHome && homeContentListMap.isNotEmpty) {
        _applyAuthenticatedHomeSections(homeContentListMap);
        middleContentTemp.addAll(middleContent);
      }
      if (isAuthenticatedHome && middleContentTemp.isEmpty) {
        // Only pay for public fallback shelves when the personalized feed
        // actually has no middle shelves to show.
        final fallbackSources = await Future.wait<dynamic>([
          _musicServices.getNewReleases(limit: 12).catchError((_) => <dynamic>[]),
          _musicServices.getHomeCharts(country: 'TR').catchError((_) => <dynamic>[]),
        ]);
        newReleaseSections = fallbackSources[0] is List
            ? List<dynamic>.from(fallbackSources[0] as List)
            : <dynamic>[];
        chartSections = fallbackSources[1] is List
            ? List<dynamic>.from(fallbackSources[1] as List)
            : <dynamic>[];
        middleContentTemp.addAll(newReleaseSections);
        middleContentTemp.addAll(chartSections);
      }

      if (!isAuthenticatedHome && contentType == "TR") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Trending");
        if (index != -1 && index != 0) {
          quickPicks.value = QuickPicks(
              List<MediaItem>.from(homeContentListMap[index]["contents"]),
              title: "Trending");
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            quickPicks.value = QuickPicks(
                List<MediaItem>.from(charts[index]["contents"]),
                title: charts[index]['title']);
            middleContentTemp.addAll(charts);
          }
        }
      } else if (!isAuthenticatedHome && contentType == "TMV") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Top music videos");
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          quickPicks.value = QuickPicks(List<MediaItem>.from(con["contents"]),
              title: con["title"]);
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            quickPicks.value = QuickPicks(
                List<MediaItem>.from(charts[index]["contents"]),
                title: charts[index]["title"]);
            middleContentTemp.addAll(charts);
          }
        }
      } else if (!isAuthenticatedHome && contentType == "BOLI") {
        try {
          final songId = box.get("recentSongId");
          if (songId != null) {
            final rel = (await _musicServices.getContentRelatedToSong(
                songId, getContentHlCode()));
            final con = rel.removeAt(0);
            quickPicks.value =
                QuickPicks(List<MediaItem>.from(con["contents"]));
            middleContentTemp.addAll(rel);
          }
        } catch (e) {
          printERROR(
              "Seems Based on last interaction content currently not available!");
        }
      }

      if (!isAuthenticatedHome && quickPicks.value.songList.isEmpty) {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Quick picks");
        if (index != -1) {
          final con = homeContentListMap.removeAt(index);
          quickPicks.value = QuickPicks(List<MediaItem>.from(con["contents"]),
              title: "Quick picks");
        }
      }

      if (!isAuthenticatedHome) {
        middleContentTemp.addAll(newReleaseSections);
        middleContentTemp.addAll(chartSections);
      }

      middleContent.value = isAuthenticatedHome
          ? middleContentTemp
          : _setContentList(middleContentTemp);
      fixedContent.value =
          isAuthenticatedHome ? [] : _setContentList(homeContentListMap);

      isContentFetched.value = true;
      // Account-scoped Home shelves must not be written into the anonymous
      // Home cache. They can contain private recommendations and QuickPicks
      // sections that the legacy cache serializer does not model.
      if (!isAuthenticatedHome) {
        await cachedHomeScreenData(updateAll: true);
        await Hive.box(appPrefsBoxName)
            .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      }
      // ignore: unused_catch_stack
    } on NetworkError catch (r, e) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
    }
  }

  void _applyAuthenticatedHomeSections(List<dynamic> sections) {
    final parsedHome = _setAuthenticatedHomeContent(sections);
    if (parsedHome.isNotEmpty && parsedHome.first is QuickPicks) {
      quickPicks.value = parsedHome.first as QuickPicks;
      middleContent.value = parsedHome.skip(1).toList();
    } else {
      quickPicks.value = QuickPicks([]);
      middleContent.value = parsedHome;
    }
    fixedContent.value = [];
    // Render the first page of the personalized feed immediately while
    // continuation pages are fetched in the background of the same request.
    isContentFetched.value = true;
  }

  List<dynamic> _setAuthenticatedHomeContent(
      List<dynamic> sections) {
    final result = <dynamic>[];

    for (final section in sections) {
      if (section is! Map) continue;
      final title = (section["title"] ?? "").toString().trim();
      final contents = section["contents"];
      if (contents is! List || contents.isEmpty) continue;

      final songs = contents.whereType<MediaItem>().toList();
      final playlists = contents.whereType<Playlist>().toList();
      final albums = contents.whereType<Album>().toList();

      // Prefer the content type that matches the shelf. Mixed shelves can
      // occasionally contain one non-primary item; keep the dominant useful
      // type instead of dropping the whole YouTube section.
      if (playlists.isNotEmpty) {
        result.add(PlaylistContent(
          title: title.isEmpty ? "YouTube Music" : title,
          playlistList: playlists,
        ));
      } else if (albums.isNotEmpty) {
        result.add(AlbumContent(
          title: title.isEmpty ? "YouTube Music" : title,
          albumList: albums,
        ));
      } else if (songs.isNotEmpty) {
        result.add(QuickPicks(
          songs,
          title: title.isEmpty ? "YouTube Music" : title,
        ));
      }
    }

    return result;
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    final contentTemp = <dynamic>[];
    for (final content in contents) {
      if (content is QuickPicks ||
          content is PlaylistContent ||
          content is AlbumContent) {
        contentTemp.add(content);
        continue;
      }
      if (content is! Map || content["contents"] is! List) continue;
      final items = content["contents"] as List;
      if (items.isEmpty) continue;
      if (items.first is Playlist) {
        final tmp = PlaylistContent(
            playlistList: items.whereType<Playlist>().toList(),
            title: content["title"]);
        if (tmp.playlistList.length >= 2) contentTemp.add(tmp);
      } else if (items.first is Album) {
        final tmp = AlbumContent(
            albumList: items.whereType<Album>().toList(),
            title: content["title"]);
        if (tmp.albumList.length >= 2) contentTemp.add(tmp);
      } else if (items.first is MediaItem) {
        contentTemp.add(
          QuickPicks(
            items.whereType<MediaItem>().toList(),
            title: content["title"]?.toString() ?? "YouTube Music",
          ),
        );
      }
    }
    return contentTemp;
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == 'QP') {
      final homeContentListMap = await _musicServices.getHome(limit: 3);
      quickPicks_ = QuickPicks(
          List<MediaItem>.from(homeContentListMap[0]["contents"]),
          title: homeContentListMap[0]["title"]);
    } else if (val == "TMV" || val == 'TR') {
      try {
        final charts = await _musicServices.getCharts(val);
        final index = charts.indexWhere((element) =>
            element['title'] ==
            (val == "TMV" ? "Top Music Videos" : "Trending"));
        quickPicks_ = QuickPicks(
            List<MediaItem>.from(charts[index]["contents"]),
            title: charts[index]["title"]);
      } catch (e) {
        printERROR(
            "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available!");
      }
    } else {
      songId ??= Hive.box(appPrefsBoxName).get("recentSongId");
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
              songId, getContentHlCode());
          middleContent.value = _setContentList(value);
          if (value.isNotEmpty && (value[0]['title']).contains("like")) {
            quickPicks_ =
                QuickPicks(List<MediaItem>.from(value[0]["contents"]));
            Hive.box(appPrefsBoxName).put("recentSongId", songId);
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }
    if (quickPicks_ == null) return;

    quickPicks.value = quickPicks_;

    // set home content last update time
    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box(appPrefsBoxName)
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
    // Returning to Home preserves the current feed. Manual refresh remains
    // available through the Home refresh gesture and long-press Home action.
  }

  Future<void> onTrackPlayed(MediaItem item) async {
    final appPrefs = Hive.box(appPrefsBoxName);
    final isYouTubeAuthenticated =
        appPrefs.get('yt_logged_in', defaultValue: false) == true;

    if (isYouTubeAuthenticated) {
      try {
        final history = await _musicServices.getYouTubeHistory(
          limit: recentlyPlayedLimit,
        );
        if (history.isEmpty) return;

        final listenAgainIndex = middleContent.indexWhere((section) {
          return section is QuickPicks &&
              (section.title.toLowerCase().contains('listen again') ||
                  section.title.toLowerCase().contains('speed dial'));
        });
        final updated = QuickPicks(history, title: 'Listen again');

        if (listenAgainIndex >= 0) {
          final copy = List<dynamic>.from(middleContent);
          copy[listenAgainIndex] = updated;
          middleContent.value = copy;
        }
      } catch (e) {
        printINFO('Unable to refresh YouTube Listen again: $e');
      }
      return;
    }

    final localHistory = loadRecentlyPlayed();
    final history = mergeRecentlyPlayed([item], localHistory);
    final listenAgainIndex = middleContent.indexWhere((section) {
      return section is QuickPicks &&
          (section.title.toLowerCase().contains('listen again') ||
              section.title.toLowerCase().contains('speed dial'));
    });

    final updated = QuickPicks(history, title: 'Listen again');
    if (listenAgainIndex >= 0) {
      final copy = List<dynamic>.from(middleContent);
      copy[listenAgainIndex] = updated;
      middleContent.value = copy;
    } else {
      middleContent.insert(0, updated);
    }
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
    // Do not refetch Home just because the user switches tabs.
    // Pull-to-refresh and the Home icon long-press still refresh explicitly.
  }


  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
              isResultScreenOnTop
                  ? const Duration(milliseconds: 300)
                  : Duration.zero, () {
            playerCon.playerPanelMinHeight.value =
                75.0 + Get.mediaQuery.viewPadding.bottom;
          });
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList())
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
