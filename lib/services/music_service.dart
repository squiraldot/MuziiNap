// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import './utils.dart';
import '../utils/helper.dart';
import '../utils/youtube_auth.dart';
import '../models/home_mood.dart';
import 'constant.dart';
import 'continuations.dart';
import 'nav_parser.dart';

enum AudioQuality {
  Low,
  High,
}

class MusicServices extends getx.GetxService {
  final Map<String, String> _headers = {
    'user-agent': userAgent,
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'content-encoding': 'gzip',
    'origin': 'https://music.youtube.com',
    'x-youtube-client-name': '67',
    'x-youtube-client-version': '1.20260707.12.00',
    'cookie': 'CONSENT=YES+1',
  };
  
  Map<String, String> get headers => _headers;

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20260707.12.00",
      },
      'user': {}
    }
  };

  // Separate context for the player endpoint — uses ANDROID client
  // which is confirmed to return streams on music.youtube.com
  final Map<String, dynamic> _playerContext = {
    'context': {
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'userAgent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
        'osName': 'Android',
        'osVersion': '11',
      },
      'user': {}
    }
  };

  final Map<String, String> _playerHeaders = {
    'content-type': 'application/json',
    'user-agent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    'origin': domain,
    'x-youtube-client-name': '3',
    'x-youtube-client-version': '20.10.38',
  };

  @override
  void onInit() {
    _initFuture = init();
    super.onInit();
  }

  // Fail stalled API calls promptly instead of leaving Home or playback
  // requests waiting indefinitely on a socket that never completes.
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
  ));
  late Future<void> _initFuture;

  Future<void> init() async {
    //check visitor id in data base, if not generate one , set lang code
    // Keep the WEB_REMIX client version aligned with a known-good current
    // YouTube Music web client instead of inventing a date-based version.
    final signatureTimestamp = getDatestamp() - 1;
    _context['playbackContext'] = {
      'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
    };

    final appPrefsBox = Hive.box(appPrefsBoxName);
    hlCode = appPrefsBox.get('contentLanguage') ?? "en";
    glCode = appPrefsBox.get('contentCountryCode') ??
        getx.Get.deviceLocale?.countryCode ?? 'US';

    final storedAccounts = appPrefsBox.get('yt_accounts');
    final activeAccountKey = appPrefsBox.get('yt_active_account_key')?.toString();
    Map<String, dynamic>? activeAccount;
    if (storedAccounts is Map && activeAccountKey != null) {
      final candidate = storedAccounts[activeAccountKey];
      if (candidate is Map) {
        activeAccount = Map<String, dynamic>.from(candidate);
      }
    }
    final storedCookies =
        activeAccount?['cookies'] ?? appPrefsBox.get('yt_cookies');
    final storedVisitorData =
        activeAccount?['visitorData']?.toString() ??
        appPrefsBox.get('yt_visitor_data')?.toString();
    final storedDataSyncId =
        activeAccount?['dataSyncId']?.toString() ??
        appPrefsBox.get('yt_data_sync_id')?.toString();
    final storedAuthUser =
        activeAccount?['authUser']?.toString() ??
        appPrefsBox.get('yt_auth_user')?.toString();
    final storedIdentityToken =
        activeAccount?['identityToken']?.toString() ??
        appPrefsBox.get('yt_identity_token')?.toString();
    if (storedCookies != null && storedCookies.toString().isNotEmpty) {
      await updateAuthCookies(
        storedCookies.toString(),
        visitorData: storedVisitorData,
        dataSyncId: storedDataSyncId,
        authUser: storedAuthUser,
        identityToken: storedIdentityToken,
      );
    }

    if (appPrefsBox.containsKey('visitorId')) {
      final visitorData = appPrefsBox.get("visitorId");
      if (visitorData != null && !isExpired(epoch: visitorData['exp'])) {
        _headers['X-Goog-Visitor-Id'] = visitorData['id'];
        appPrefsBox.put("visitorId", {
          'id': visitorData['id'],
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2590200
        });
        printINFO("Got Visitor id ($visitorData['id']) from Box");
        return;
      }
    }

    final visitorId = await genrateVisitorId();
    if (visitorId != null) {
      _headers['X-Goog-Visitor-Id'] = visitorId;
      printINFO("New Visitor id generated ($visitorId)");
      appPrefsBox.put("visitorId", {
        'id': visitorId,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000
      });
      return;
    }
    // not able to generate in that case
    _headers['X-Goog-Visitor-Id'] =
        visitorId ?? "CgttN24wcmd5UzNSWSi2lvq2BjIKCgJKUBIEGgAgYQ%3D%3D";
  }

  Future<void> ensureReady() => _initFuture;

  Future<bool> updateAuthCookies(
    String cookies, {
    String? visitorData,
    String? dataSyncId,
    String? authUser,
    String? identityToken,
  }) async {
    final normalizedCookies = cookies.trim();
    if (normalizedCookies.isEmpty) {
      clearAuthCookies();
      return false;
    }

    _headers['cookie'] = normalizedCookies;

    if (visitorData != null && visitorData.trim().isNotEmpty) {
      _headers['X-Goog-Visitor-Id'] = visitorData.trim();
      _context['context']['client']['visitorData'] = visitorData.trim();
    }

    final identity = YouTubeSessionIdentity.fromDataSyncId(
      dataSyncId,
      authUser: authUser,
    );
    if (identity.delegatedSessionId != null) {
      _headers['X-Goog-PageId'] = identity.delegatedSessionId!;
    } else {
      _headers.remove('X-Goog-PageId');
    }
    _headers['X-Goog-AuthUser'] = identity.authUser;

    _headers['X-Youtube-Bootstrap-Logged-In'] = 'true';
    if (identityToken != null && identityToken.trim().isNotEmpty) {
      _headers['X-Youtube-Identity-Token'] = identityToken.trim();
    } else {
      _headers.remove('X-Youtube-Identity-Token');
    }
    _headers['X-Origin'] = 'https://music.youtube.com';

    final sapisid = _extractCookie(normalizedCookies, 'SAPISID') ??
        _extractCookie(normalizedCookies, '__Secure-3PAPISID') ??
        _extractCookie(normalizedCookies, '__Secure-1PAPISID');
    if (sapisid == null || sapisid.isEmpty) {
      _headers.remove('authorization');
      return false;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hash = sha1.convert(
      utf8.encode('$timestamp $sapisid https://music.youtube.com'),
    ).toString();
    final auth = 'SAPISIDHASH ${timestamp}_$hash';

    final sapisid1p = _extractCookie(normalizedCookies, '__Secure-1PAPISID');
    final sapisid3p = _extractCookie(normalizedCookies, '__Secure-3PAPISID');
    final authParts = <String>[auth];
    for (final entry in <String, String?>{
      'SAPISID1PHASH': sapisid1p,
      'SAPISID3PHASH': sapisid3p,
    }.entries) {
      final sid = entry.value;
      if (sid == null || sid.isEmpty) continue;
      final sidHash = sha1
          .convert(utf8.encode('$timestamp $sid https://music.youtube.com'))
          .toString();
      authParts.add(entry.key + ' ' + timestamp.toString() + '_' + sidHash);
    }
    _headers['authorization'] = authParts.join(' ');
    return true;
  }

  String? _extractCookie(String cookies, String name) {
    final match = RegExp(
      '(^|;\\s*)${RegExp.escape(name)}=([^;]*)',
      caseSensitive: true,
    ).firstMatch(cookies);
    return match?.group(2);
  }

  Future<bool> validateYouTubeSession() async {
    await ensureReady();
    try {
      final response = await _sendRequest(
        'browse',
        {
          ...Map<String, dynamic>.from(_context),
          'browseId': 'FEmusic_liked_playlists',
        },
      );
      final data = response.data;
      final sections = nav(
        data,
        single_column_tab + section_list,
      );
      return response.statusCode == 200 &&
          sections is List &&
          (sections.isNotEmpty || data.toString().contains('music'));
    } catch (_) {
      return false;
    }
  }

  void clearAuthCookies() {
    _headers['cookie'] = 'CONSENT=YES+1';
    for (final key in [
      'authorization',
      'X-Goog-PageId',
      'X-Goog-AuthUser',
      'X-Youtube-Bootstrap-Logged-In',
      'X-Origin',
      'X-Youtube-Identity-Token',
    ]) {
      _headers.remove(key);
    }
  }

  set hlCode(String code) {
    _context['context']['client']['hl'] = code;
  }

  set glCode(String code) {
    _context['context']['client']['gl'] = code.toUpperCase();
  }

  Future<String?> genrateVisitorId() async {
    try {
      final response =
          await dio.get(domain, options: Options(headers: _headers));
      final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
      final matches = reg.firstMatch(response.data.toString());
      String? visitorId;
      if (matches != null) {
        final ytcfg = json.decode(matches.group(1).toString());
        visitorId = ytcfg['VISITOR_DATA']?.toString();
      }
      return visitorId;
    } catch (e) {
      return null;
    }
  }

  Future<Response> _sendRequest(String action, Map<dynamic, dynamic> data,
      {additionalParams = ""}) async {
    // SAPISIDHASH is timestamped; rebuild it for every request so a
    // long-lived signed-in session does not start returning 401.
    final cookies = _headers['cookie'] ?? '';
    final sapisid = _extractCookie(cookies, 'SAPISID') ??
        _extractCookie(cookies, '__Secure-3PAPISID') ??
        _extractCookie(cookies, '__Secure-1PAPISID');
    if (sapisid != null && sapisid.isNotEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final authParts = <String>[];
      final hash = sha1
          .convert(utf8.encode('$timestamp $sapisid https://music.youtube.com'))
          .toString();
      authParts.add('SAPISIDHASH ${timestamp}_$hash');

      final sapisid1p = _extractCookie(cookies, '__Secure-1PAPISID');
      final sapisid3p = _extractCookie(cookies, '__Secure-3PAPISID');
      for (final entry in <String, String?>{
        'SAPISID1PHASH': sapisid1p,
        'SAPISID3PHASH': sapisid3p,
      }.entries) {
        final sid = entry.value;
        if (sid == null || sid.isEmpty) continue;
        final sidHash = sha1
            .convert(utf8.encode('$timestamp $sid https://music.youtube.com'))
            .toString();
        authParts.add(entry.key + ' ' + timestamp.toString() + '_' + sidHash);
      }
      _headers['authorization'] = authParts.join(' ');
    }
    try {
      final response =
          await dio.post("$baseUrl$action$fixedParms$additionalParams",
              options: Options(
                headers: _headers,
              ),
              data: data);

      if (response.statusCode == 200) {
        return response;
      }
      throw NetworkError();
    } on DioException catch (e) {
      printINFO("Error $e");
      throw NetworkError();
    }
  }
  Future<dynamic> getHome({
    int limit = 4,
    bool allSections = false,
    void Function(List<dynamic> initialResults)? onInitialResults,
  }) async {
    await ensureReady();
    final data = Map.from(_context);
    data["browseId"] = "FEmusic_home";
    final response = await _sendRequest("browse", data);
    final results = nav(response.data, single_column_tab + section_list);
    final home = [...parseMixedContent(results)];

    // Let the Home screen render the first response immediately instead of
    // waiting for every personalized shelf continuation to finish.
    onInitialResults?.call(List<dynamic>.from(home));

    final sectionList =
        nav(response.data, single_column_tab + ['sectionListRenderer']);
    // YouTube Music Home is paginated. Authenticated accounts can expose
    // many more personalized shelves than the first response page.
    // allSections deliberately walks the Home continuation until exhausted
    // (bounded by a generous safety cap) instead of the app's normal shelf
    // count preference.
    if (sectionList.containsKey('continuations')) {
      requestFunc(additionalParams) async {
        return (await _sendRequest("browse", data,
                additionalParams: additionalParams))
            .data;
      }

      parseFunc(contents) => parseMixedContent(contents);
      final remainingLimit = allSections ? 1000 : limit - home.length;
      if (remainingLimit > 0) {
        try {
          final x = await getContinuations(
            sectionList,
            'sectionListContinuation',
            remainingLimit,
            requestFunc,
            parseFunc,
          );
          home.addAll(x.cast<Map<String, dynamic>>());
        } catch (e) {
          // The first page is already usable. A continuation failure should
          // not turn a partially rendered Home feed into a network error.
          printINFO(
            'Home continuation fetch stopped after ${home.length} sections: $e',
          );
        }
      }
    }

    return home;
  }

  Future<List<dynamic>> getNewReleases({int limit = 24}) async {
    await ensureReady();
    final data = Map.from(_context);
    data['browseId'] = 'FEmusic_new_releases';
    final response = await _sendRequest('browse', data);
    final sections = nav(response.data, single_column_tab + section_list);
    final parsed = parseMixedContent(sections);
    return parsed.take(limit).toList();
  }

  Future<List<dynamic>> getHomeCharts({
    String country = 'IN',
    int limit = 24,
  }) async {
    await ensureReady();
    final data = Map.from(_context);
    data['browseId'] = 'FEmusic_charts';
    if (country.isNotEmpty) {
      data['formData'] = {
        'selectedValues': [country.toUpperCase()],
      };
    }
    final response = await _sendRequest('browse', data);
    final sections = nav(response.data, single_column_tab + section_list);
    final parsed = parseMixedContent(sections);
    return parsed.take(limit).toList();
  }

  Future<List<dynamic>> getMoodsAndGenres() async {
    await ensureReady();
    final data = Map.from(_context);
    data['browseId'] = 'FEmusic_moods_and_genres';
    final response = await _sendRequest('browse', data);
    final result = <dynamic>[];
    final seen = <String>{};

    void walk(dynamic value) {
      if (value is Map) {
        final renderer = value['musicNavigationButtonRenderer'];
        if (renderer is Map) {
          final mood = HomeMood.fromRenderer(Map<String, dynamic>.from(renderer));
          if (mood != null && seen.add(mood.browseId + '|' + mood.title)) {
            result.add(mood);
          }
        }
        for (final child in value.values) {
          if (child is Map || child is List) walk(child);
        }
      } else if (value is List) {
        for (final child in value) {
          walk(child);
        }
      }
    }

    walk(response.data);
    return result;
  }

  Future<List<dynamic>> getMoodBrowse(
    String browseId, {
    String? params,
  }) async {
    await ensureReady();
    final data = Map.from(_context);
    data['browseId'] = browseId;
    if (params != null && params.isNotEmpty) {
      data['params'] = params;
    }
    final response = await _sendRequest('browse', data);

    // Mood/category pages are not always returned through the same
    // single-column path as Home. Current YouTube Music responses can put
    // their shelves under either a single-column or a two-column browse
    // renderer. Walk the response and collect every sectionListRenderer
    // contents list so we do not show an empty page for a valid mood.
    final sectionRows = <dynamic>[];

    void collectSections(dynamic value) {
      if (value is Map) {
        final sectionList = value['sectionListRenderer'];
        if (sectionList is Map && sectionList['contents'] is List) {
          sectionRows.addAll(sectionList['contents'] as List);
        }
        for (final child in value.values) {
          if (child is Map || child is List) {
            collectSections(child);
          }
        }
      } else if (value is List) {
        for (final child in value) {
          if (child is Map || child is List) {
            collectSections(child);
          }
        }
      }
    }

    collectSections(response.data);

    // Keep order while avoiding the same shelf being parsed twice when a
    // renderer is reachable through nested wrapper objects.
    final seenRows = <String>{};
    final uniqueRows = <dynamic>[];
    for (final row in sectionRows) {
      final key = row is Map ? jsonEncode(row) : row.toString();
      if (seenRows.add(key)) uniqueRows.add(row);
    }

    return parseMixedContent(uniqueRows);
  }

  Future<Map<String, String?>> getYouTubeAccountInfo() async {
    await ensureReady();
    // Unlike ytmusicapi's _send_request helper, our _sendRequest does not
    // inject the InnerTube context automatically. The account menu endpoint
    // therefore needs the same authenticated WEB_REMIX context as other calls.
    final requestData = Map<String, dynamic>.from(_context);
    final response = await _sendRequest('account/account_menu', requestData);

    String? text(dynamic value) {
      if (value is Map) {
        final runs = value['runs'];
        if (runs is List && runs.isNotEmpty) {
          return runs
              .map((run) => run is Map ? run['text']?.toString() ?? '' : '')
              .join()
              .trim();
        }
        final simple = value['simpleText'];
        if (simple is String) return simple.trim();
      }
      return value is String ? value.trim() : null;
    }

    Map<String, String?>? account;
    void walk(dynamic value) {
      if (account != null) return;
      if (value is Map) {
        final header = value['activeAccountHeaderRenderer'];
        if (header is Map) {
          final thumbnails = header['accountPhoto'] is Map
              ? header['accountPhoto']['thumbnails']
              : null;
          String? photoUrl;
          if (thumbnails is List && thumbnails.isNotEmpty) {
            final first = thumbnails.first;
            if (first is Map) {
              photoUrl = first['url']?.toString();
            }
          }
          account = {
            'accountName': text(header['accountName']),
            'channelHandle': text(header['channelHandle']),
            'accountPhotoUrl': photoUrl,
          };
          return;
        }
        for (final child in value.values) {
          if (child is Map || child is List) walk(child);
          if (account != null) return;
        }
      } else if (value is List) {
        for (final child in value) {
          if (child is Map || child is List) walk(child);
          if (account != null) return;
        }
      }
    }

    walk(response.data);
    return account ??
        <String, String?>{
          'accountName': null,
          'channelHandle': null,
          'accountPhotoUrl': null,
        };
  }

  Future<bool> activateYouTubeAccount(String accountKey) async {
    await ensureReady();
    final box = Hive.box(appPrefsBoxName);
    final storedAccounts = box.get('yt_accounts');
    if (storedAccounts is! Map) return false;
    final account = storedAccounts[accountKey];
    if (account is! Map) return false;

    final cookies = account['cookies']?.toString();
    if (cookies == null || cookies.isEmpty) return false;

    final ready = await updateAuthCookies(
      cookies,
      visitorData: account['visitorData']?.toString(),
      dataSyncId: account['dataSyncId']?.toString(),
      authUser: account['authUser']?.toString(),
      identityToken: account['identityToken']?.toString(),
    );
    if (!ready) return false;

    await box.put('yt_active_account_key', accountKey);
    await box.put('yt_cookies', cookies);
    await box.put('yt_logged_in', true);
    if (account['visitorData'] != null) {
      await box.put('yt_visitor_data', account['visitorData']);
    }
    if (account['dataSyncId'] != null) {
      await box.put('yt_data_sync_id', account['dataSyncId']);
    }
    await box.put('yt_auth_user', account['authUser']?.toString() ?? '0');
    if (account['identityToken'] != null) {
      await box.put('yt_identity_token', account['identityToken']);
    }
    return await validateYouTubeSession();
  }

  Future<bool> recordYouTubePlayback(String videoId) async {
    await ensureReady();
    final appPrefs = Hive.box(appPrefsBoxName);
    if (appPrefs.get('yt_logged_in', defaultValue: false) != true) {
      return false;
    }

    try {
      final data = Map.from(_context);
      data['videoId'] = videoId;
      data['contentCheckOk'] = true;
      data['racyCheckOk'] = true;

      final response = (await _sendRequest('player', data)).data;
      final playbackUrl = nav(
        response,
        ['playbackTracking', 'videostatsPlaybackUrl', 'baseUrl'],
      )?.toString();
      if (playbackUrl == null || playbackUrl.isEmpty) return false;

      const alphabet =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
      final random = Random.secure();
      final cpn = List.generate(
        16,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();

      final trackingResponse = await dio.get(
        playbackUrl,
        queryParameters: {
          'ver': 2,
          'c': 'WEB_REMIX',
          'cpn': cpn,
        },
        options: Options(
          headers: {
            'origin': 'https://music.youtube.com',
            'referer': 'https://music.youtube.com/',
            'user-agent': userAgent,
            if (_headers['cookie'] != null) 'cookie': _headers['cookie']!,
            if (_headers['authorization'] != null)
              'authorization': _headers['authorization']!,
          },
          validateStatus: (_) => true,
        ),
      );

      return trackingResponse.statusCode != null &&
          trackingResponse.statusCode! >= 200 &&
          trackingResponse.statusCode! < 300;
    } catch (e) {
      printINFO('YouTube playback tracking failed: $e');
      return false;
    }
  }

  Future<List<MediaItem>> getYouTubeHistory({int limit = 20}) async {
    await ensureReady();
    if (limit <= 0) return <MediaItem>[];

    final appPrefs = Hive.box(appPrefsBoxName);
    if (appPrefs.get('yt_logged_in', defaultValue: false) != true) {
      throw StateError('Sign in to YouTube Music to view listening history.');
    }

    final data = Map<String, dynamic>.from(_context);
    data['browseId'] = 'FEmusic_history';

    // History is an authenticated InnerTube endpoint. Bound the request so
    // a stalled connection cannot leave the playlist screen loading forever.
    final response = (await _sendRequest('browse', data)
            .timeout(const Duration(seconds: 25)))
        .data;

    // Match YouTube Music's documented response path first. Recursively
    // searching for any musicShelfRenderer can accidentally collect unrelated
    // nested shelves and misses the API's explicit sign-in/error notifier.
    final sections = nav(response, single_column_tab + section_list);
    if (sections is! List) {
      throw StateError('YouTube Music returned an unexpected history response.');
    }

    final result = <MediaItem>[];
    final seen = <String>{};
    for (final section in sections) {
      if (section is! Map) continue;

      final shelfData = section['musicShelfRenderer'];
      if (shelfData is! Map) {
        final notifier = section['musicNotifierShelfRenderer'];
        if (notifier is Map) {
          final message = nav(notifier, title_text)?.toString();
          if (message != null && message.isNotEmpty) {
            throw StateError('YouTube Music history: $message');
          }
        }
        continue;
      }

      final shelf = Map<String, dynamic>.from(shelfData);
      final contents = shelf['contents'];
      if (contents is List) {
        for (final item in parsePlaylistItems(contents)) {
          if (item is! MediaItem || !seen.add(item.id)) continue;
          result.add(item);
          if (result.length >= limit) return result;
        }
      }

      // The history shelf is paginated for some accounts. Follow the API's
      // continuation token rather than silently showing only its first page.
      if (result.length < limit && shelf['continuations'] is List) {
        Future<dynamic> requestContinuation(String additionalParams) async {
          return (await _sendRequest(
            'browse',
            data,
            additionalParams: additionalParams,
          ).timeout(const Duration(seconds: 25)))
              .data;
        }

        List<MediaItem> parseContinuation(Map<String, dynamic> continuation) {
          final items = continuation['contents'];
          if (items is! List) return <MediaItem>[];
          return parsePlaylistItems(items).whereType<MediaItem>().toList();
        }

        final remaining = limit - result.length;
        final extra = await getContinuations(
          shelf,
          'musicShelfContinuation',
          remaining,
          requestContinuation,
          parseContinuation,
        );
        for (final item in extra.whereType<MediaItem>()) {
          if (seen.add(item.id)) result.add(item);
          if (result.length >= limit) return result;
        }
      }
    }

    return result;
  }

  Future<List<Artist>> getYouTubeSubscriptions({int limit = 200}) async {
    await ensureReady();
    final data = Map.from(_context);
    data['browseId'] = 'FEmusic_library_corpus_artists';
    final response = (await _sendRequest('browse', data)).data;

    dynamic findRenderer(dynamic root, String key) {
      if (root is Map) {
        final direct = root[key];
        if (direct is Map) return direct;
        for (final value in root.values) {
          final found = findRenderer(value, key);
          if (found != null) return found;
        }
      } else if (root is List) {
        for (final value in root) {
          final found = findRenderer(value, key);
          if (found != null) return found;
        }
      }
      return null;
    }

    List<Artist> parseArtists(dynamic contents) {
      if (contents is! List) return <Artist>[];
      final result = <Artist>[];
      final seen = <String>{};

      for (final item in contents) {
        if (item is! Map) continue;
        final renderer = item['musicResponsiveListItemRenderer'];
        if (renderer is! Map) continue;

        final browseId = nav(renderer, navigation_browse_id);
        final name = nav(renderer, [
          'flexColumns',
          0,
          'musicResponsiveListItemFlexColumnRenderer',
          'text',
          'runs',
          0,
          'text'
        ]);
        if (browseId == null || name == null || name.toString().trim().isEmpty) {
          continue;
        }

        final subscribers = nav(renderer, [
          'flexColumns',
          1,
          'musicResponsiveListItemFlexColumnRenderer',
          'text',
          'runs',
          0,
          'text'
        ]);
        final thumbnails = nav(renderer, thumbnail_renderer);
        if (!seen.add(browseId.toString())) continue;

        result.add(Artist.fromJson({
          'artist': name.toString().trim(),
          'browseId': browseId.toString(),
          'subscribers': subscribers?.toString() ?? '',
          'thumbnails': thumbnails is List && thumbnails.isNotEmpty
              ? thumbnails
              : [{'url': Playlist.thumbPlaceholderUrl}],
        }));

        if (result.length >= limit) break;
      }
      return result;
    }

    final shelf = findRenderer(response, 'musicShelfRenderer');
    if (shelf is! Map) return <Artist>[];

    final artists = parseArtists(shelf['contents']);
    final continuation = shelf['continuations'];
    if (artists.length >= limit || continuation is! List) {
      return artists;
    }

    requestFunc(additionalParams) async {
      return (await _sendRequest('browse', data,
              additionalParams: additionalParams))
          .data;
    }

    parseFunc(contents) => parseArtists(contents);
    final remaining = limit - artists.length;
    if (remaining > 0) {
      final extra = await getContinuations(
        shelf,
        'musicShelfContinuation',
        remaining,
        requestFunc,
        parseFunc,
      );
      artists.addAll(List<Artist>.from(extra));
    }
    return artists.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getCharts(String catogory,
      {String? countryCode}) async {
    final List<Map<String, dynamic>> charts = [];
    final data = Map.from(_context);

    data['browseId'] = 'FEmusic_charts';
    data['context']['client']["hl"] = 'en';
    if (countryCode != null) {
      data['formData'] = {
        'selectedValues': [countryCode]
      };
    }
    final response = (await _sendRequest('browse', data)).data;
    final results = nav(response, single_column_tab + section_list);
    results.removeAt(0);
    for (dynamic result in results) {
      if (nav(result, [
            "musicCarouselShelfRenderer",
            "header",
            "musicCarouselShelfBasicHeaderRenderer",
            ...title_text
          ]) ==
          "Video charts") {
        for (dynamic item in result['musicCarouselShelfRenderer']['contents']) {
          final chartItem =
              await getChartItems(parseChartsItemBrowseId(item), catogory);
          charts.add(chartItem);
        }
      } else {
        continue;
      }
    }

    return charts;
  }

  Future<Map<String, dynamic>> getChartItems(
      Map<String, dynamic> item, String catogory) async {
    final catString = catogory == "TMV" ? "Top Music Videos" : "Trending";
    if ((item['title'])!.contains(catString)) {
      final songs = (await getPlaylistOrAlbumSongs(
          playlistId: item['browseId']))['tracks'];
      final limitedSongs = songs.length > 24 ? songs.sublist(0, 24) : songs;
      return {'title': item['title'], 'contents': limitedSongs};
    }
    return {'title': item['title'], 'contents': []};
  }

  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    if (videoId.isNotEmpty && videoId.substring(0, 4) == "MPED") {
      videoId = videoId.substring(4);
    }
    final data = Map.from(_context);
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
    if (videoId == "" && playlistId == null) {
      throw Exception(
          "You must provide either a video id, a playlist id, or both");
    }
    if (videoId != "") {
      data['videoId'] = videoId;
      playlistId ??= "RDAMVM$videoId";

      if (!(radio || shuffle)) {
        data['watchEndpointMusicSupportedConfigs'] = {
          'watchEndpointMusicConfig': {
            'hasPersistentPlaylistPanel': true,
            'musicVideoType': "MUSIC_VIDEO_TYPE_ATV",
          }
        };
      }
    }

    playlistId = validatePlaylistId(playlistId!);
    data['playlistId'] = playlistId;
    final isPlaylist =
        playlistId.startsWith('PL') || playlistId.startsWith('OLA');
    if (shuffle) {
      data['params'] = "wAEB8gECKAE%3D";
    }
    if (radio) {
      data['params'] = "wAEB";
    }

    final List<dynamic> tracks = [];
    dynamic lyricsBrowseId, relatedBrowseId, playlist;
    final results = {};

    if (additionalParamsNext == null) {
      final response = (await _sendRequest("next", data)).data;
      final watchNextRenderer = nav(response, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer'
      ]);

      lyricsBrowseId = getTabBrowseId(watchNextRenderer, 1);
      relatedBrowseId = getTabBrowseId(watchNextRenderer, 2);
      if (onlyRelated) {
        return {
          'lyrics': lyricsBrowseId,
          'related': relatedBrowseId,
        };
      }

      results.addAll(nav(watchNextRenderer, [
        ...tab_content,
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer'
      ]));
      playlist = results['contents']
          .map((content) => nav(content,
              ['playlistPanelVideoRenderer', ...navigation_playlist_id]))
          .where((e) => e != null)
          .toList()
          .first;
      tracks.addAll(parseWatchPlaylist(results['contents']));
    }

    dynamic additionalParamsForNext;
    if (results.containsKey('continuations') || additionalParamsNext != null) {
      requestFunc(additionalParams) async =>
          (await _sendRequest("next", data, additionalParams: additionalParams))
              .data;
      parseFunc(contents) => parseWatchPlaylist(contents);
      final x = await getContinuations(results, 'playlistPanelContinuation',
          limit - tracks.length, requestFunc, parseFunc,
          ctokenPath: isPlaylist ? '' : 'Radio',
          isAdditionparamReturnReq: true,
          additionalParams_: additionalParamsNext);
      additionalParamsForNext = x[1];
      tracks.addAll(List<dynamic>.from(x[0]));
    }

    return {
      'tracks': tracks,
      'playlistId': playlist,
      'lyrics': lyricsBrowseId,
      'related': relatedBrowseId,
      'additionalParamsForNext': additionalParamsForNext
    };
  }

  Future<String> getAlbumBrowseId(String audioPlaylistId) async {
    final response = await dio.get("${domain}playlist",
        options: Options(headers: _headers),
        queryParameters: {"list": audioPlaylistId});
    final reg = RegExp(r'\"MPRE.+?\"');
    final matchs = reg.firstMatch(response.data.toString());
    if (matchs != null) {
      final x = (matchs[0])!;
      final res = (x.substring(1)).split("\\")[0];
      return res;
    }
    return audioPlaylistId;
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    final params = await getWatchPlaylist(videoId: videoId, onlyRelated: true);
    final data = Map.from(_context);
    data['browseId'] = params['related'];
    data['context']['client']['hl'] = hlCode;
    final response = (await _sendRequest('browse', data)).data;
    final sections = nav(response, ['contents'] + section_list);
    final x = parseMixedContent(sections);
    return x;
  }

  dynamic getLyrics(String browseId) async {
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final response = (await _sendRequest('browse', data)).data;
    return nav(
      response,
      ['contents', ...section_list_item, ...description_shelf, ...description],
    );
  }

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int limit = 3000,
      bool related = false,
      int suggestionsLimit = 0}) async {
    await ensureReady();
    String browseId = playlistId != null
        ? (playlistId.startsWith("VL") ? playlistId : "VL$playlistId")
        : albumId!;
    if (albumId != null && albumId.contains("OLAK5uy")) {
      browseId = await getAlbumBrowseId(browseId);
    }
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final Map<String, dynamic> response =
        (await _sendRequest('browse', data)).data;
    if (playlistId != null) {
      Map<String, dynamic>? findRenderer(dynamic root, String key) {
        if (root is Map) {
          final direct = root[key];
          if (direct is Map) return Map<String, dynamic>.from(direct);
          for (final value in root.values) {
            final found = findRenderer(value, key);
            if (found != null) return found;
          }
        } else if (root is List) {
          for (final value in root) {
            final found = findRenderer(value, key);
            if (found != null) return found;
          }
        }
        return null;
      }

      final header = findRenderer(response, 'musicDetailHeaderRenderer') ??
          findRenderer(response, 'musicResponsiveHeaderRenderer') ??
          <String, dynamic>{};
      final results = findRenderer(response, 'musicPlaylistShelfRenderer');

      if (results == null) {
        return {
          'id': playlistId,
          'title': nav(header, title_text) ?? '',
          'thumbnails': nav(header, thumnail_cropped) ?? [],
          'description': nav(header, description) ?? '',
          'tracks': <MediaItem>[],
        };
      }

      final Map<String, dynamic> playlist = {
        'id': results['playlistId'] ?? playlistId,
      };

      playlist['title'] = nav(header, title_text);
      playlist['thumbnails'] = nav(header, thumnail_cropped) ??
          nav(header, [
            "thumbnail",
            "musicThumbnailRenderer",
            "thumbnail",
            "thumbnails"
          ]);
      playlist["description"] = nav(header, description);
      final int runCount = header['subtitle']['runs'].length;
      if (runCount > 1) {
        playlist['author'] = {
          'name': nav(header, subtitle2),
          'id': nav(header, ['subtitle', 'runs', 2] + navigation_browse_id)
        };
        if (runCount == 5) {
          playlist['year'] = nav(header, subtitle3);
        }
      }

      final secondSubtitleRuns =
          (nav(header, ['secondSubtitle', 'runs']) as List?) ?? const [];
      int songCount = 0;
      for (final run in secondSubtitleRuns) {
        final text = run is Map ? run['text']?.toString() ?? '' : '';
        final match = RegExp(r'([0-9][0-9,]*)').firstMatch(text);
        if (match != null) {
          songCount = int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
          if (songCount > 0) break;
        }
      }
      if (secondSubtitleRuns.length > 1) {
        playlist['duration'] = secondSubtitleRuns.last['text']?.toString();
      }
      playlist['trackCount'] = songCount;

      requestFuncCountinuation(cont) async =>
          (await _sendRequest("browse", {...data, ...cont})).data;

      final initialContents =
          results['contents'] is List ? results['contents'] as List : const [];
      playlist['tracks'] = parsePlaylistItems(initialContents);

      if (songCount > 0) {
        limit = songCount;
      }
      if (initialContents.isNotEmpty &&
          initialContents.last is Map &&
          nav(initialContents.last, CONTINUATION_TOKEN) != null) {
        List<dynamic> parseFunc(contents) => parsePlaylistItems(contents);
        playlist['tracks'] = [
          ...(playlist['tracks'] as List),
          ...(await getContinuationsPlaylist(
              results, limit, requestFuncCountinuation, parseFunc))
        ];
      }
      playlist['duration_seconds'] = sumTotalDuration(playlist);
      return playlist;
    }

    //album content
    final album = parseAlbumHeader(response);
    dynamic results = nav(
          response,
          [
            'contents',
            "twoColumnBrowseResultsRenderer",
            "secondaryContents",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        ) ??
        nav(
          response,
          [
            'contents',
            "singleColumnBrowseResultsRenderer",
            "tabs",
            0,
            "tabRenderer",
            "content",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        );

    album['tracks'] = parsePlaylistItems(results['contents'],
        artistsM: album['artists'],
        thumbnailsM: album["thumbnails"],
        albumIdName: {"id": albumId, 'name': album['title']},
        albumYear: album['year'],
        isAlbum: true);
    results = nav(
      response,
      [...single_column_tab, ...section_list, 1, 'musicCarouselShelfRenderer'],
    );
    if (results != null) {
      List contents = [];
      if (results.runtimeType.toString().contains("Iterable") ||
          results.runtimeType.toString().contains("List")) {
        for (dynamic result in results) {
          contents.add(parseAlbum(result['musicTwoRowItemRenderer']));
        }
      } else {
        contents
            .add(parseAlbum(results['contents'][0]['musicTwoRowItemRenderer']));
      }
      album['other_versions'] = contents;
    }
    album['duration_seconds'] = sumTotalDuration(album);

    return album;
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    final data = Map.from(_context);
    data['input'] = queryStr;
    final res = nav(
            (await _sendRequest("music/get_search_suggestions", data)).data,
            ['contents', 0, 'searchSuggestionsSectionRenderer', 'contents']) ??
        [];
    return res
        .map<String?>((item) {
          return (nav(item, [
            'searchSuggestionRenderer',
            'navigationEndpoint',
            'searchEndpoint',
            'query'
          ])).toString();
        })
        .whereType<String>()
        .toList();
  }

  ///Specially created for deep-links
  Future<List> getSongWithId(String songId) async {
    final data = Map.of(_context);
    data['videoId'] = songId;
    final response = (await _sendRequest("player", data)).data;
    final category =
        nav(response, ["microformat", "microformatDataRenderer", "category"]);
    if (category == "Music" ||
        (response["videoDetails"]).containsKey("musicVideoType")) {
      final list = await getWatchPlaylist(videoId: songId);
      return [true, list['tracks']];
    }
    return [false, null];
  }

  /// Fetch streaming data (adaptive formats) directly from YouTube Music
  /// Uses the ANDROID client which returns streams on music.youtube.com
  Future<List<Map<String, dynamic>>> getStreamInfo(String songId) async {
    try {
      final data = Map<String, dynamic>.from(_playerContext);
      data['videoId'] = songId;
      // Use music.youtube.com player endpoint with ANDROID client
      final response = await dio.post(
        '${domain}youtubei/v1/player?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
        options: Options(headers: {
          ..._playerHeaders,
          if (_headers.containsKey('X-Goog-Visitor-Id'))
            'X-Goog-Visitor-Id': _headers['X-Goog-Visitor-Id']!,
        }),
        data: data,
      );
      if (response.statusCode == 200 && response.data.containsKey('streamingData')) {
        final adaptive = response.data['streamingData']['adaptiveFormats'] as List?;
        if (adaptive != null && adaptive.isNotEmpty) {
          return adaptive
              .where((f) => f['mimeType'].toString().contains('audio'))
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      // Swallow and let fallback handle it
    }
    return [];
  }

  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    final data = Map.of(_context);
    data['context']['client']["hl"] = 'en';
    data['query'] = query;

    final Map<String, dynamic> searchResults = {};
    final filters = [
      'albums',
      'artists',
      'playlists',
      'community_playlists',
      'featured_playlists',
      'songs',
      'videos'
    ];

    if (filter != null && !filters.contains(filter)) {
      throw Exception(
          'Invalid filter provided. Please use one of the following filters or leave out the parameter: ${filters.join(', ')}');
    }

    final scopes = ['library', 'uploads'];

    if (scope != null && !scopes.contains(scope)) {
      throw Exception(
          'Invalid scope provided. Please use one of the following scopes or leave out the parameter: ${scopes.join(', ')}');
    }

    if (scope == scopes[1] && filter != null) {
      throw Exception(
          'No filter can be set when searching uploads. Please unset the filter parameter when scope is set to uploads.');
    }

    final params = getSearchParams(filter, scope, ignoreSpelling);

    if (filterParams != null || params != null) {
      data['params'] = filterParams ?? params;
    }

    final response = (await _sendRequest("search", data)).data;

    if (response['contents'] == null) {
      return searchResults;
    }

    dynamic results;

    if ((response['contents']).containsKey('tabbedSearchResultsRenderer')) {
      final tabIndex =
          scope == null || filter != null ? 0 : scopes.indexOf(scope) + 1;
      results = response['contents']['tabbedSearchResultsRenderer']['tabs']
          [tabIndex]['tabRenderer']['content'];
    } else {
      results = response['contents'];
    }

    // Search Chips
    /*
    {
      "searchEndpoint": {
        "Songs": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Videos": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Albums": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Artists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Community playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Featured playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB"
      }
     */
    if (filter == null) {
      final searchChips = nav(results,
          ['sectionListRenderer', 'header', "chipCloudRenderer", "chips"]);

      searchResults['searchEndpoint'] = {};
      if (searchChips != null) {
        for (dynamic chipsItemRenderer in searchChips) {
          final chip = chipsItemRenderer['chipCloudChipRenderer'];
          final chipText = nav(chip, ['text', 'runs', 0, 'text']);
          searchResults['searchEndpoint'][chipText] =
              nav(chip, ['navigationEndpoint', 'searchEndpoint', 'params']);
        }
      }

      // now Featured playlists and community playlists are not coming in top results
      // so adding them in tab if not present
      if ((searchResults['searchEndpoint'])
              .containsKey("Community playlists") &&
          !searchResults.containsKey("Community playlists")) {
        searchResults["Community playlists"] = [];
      }

      if ((searchResults['searchEndpoint']).containsKey("Featured playlists") &&
          !searchResults.containsKey("Featured playlists")) {
        searchResults["Featured playlists"] = [];
      }
    }

    /// End Search Chips

    results = nav(results, ['sectionListRenderer', 'contents']);

    String? type;

    // Aggregate items if they are in itemSectionRenderer (new API behavior)
    List<dynamic> aggregatedItemResults = [];
    for (var res in results) {
      if (res['itemSectionRenderer'] != null &&
          res['itemSectionRenderer']['contents'] != null) {
        aggregatedItemResults.addAll(res['itemSectionRenderer']['contents']);
      }
    }

    if (aggregatedItemResults.isNotEmpty) {
      // Process the aggregated items as a single shelf
      String? typeFilter = filter;
      String category = filter == null ? "mixed" : "Search Results";

      final mixedItems = parseSearchResults(aggregatedItemResults,
          ['artist', 'playlist', 'song', 'video', 'station'], type, category);

      if (filter == null) {
        for (var item in mixedItems) {
          final itemType = item.runtimeType == MediaItem
              ? (item.artist.split(",")[0]) + "s"
              : "${item.runtimeType}s";
          if (searchResults.containsKey(itemType) &&
              (searchResults[itemType]).length < 3) {
            (searchResults[itemType] as List).add(item);
          } else if (!searchResults.containsKey(itemType)) {
            searchResults[itemType] = [item];
          }
        }
      } else {
        searchResults[category] = mixedItems;
      }
      type = typeFilter?.substring(0, typeFilter.length - 1).toLowerCase();
    }

    for (var res in results) {
      String category;
      if (res['musicShelfRenderer'] != null) {
        dynamic itemResults = res['musicShelfRenderer']['contents'];
        String? typeFilter = filter;
        category = "mixed"; // Just a default value
        final mixedItems = parseSearchResults(itemResults,
            ['artist', 'playlist', 'song', 'video', 'station'], type, category);
        if (filter == null) {
          for (var item in mixedItems) {
            final itemType = item.runtimeType == MediaItem
                ? (item.artist.split(",")[0]) + "s"
                : "${item.runtimeType}s";
            if (searchResults.containsKey(itemType) &&
                (searchResults[itemType]).length < 3) {
              (searchResults[itemType] as List).add(item);
            } else if (!searchResults.containsKey(itemType)) {
              searchResults[itemType] = [item];
            }
          }
        } else {
          category = nav(res, ['musicShelfRenderer', ...title_text]);
          searchResults[category] = parseSearchResults(
              res['musicShelfRenderer']['contents'],
              ['artist', 'playlist', 'song', 'video', 'station'],
              type,
              category);
        }
        type = typeFilter?.substring(0, typeFilter.length - 1).toLowerCase();
      } else {
        continue;
      }

      if (filter != null) {
        requestFunc(additionalParams) async =>
            (await _sendRequest("search", data,
                    additionalParams: additionalParams))
                .data;
        parseFunc(contents) => parseSearchResults(contents,
            ['artist', 'playlist', 'song', 'video', 'station'], type, category);

        if (searchResults.containsKey(category)) {
          final x = await getContinuations(
              res['musicShelfRenderer'],
              'musicShelfContinuation',
              limit - ((searchResults[category] as List).length),
              requestFunc,
              parseFunc,
              isAdditionparamReturnReq: true);

          searchResults["params"] = {
            'data': data,
            "type": type,
            "category": category,
            'additionalParams': x[1],
          };

          searchResults[category] = [
            ...(searchResults[category] as List),
            ...(x[0])
          ];
        }
      }
    }

    return searchResults;
  }

  Future<Map<String, dynamic>> getSearchContinuation(Map additionalParamsNext,
      {int limit = 10}) async {
    final data = additionalParamsNext['data'];
    final type = additionalParamsNext['type'];
    final category = additionalParamsNext['category'];
    final Map<String, dynamic> searchResults = {};

    requestFunc(additionalParams) async =>
        (await _sendRequest("search", data, additionalParams: additionalParams))
            .data;

    parseFunc(contents) => parseSearchResults(contents,
        ['artist', 'playlist', 'song', 'video', 'station'], type, category);

    final x = await getContinuations(
        {}, 'musicShelfContinuation', limit, requestFunc, parseFunc,
        isAdditionparamReturnReq: true,
        additionalParams_: additionalParamsNext['additionalParams']);

    searchResults["params"] = {
      "data": data,
      "type": type,
      "category": category,
      'additionalParams': x[1],
    };

    searchResults[category] = x[0];

    return searchResults;
  }

  Future<Map<String, dynamic>> getArtist(String channelId) async {
    if (channelId.startsWith("MPLA")) {
      channelId = channelId.substring(4);
    }
    final data = Map.from(_context);
    data['context']['client']["hl"] = 'en';
    data['browseId'] = channelId;
    final response = (await _sendRequest("browse", data)).data;
    final results = nav(response, [...single_column_tab, ...section_list]);

    final Map<String, dynamic> artist = {'description': null, 'views': null};
    final Map<String, dynamic> header = (response['header']
            ['musicImmersiveHeaderRenderer']) ??
        response['header']['musicVisualHeaderRenderer'];
    artist['name'] = nav(header, title_text);
    final descriptionShelf =
        findObjectByKey(results, description_shelf[0], isKey: true);
    if (descriptionShelf != null) {
      artist['description'] = nav(descriptionShelf, description);
      artist['views'] = descriptionShelf['subheader'] == null
          ? null
          : descriptionShelf['subheader']['runs'][0]['text'];
    }
    final dynamic subscriptionButton = header['subscriptionButton'] != null
        ? header['subscriptionButton']['subscribeButtonRenderer']
        : null;
    artist['channelId'] = channelId;
    artist['shuffleId'] = nav(header,
        ['playButton', 'buttonRenderer', ...navigation_watch_playlist_id]);
    artist['radioId'] = nav(
      header,
      ['startRadioButton', 'buttonRenderer'] + navigation_playlist_id,
    );
    artist['subscribers'] = subscriptionButton != null
        ? nav(
            subscriptionButton,
            ['subscriberCountText', 'runs', 0, 'text'],
          )
        : null;

    artist['thumbnails'] = nav(header, thumbnails);

    artist.addAll(parseArtistContents(results));
    return artist;
  }

  Future<Map<String, dynamic>> getArtistRealtedContent(
      Map<String, dynamic> browseEndpoint, String category,
      {String additionalParams = ""}) async {
    final Map<String, dynamic> result = {
      "results": [],
    };
    final data = Map.of(_context);
    browseEndpoint.remove("content");
    if (browseEndpoint.isEmpty) return result;
    data.addAll(browseEndpoint);
    final response =
        (await _sendRequest("browse", data, additionalParams: additionalParams))
            .data;
    final contents = nav(response, [
      'contents',
      'singleColumnBrowseResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
      0,
    ]);

    if (category == "Songs" || category == "Videos") {
      if (additionalParams != "") {
        final contentList = nav(response, [
          "onResponseReceivedActions",
          0,
          "appendContinuationItemsAction",
          "continuationItems"
        ]);
        final x = parsePlaylistItems(contentList);
        result['results'] = x;
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else if (contents.containsKey("gridRenderer")) {
        result['results'] = (contents['gridRenderer']['items'])
            .map((video) => parseVideo(video['musicTwoRowItemRenderer']))
            .toList();
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else {
        final collapseContent =
            nav(contents, ['musicPlaylistShelfRenderer', "collapsedItemCount"]);
        if (collapseContent != null) {
          final contentlist =
              contents['musicPlaylistShelfRenderer']['contents'];
          if (contentlist.length.toString() != collapseContent.toString()) {
            final continuationItem = contentlist.removeAt(100);
            result['results'] = parsePlaylistItems(contentlist);
            final continuationKey = nav(continuationItem, [
              "continuationItemRenderer",
              "continuationEndpoint",
              "continuationCommand",
              "token"
            ]);
            result['additionalParams'] =
                "&ctoken=$continuationKey&continuation=$continuationKey";
          } else {
            result['results'] = parsePlaylistItems(contentlist);
            result['additionalParams'] = "&ctoken=null&continuation=null";
          }
        }
        return result;
      }
    } else if (category == 'Albums' || category == 'Singles') {
      List contentlist;

      /// in continuation
      if (additionalParams != "") {
        contentlist =
            response['continuationContents']['gridContinuation']['items'];
        final continuationKey = nav(response, [
          'continuationContents',
          'gridContinuation',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
        result['additionalParams'] =
            "&ctoken=$continuationKey&continuation=$continuationKey";
      } else {
        /// in first request
        contentlist = contents['gridRenderer']['items'];

        final continuationKey = nav(contents, [
          'gridRenderer',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
        result['additionalParams'] =
            "&ctoken=$continuationKey&continuation=$continuationKey";
      }

      result['results'] = category == 'Albums'
          ? contentlist
              .map((item) => parseAlbum(item['musicTwoRowItemRenderer']))
              .whereType<Album>()
              .toList()
          : contentlist
              .map((item) => parseSingle(item['musicTwoRowItemRenderer']))
              .whereType<Album>()
              .toList();
    }
    return result;
  }

  Future<Map<String, dynamic>> getLikedSongs({int limit = 100}) async {
    return await getPlaylistOrAlbumSongs(playlistId: "LM", limit: limit);
  }

  Future<List<Playlist>> getAccountPlaylists() async {
    await ensureReady();
    final playlists = <Playlist>[];
    final seen = <String>{};

    dynamic parseRenderer(dynamic item) {
      if (item is! Map) return null;
      final renderer = item['musicTwoRowItemRenderer'] ??
          item['gridPlaylistRenderer'] ??
          item['playlistRenderer'] ??
          item['musicResponsiveListItemRenderer'];
      if (renderer is! Map) return null;

      if (item['gridPlaylistRenderer'] != null ||
          item['playlistRenderer'] != null ||
          item['musicTwoRowItemRenderer'] != null) {
        final title = nav(renderer, ['title', 'simpleText']) ??
            nav(renderer, ['title', 'runs', 0, 'text']);
        final playlistId = renderer['playlistId']?.toString() ??
            nav(renderer, ['navigationEndpoint', 'browseEndpoint', 'browseId'])?.toString();
        final thumbs = nav(renderer, ['thumbnail', 'thumbnails']) ??
            nav(renderer, ['thumbnailRenderer', 'playlistThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            nav(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
        if (title != null &&
            playlistId != null &&
            playlistId.isNotEmpty &&
            playlistId != 'LM' &&
            playlistId != 'VLLM') {
          return Playlist.fromJson({
            'title': title,
            'playlistId': playlistId,
            'thumbnails': thumbs is List && thumbs.isNotEmpty
                ? thumbs
                : [{'url': Playlist.thumbPlaceholderUrl}],
            'description': 'YouTube playlist',
          });
        }
      }

      try {
        final parsed = parsePlaylist(Map<String, dynamic>.from(renderer));
        return parsed.playlistId.isNotEmpty ? parsed : null;
      } catch (_) {
        return null;
      }
    }

    void collect(dynamic root) {
      if (root is List) {
        for (final item in root) {
          collect(item);
        }
        return;
      }
      if (root is! Map) return;
      if (root.containsKey('musicTwoRowItemRenderer') ||
          root.containsKey('gridPlaylistRenderer') ||
          root.containsKey('playlistRenderer') ||
          root.containsKey('musicResponsiveListItemRenderer')) {
        final parsed = parseRenderer(root);
        if (parsed is Playlist && parsed.playlistId.isNotEmpty && seen.add(parsed.playlistId)) {
          playlists.add(parsed);
        }
      }
      for (final value in root.values) {
        if (value is Map || value is List) collect(value);
      }
    }

    String? continuation;
    for (var page = 0; page < 10; page++) {
      final request = Map<String, dynamic>.from(_context);
      if (continuation == null) {
        request['browseId'] = 'FEmusic_liked_playlists';
      } else {
        request['continuation'] = continuation;
      }

      try {
        final response = (await _sendRequest('browse', request)).data;
        if (continuation == null) {
          collect(nav(response, single_column_tab + section_list));
        } else {
          collect(nav(response, [
            'onResponseReceivedActions',
            0,
            'appendContinuationItemsAction',
            'continuationItems',
          ]));
        }

        final section = nav(response, single_column_tab + section_list);
        continuation = nav(section, [
          'continuations',
          0,
          'nextContinuationData',
          'continuation',
        ])?.toString();
        if (continuation == null || continuation.isEmpty) {
          final continuationItems = nav(response, [
            'onResponseReceivedActions',
            0,
            'appendContinuationItemsAction',
            'continuationItems',
          ]);
          if (continuationItems is List) {
            for (final item in continuationItems.reversed) {
              final token = nav(item, [
                'continuationItemRenderer',
                'continuationEndpoint',
                'continuationCommand',
                'token',
              ]);
              if (token != null && token.toString().isNotEmpty) {
                continuation = token.toString();
                break;
              }
            }
          }
        }
        if (continuation == null || continuation.isEmpty) break;
      } catch (_) {
        break;
      }
    }

    return playlists;
  }

  Future<bool> addSongToPlaylist(
      String playlistId, String videoId) async {
    await ensureReady();
    final data = Map.from(_context);
    // Playlist detail pages use VL<id>; mutations require the raw playlist ID.
    final cleanPlaylistId =
        playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;
    data['playlistId'] = cleanPlaylistId;
    data['actions'] = [
      {
        'action': 'ACTION_ADD_VIDEO',
        'addedVideoId': videoId,
      }
    ];
    try {
      final response = await _sendRequest("browse/edit_playlist", data);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<String?> getSongYear(String songId) async {
    final data = Map.from(_context);
    data['browseId'] = "MPTC$songId";
    try {
      final response = (await _sendRequest('browse', data)).data;
      String? year = nav(response, [
        "onResponseReceivedActions",
        0,
        "openPopupAction",
        "popup",
        "dismissableDialogRenderer",
        "metadata",
        "musicMultiRowListItemRenderer",
        "secondTitle",
        "runs",
        2,
        "text"
      ]);
      return year;
    } catch (e) {
      rethrow;
    }
  }

  @override
  void onClose() {
    dio.close();
    super.onClose();
  }
}

class NetworkError extends Error {
  final message = "Network Error !";
}
