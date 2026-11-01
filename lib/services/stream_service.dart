import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube/stream_url_decipherer.dart';
import 'youtube/player_js_service.dart';
import 'youtube/nsig_decipher_service.dart';
import 'youtube/signature_decipher_service.dart';
import 'youtube/po_token/po_token_manager.dart';
import 'youtube/po_token/po_token_request.dart';
import 'youtube/po_token/po_token_policy.dart';
import 'youtube/po_token/po_token_provider.dart';
import 'youtube/po_token/bgutil_http_po_token_provider.dart';

import 'device_adaptive_stream_selector.dart';

import '../utils/helper.dart';
import 'constant.dart';

/// Resolves audio-only streams. InnerTube is the primary extractor; external
/// extractors are deliberately sequential fallbacks, never competing races.
class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  final Map<String, String>? streamHeaders;

  StreamProvider({
    required this.playable,
    this.audioFormats,
    this.statusMSG = '',
    this.streamHeaders,
  });

  // Reuse one Dio client across tracks so InnerTube requests share the
  // underlying HttpClient connection pool instead of opening a new socket
  // for every song. The API key remains sourced from the existing constant.
  static final String _innerTubeApiKey =
      Uri.parse('https://music.youtube.com/$fixedParms')
          .queryParameters['key']!;
  static final Dio _innerTubeDio = Dio(
    BaseOptions(
      connectTimeout: _requestTimeout,
      sendTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
    ),
  )..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..connectionTimeout = _requestTimeout,
    );

  static const Duration _requestTimeout = Duration(seconds: 5);
  static final PlayerJsService _playerJsService = PlayerJsService();
  static final StreamUrlDecipherer _streamUrlDecipherer = StreamUrlDecipherer(
    nsig: NsigDecipherService(_playerJsService),
    signature: SignatureDecipherService(_playerJsService),
  );
  static const Duration _initialHandshakeTimeout =
      Duration(milliseconds: 1500);

  static const PoTokenPolicy _poTokenPolicy = PoTokenPolicy();
  static PoTokenManager _poTokenManager = PoTokenManager(
    provider: const UnavailablePoTokenProvider(),
  );
  static bool _poTokenProviderOverridden = false;
  static String? _configuredPoTokenProviderUrl;

  /// Allows the host application or tests to replace the attestation provider.
  /// The provider is never assumed to exist and unsupported requests fail closed.
  static void configurePoTokenProvider(PoTokenProvider provider) {
    _poTokenProviderOverridden = true;
    _poTokenManager.clear();
    _poTokenManager = PoTokenManager(provider: provider);
  }

  // Bump when URL playability semantics change so previously cached,
  // syntactically valid but unusable InnerTube URLs are re-resolved.
  static const int streamResolverVersion = 4;
  static const Duration _urlCacheMaxAge = Duration(minutes: 10);
  static const Duration _urlExpirySafetyWindow = Duration(seconds: 60);
  static const List<String> _defaultPipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.moomoo.me',
    'https://piped-api.lunar.icu',
  ];

  /// Returns whether a persisted stream result can safely be reused.
  ///
  /// Headers are optional: Piped URLs are often self-contained and do not
  /// require request headers. Both quality slots are validated because the
  /// selected quality can change while the cached record remains in Hive.
  static bool isCachedStreamUsable(
    dynamic cacheEntry, {
    int qualityIndex = 1,
    DateTime? now,
    Duration maxAge = _urlCacheMaxAge,
  }) {
    if (cacheEntry is! Map ||
        cacheEntry['playable'] != true ||
        cacheEntry['statusMSG'] is! String ||
        cacheEntry['streamResolverVersion'] != streamResolverVersion) {
      return false;
    }

    final lowQuality = cacheEntry['lowQualityAudio'];
    final highQuality = cacheEntry['highQualityAudio'];
    if (lowQuality is! Map ||
        highQuality is! Map ||
        lowQuality['audioCodec'] is! String ||
        highQuality['audioCodec'] is! String ||
        !isValidAudioFormatUrl(lowQuality['url']?.toString()) ||
        !isValidAudioFormatUrl(highQuality['url']?.toString())) {
      return false;
    }

    final headers = cacheEntry['streamHeaders'];
    if (headers != null &&
        (headers is! Map ||
            headers.entries.any(
              (entry) => entry.key is! String || entry.value is! String,
            ))) {
      return false;
    }

    // Only the currently selected quality must be fresh. The other quality
    // slot still needs a valid URL shape because HMStreamingData deserializes
    // both slots, but it may be refreshed later if the user changes quality.
    final selectedAudio = qualityIndex == 0 ? lowQuality : highQuality;
    final selectedUrl = selectedAudio['url'].toString();
    final currentTime = now ?? DateTime.now();
    final uri = Uri.tryParse(selectedUrl);
    final expiryValue = uri?.queryParameters['expire'] ??
        uri?.queryParameters['expires'];

    if (expiryValue != null) {
      final expiry = int.tryParse(expiryValue);
      return expiry != null &&
          expiry > currentTime.millisecondsSinceEpoch ~/ 1000 +
              _urlExpirySafetyWindow.inSeconds;
    }

    // Providers without an explicit expiry are cached for a short bounded
    // period. Old records without a timestamp are deliberately re-resolved.
    final resolvedAtValue = cacheEntry['resolvedAt'];
    final resolvedAt = resolvedAtValue is num
        ? resolvedAtValue.toInt()
        : int.tryParse(resolvedAtValue?.toString() ?? '');
    if (resolvedAt == null || resolvedAt <= 0) return false;
    final age = currentTime.millisecondsSinceEpoch - resolvedAt;
    return age >= 0 && age <= maxAge.inMilliseconds;
  }

  /// A stream URL must be an absolute HTTPS URL without embedded credentials.
  /// We intentionally don't restrict the hostname because configured Piped
  /// instances may serve media from their own HTTPS domains.
  static bool isValidAudioFormatUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return false;
    final uri = Uri.tryParse(rawUrl.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static bool isAudioMimeType(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType.trim().toLowerCase().startsWith('audio/');
  }

  /// Validates a server-issued stream URL without rewriting its signed query.
  /// Mutating cpn/signature/n/expiry can invalidate a provider-issued URL.
  static String prepareStreamUrl(String rawUrl) {
    final normalized = rawUrl.trim();
    if (!isValidAudioFormatUrl(normalized)) {
      throw FormatException('Expected an absolute HTTPS media URL');
    }
    return normalized;
  }

  /// Native media headers only; never forward account cookies or InnerTube
  /// authorization headers to a separate media host.
  static Map<String, String> buildMediaRequestHeaders(String userAgent) => {
        'User-Agent': userAgent,
        'Accept': '*/*',
      };

  /// Bound the first-choice VISIONOS handshake; other clients remain available
  /// as staggered fallbacks if the primary endpoint is slow or unavailable.
  static Duration requestTimeoutForClient(
    String clientName, {
    bool isInitialAttempt = true,
  }) {
    if (clientName == 'VISIONOS' && isInitialAttempt) {
      return _initialHandshakeTimeout;
    }
    return _requestTimeout;
  }

  static Future<StreamProvider> fetch(
    String videoId, {
    bool preferYoutubeExplode = false,
    String? preferredClient,
    Map<String, String>? authenticatedHeaders,
    DeviceStreamProfile? deviceProfile,
    Future<String?> Function()? refreshVisitorId,
  }) async {
    // Retain the legacy argument for source compatibility. Client selection
    // is deterministic; the caller may promote a different context on retry.
    final cleanId =
        videoId.startsWith('MPED') ? videoId.substring(4) : videoId;
    if (cleanId.isEmpty) {
      return StreamProvider(
        playable: false,
        statusMSG: 'Invalid video ID',
      );
    }

    String lastFailure = 'No supported audio stream was returned';
    String visitorId = '';
    String language = 'en';
    String country = 'US';
    List<String> pipedInstances = _defaultPipedInstances;

    try {
      final prefs = Hive.box(appPrefsBoxName);
      final savedLanguage = prefs.get('contentLanguage')?.toString().trim();
      final savedCountry = prefs.get('contentCountryCode')?.toString().trim();
      if (savedLanguage != null && savedLanguage.isNotEmpty) {
        language = savedLanguage;
      }
      if (savedCountry != null &&
          RegExp(r'^[A-Za-z]{2}$').hasMatch(savedCountry)) {
        country = savedCountry.toUpperCase();
      }
      final visitorData = prefs.get('visitorId');
      if (visitorData is Map) {
        visitorId = (visitorData['id'] ?? '').toString();
      } else if (visitorData is String) {
        visitorId = visitorData;
      }

      pipedInstances = _getPipedInstances(prefs);
      if (!_poTokenProviderOverridden) {
        final poTokenProviderUrl =
            prefs.get('youtubePoTokenProviderUrl')?.toString().trim();
        if (poTokenProviderUrl != _configuredPoTokenProviderUrl) {
          _configuredPoTokenProviderUrl = poTokenProviderUrl;
          if (poTokenProviderUrl != null && poTokenProviderUrl.isNotEmpty) {
          try {
            _poTokenManager = PoTokenManager(
              provider: BgutilHttpPoTokenProvider(baseUrl: poTokenProviderUrl),
            );
          } catch (_) {
            _poTokenManager = PoTokenManager(
              provider: const UnavailablePoTokenProvider(),
            );
          }
          } else {
            _poTokenManager = PoTokenManager(
              provider: const UnavailablePoTokenProvider(),
            );
          }
        }
      }
      // VISIONOS needs a visitorData value. If startup could not obtain one,
      // make one bounded refresh attempt before asking the player endpoint.
      if (visitorId.isEmpty && refreshVisitorId != null) {
        try {
          final refreshed = await refreshVisitorId()
              .timeout(const Duration(seconds: 3));
          if (refreshed != null && refreshed.trim().isNotEmpty) {
            visitorId = refreshed.trim();
            await prefs.put('visitorId', {
              'id': visitorId,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000,
            });
          }
        } catch (error) {
          printINFO('Unable to refresh YouTube visitor data: $error');
        }
      }
    } catch (error) {
      // Hive may not be available in isolated tests or early startup. The
      // anonymous InnerTube request can still be attempted.
      printINFO('Unable to read stream preferences: $error');
    }

    // 1. Primary: try supported InnerTube player clients in the selected order.
    final innerTube = await _fetchInnerTubeClients(
      cleanId,
      visitorId,
      preferredClient: preferredClient,
      authenticatedHeaders: authenticatedHeaders,
      deviceProfile: deviceProfile,
      language: language,
      country: country,
    );
    if (innerTube.playable) return innerTube;
    if (innerTube.statusMSG.isNotEmpty) lastFailure = innerTube.statusMSG;

    // YouTube can silently stop accepting a previously persisted visitorData.
    // Refresh it only for bot/visitor/403-style refusals, then retry InnerTube
    // once before falling back to another extractor.
    final normalizedFailure = innerTube.statusMSG.toLowerCase();
    // Do not rotate visitor ids for an IP-wide bot block: current field
    // reports show that doing so does not clear it and only adds latency.
    final visitorRejected = normalizedFailure.contains('visitor');
    if (visitorRejected && refreshVisitorId != null) {
      try {
        final refreshed = await refreshVisitorId()
            .timeout(const Duration(seconds: 3));
        if (refreshed != null && refreshed.trim().isNotEmpty) {
          visitorId = refreshed.trim();
          try {
            final prefs = Hive.box(appPrefsBoxName);
            await prefs.put('visitorId', {
              'id': visitorId,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000,
            });
          } catch (_) {
            // A refreshed id can still be used for this request if storage is unavailable.
          }
          final retried = await _fetchInnerTubeClients(
            cleanId,
            visitorId,
            preferredClient: preferredClient,
            authenticatedHeaders: authenticatedHeaders,
            deviceProfile: deviceProfile,
            language: language,
            country: country,
          );
          if (retried.playable) return retried;
          if (retried.statusMSG.isNotEmpty) lastFailure = retried.statusMSG;
        }
      } catch (error) {
        printINFO('YouTube visitor-data recovery failed: $error');
      }
    }

    // 2. Secondary: YouTubeExplode is invoked only after all primary clients
    // fail to provide at least one validated direct audio URL.
    final youtubeExplode = await _fetchYoutubeExplode(
      cleanId,
      deviceProfile: deviceProfile,
    );
    if (youtubeExplode != null && youtubeExplode.playable) {
      return youtubeExplode;
    }
    lastFailure = '$lastFailure; YouTubeExplode fallback unavailable';

    // 3. Optional last resort: configured/public Piped instances.
    final piped = await _fetchPipedStreams(
      cleanId,
      pipedInstances,
      deviceProfile: deviceProfile,
    );
    if (piped != null && piped.playable) return piped;
    lastFailure = '$lastFailure; Piped fallback unavailable';

    return StreamProvider(playable: false, statusMSG: lastFailure);
  }

  static List<String> _getPipedInstances(Box prefs) {
    final result = <String>[];
    final configured = prefs.get('piped');
    if (configured is Map) {
      final configuredUrl = configured['instApiUrl']?.toString().trim();
      if (configuredUrl != null && configuredUrl.isNotEmpty) {
        final uri = Uri.tryParse(configuredUrl);
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            !result.contains(configuredUrl)) {
          result.add(configuredUrl);
        }
      }
    }
    for (final instance in _defaultPipedInstances) {
      if (!result.contains(instance)) result.add(instance);
    }
    return result;
  }

  static const List<
      ({
        String name,
        String version,
        String userAgent,
        String id,
      })> _innerTubeClients = [
    (
      // VISIONOS (client 101) is currently the reliable full-track client.
      // YouTube began requiring a proof-of-origin token from ANDROID_VR and
      // IOS in August 2026; VISIONOS does not currently require that token or
      // signature deciphering. Keep it first so the primary InnerTube path
      // does not depend on the token-gated clients.
      name: 'VISIONOS',
      version: '1.04',
      userAgent:
          'com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)',
      id: '101',
    ),
    (
      name: 'WEB_REMIX',
      version: '1.20260707.12.00',
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/140.0.0.0 Safari/537.36',
      id: '67',
    ),
    (
      // Keep the older embedded web client in the race. Some Android
      // networks/accounts no longer receive direct audio formats from the
      // newer WEB_REMIX identity, while WEB_EMBEDDED still serves them.
      name: 'WEB_EMBEDDED',
      version: '1.20240104.01.00',
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Safari/537.36',
      id: '56',
    ),
    (
      name: 'ANDROID',
      version: '20.10.38',
      userAgent:
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      id: '3',
    ),
    (
      name: 'ANDROID_VR',
      version: '1.43.32',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 10) gzip',
      id: '28',
    ),
    (
      name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
      version: '2.0',
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
          'Chrome/113.0.0.0 Safari/537.36',
      id: '85',
    ),
  ];

  /// Stagger non-primary client requests so a fast VISIONOS response can
  /// cancel the remaining attempts before they consume network connections.
  static Duration clientStartDelayFor(int clientIndex) => Duration(
        milliseconds: clientIndex <= 0 ? 0 : clientIndex * 200,
      );

  /// Exposes deterministic client ordering for diagnostics and unit tests.
  static List<String> clientNamesFor({String? preferredClient}) =>
      _orderedClients(preferredClient)
          .map((client) => client.name)
          .toList(growable: false);

  /// Races independent provider attempts and returns the first playable result.
  /// A failure is returned only after every attempt has completed unsuccessfully.
  /// [onWinner] is invoked once so callers can cancel requests that lost the race.
  static Future<StreamProvider> firstPlayableResult(
    Iterable<Future<StreamProvider>> attempts, {
    void Function()? onWinner,
  }) {
    final pendingAttempts = attempts.toList(growable: false);
    if (pendingAttempts.isEmpty) {
      return Future.value(StreamProvider(
        playable: false,
        statusMSG: 'No InnerTube clients were available',
      ));
    }

    final completer = Completer<StreamProvider>();
    var remaining = pendingAttempts.length;
    final failures = <String>[];

    for (final attempt in pendingAttempts) {
      attempt.then((result) {
        if (result.playable) {
          if (!completer.isCompleted) {
            completer.complete(result);
            try {
              onWinner?.call();
            } catch (_) {
              // Cancellation is best-effort; a playable URL must still win.
            }
          }
          return;
        }

        if (result.statusMSG.isNotEmpty) failures.add(result.statusMSG);
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(StreamProvider(
            playable: false,
            statusMSG: failures.isEmpty
                ? 'All InnerTube clients failed'
                : failures.join('; '),
          ));
        }
      }, onError: (Object error) {
        failures.add('InnerTube request failed: $error');
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(StreamProvider(
            playable: false,
            statusMSG: failures.isEmpty
                ? 'All InnerTube clients failed'
                : failures.join('; '),
          ));
        }
      });
    }

    return completer.future;
  }

  static List<
      ({
        String name,
        String version,
        String userAgent,
        String id,
      })> _orderedClients(String? preferredClient) {
    final clients = List.of(_innerTubeClients);
    // VISIONOS is the stable first-choice stream identity. A requested
    // recovery client is promoted immediately behind it, never ahead of it.
    final preferredIndex =
        clients.indexWhere((client) => client.name == preferredClient);
    if (preferredIndex > 0) {
      final preferred = clients.removeAt(preferredIndex);
      clients.insert(1, preferred);
    }
    return clients;
  }

  static Future<StreamProvider> _fetchInnerTubeClients(
    String videoId,
    String visitorId, {
    String? preferredClient,
    Map<String, String>? authenticatedHeaders,
    DeviceStreamProfile? deviceProfile,
    String language = 'en',
    String country = 'US',
  }) async {
    final clients = _orderedClients(
      deviceProfile?.requiresWebClient == true ? 'WEB_REMIX' : preferredClient,
    );
    if (clients.isEmpty) {
      return StreamProvider(
        playable: false,
        statusMSG: 'No InnerTube clients were available',
      );
    }

    // VISIONOS is the only currently verified full-track client in this
    // environment. Let it finish its bounded handshake before considering
    // other InnerTube identities, some of which can return capped streams.
    final primary = clients.first;
    StreamProvider primaryResult;
    try {
      primaryResult = await _fetchInnerTube(
        videoId: videoId,
        clientName: primary.name,
        clientVersion: primary.version,
        userAgent: primary.userAgent,
        clientId: primary.id,
        visitorId: visitorId,
        requestTimeout: requestTimeoutForClient(
          primary.name,
          isInitialAttempt: true,
        ),
        deviceProfile: deviceProfile,
        language: language,
        country: country,
      );
    } on TimeoutException {
      primaryResult = StreamProvider(
        playable: false,
        statusMSG:
            '${primary.name}: request timed out after ${requestTimeoutForClient(primary.name).inMilliseconds} ms',
      );
    } catch (error) {
      final message = error is DioException &&
              error.type == DioExceptionType.cancel
          ? '${primary.name}: request cancelled or timed out'
          : error is DioException && error.response?.statusCode != null
              ? '${primary.name}: HTTP ${error.response!.statusCode}'
              : error is DioException &&
                      (error.type == DioExceptionType.connectionTimeout ||
                          error.type == DioExceptionType.sendTimeout ||
                          error.type == DioExceptionType.receiveTimeout)
                  ? '${primary.name}: request timed out'
                  : '${primary.name}: request failed';
      printINFO('InnerTube ${primary.name} failed: $error');
      primaryResult = StreamProvider(playable: false, statusMSG: message);
    }

    if (primaryResult.playable) return primaryResult;

    // Only after VISIONOS fails do the remaining InnerTube clients race.
    final fallbackClients = clients.skip(1).toList(growable: false);
    if (fallbackClients.isEmpty) return primaryResult;

    final cancelTokens = <CancelToken>[];
    final attempts = <Future<StreamProvider>>[];
    for (var index = 0; index < fallbackClients.length; index++) {
      final client = fallbackClients[index];
      final requestTimeout = requestTimeoutForClient(
        client.name,
        isInitialAttempt: false,
      );
      final startDelay = clientStartDelayFor(index);
      final cancelToken = CancelToken();
      cancelTokens.add(cancelToken);

      attempts.add(() async {
        try {
          if (startDelay > Duration.zero) {
            await Future<void>.delayed(startDelay);
          }
          if (cancelToken.isCancelled) {
            return StreamProvider(
              playable: false,
              statusMSG: '${client.name}: cancelled before request',
            );
          }
          return await _fetchInnerTube(
            videoId: videoId,
            clientName: client.name,
            clientVersion: client.version,
            userAgent: client.userAgent,
            clientId: client.id,
            visitorId: visitorId,
            authenticatedHeaders:
                client.name == 'WEB_REMIX' ? authenticatedHeaders : null,
            requestTimeout: requestTimeout,
            deviceProfile: deviceProfile,
            language: language,
            country: country,
            cancelToken: cancelToken,
          );
        } on TimeoutException {
          return StreamProvider(
            playable: false,
            statusMSG:
                '${client.name}: request timed out after ${requestTimeout.inMilliseconds} ms',
          );
        } catch (error) {
          final message = error is DioException &&
                  error.type == DioExceptionType.cancel
              ? '${client.name}: request cancelled or timed out'
              : error is DioException && error.response?.statusCode != null
                  ? '${client.name}: HTTP ${error.response!.statusCode}'
                  : '${client.name}: request failed';
          printINFO('InnerTube ${client.name} failed: $error');
          return StreamProvider(playable: false, statusMSG: message);
        }
      }());
    }

    final fallback = await firstPlayableResult(
      attempts,
      onWinner: () {
        for (final token in cancelTokens) {
          if (!token.isCancelled) {
            token.cancel('Another InnerTube client returned a playable stream');
          }
        }
      },
    );
    if (fallback.playable) return fallback;

    return StreamProvider(
      playable: false,
      statusMSG: [
        primaryResult.statusMSG,
        fallback.statusMSG,
      ].where((message) => message.isNotEmpty).join('; '),
    );
  }

  static Future<StreamProvider> _fetchInnerTube({
    required String videoId,
    required String clientName,
    required String clientVersion,
    required String userAgent,
    required String clientId,
    required String visitorId,
    Map<String, String>? authenticatedHeaders,
    required Duration requestTimeout,
    DeviceStreamProfile? deviceProfile,
    String language = 'en',
    String country = 'US',
    CancelToken? cancelToken,
    String? poToken,
    bool poTokenRetried = false,
  }) async {
    final requestCancelToken = cancelToken ?? CancelToken();
    final timeoutTimer = Timer(
      requestTimeout,
      () => requestCancelToken.cancel('InnerTube handshake deadline exceeded'),
    );
    try {
      final uri = Uri.parse(
        'https://music.youtube.com/youtubei/v1/player?key=$_innerTubeApiKey',
      );
      final headers = <String, String>{
        ...?authenticatedHeaders,
        'content-type': 'application/json',
        'x-youtube-client-name': clientId,
        'x-youtube-client-version': clientVersion,
        'user-agent': userAgent,
        // HttpClient retains HTTP/1.1 connections in its shared pool. Avoid
        // forcing the hop-by-hop Connection header, which is invalid on HTTP/2.
      };
      if (visitorId.isNotEmpty) {
        headers['x-goog-visitor-id'] = visitorId;
      }

      final clientContext = <String, dynamic>{
        'clientName': clientName,
        'clientVersion': clientVersion,
        'userAgent': userAgent,
        'hl': language,
        'gl': country,
      };
      if (visitorId.isNotEmpty) clientContext['visitorData'] = visitorId;
      if (clientName == 'VISIONOS') {
        // Match the platform identity expected by YouTube's VisionOS player.
        clientContext.addAll({
          'osName': 'visionOS',
          'osVersion': '26.6.0.23O770',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
        });
      }

      final requestBody = <String, dynamic>{
        'context': {'client': clientContext, 'user': <String, dynamic>{}},
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      };
      final bodyWithToken =
          _poTokenPolicy.attachPlayerToken(requestBody, poToken);
      final response = await _innerTubeDio.post<dynamic>(
        uri.toString(),
        cancelToken: requestCancelToken,
        options: Options(
          headers: headers,
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
        ),
        data: bodyWithToken,
      );
      if (response.statusCode != HttpStatus.ok) {
        return StreamProvider(
          playable: false,
          statusMSG: 'HTTP ${response.statusCode}',
        );
      }

      final decoded = response.data;
      if (decoded is! Map) {
        return StreamProvider(
          playable: false,
          statusMSG: 'Invalid InnerTube response',
        );
      }

      final playability = decoded['playabilityStatus'];
      final streamingData = decoded['streamingData'];
      if (streamingData is! Map) {
        final reason = playability is Map
            ? (playability['reason'] ?? playability['status'])
            : null;
        final reasonText = reason?.toString() ?? 'No streaming data';
        final requiredPurpose =
            _poTokenPolicy.purposeRequiredByPlayerReason(reasonText);
        if (requiredPurpose == PoTokenPurpose.player) {
          final sessionId = _poTokenPolicy.extractSessionId(decoded);
          final isAuthenticated = authenticatedHeaders?.isNotEmpty ?? false;
          final tokenRequest = PoTokenRequest(
            clientName: clientName,
            clientVersion: clientVersion,
            videoId: videoId,
            visitorData: visitorId,
            sessionId: sessionId,
            purpose: PoTokenPurpose.player,
            binding: sessionId != null || isAuthenticated
                ? PoTokenBinding.session
                : PoTokenBinding.visitor,
            userAgent: userAgent,
          );
          if (poToken != null) {
            // The upstream explicitly rejected this token; do not keep serving
            // it from cache on the next playback attempt.
            _poTokenManager.invalidate(tokenRequest);
          } else if (!poTokenRetried) {
            final tokenResult =
                await _poTokenManager.getToken(tokenRequest);
            if (tokenResult != null) {
              // YouTube.js places Player PO Tokens in serviceIntegrityDimensions,
              // not in the URL or an unrelated request header.
              return await _fetchInnerTube(
                videoId: videoId,
                clientName: clientName,
                clientVersion: clientVersion,
                userAgent: userAgent,
                clientId: clientId,
                visitorId: visitorId,
                authenticatedHeaders: authenticatedHeaders,
                requestTimeout: requestTimeout,
                deviceProfile: deviceProfile,
                language: language,
                country: country,
                cancelToken: cancelToken,
                poToken: tokenResult.token,
                poTokenRetried: true,
              );
            }
          }
        }
        final diagnostic = requiredPurpose == PoTokenPurpose.player
            ? 'YouTube explicitly requires a Player PO Token for $clientName; no compatible provider is available.'
            : reasonText;
        return StreamProvider(
          playable: false,
          statusMSG: diagnostic,
        );
      }

      final formats = streamingData['adaptiveFormats'];
      if (formats is! List) {
        return StreamProvider(
          playable: false,
          statusMSG: 'No adaptive audio formats',
        );
      }

      String? gvsPoToken;
      if (clientName == 'WEB_REMIX') {
        final sessionId = _poTokenPolicy.extractSessionId(decoded);
        final isAuthenticated = authenticatedHeaders?.isNotEmpty ?? false;
        final gvsRequest = PoTokenRequest(
          clientName: clientName,
          clientVersion: clientVersion,
          videoId: videoId,
          visitorData: visitorId,
          sessionId: sessionId,
          purpose: PoTokenPurpose.gvs,
          // Current Web GVS PO tokens are video-ID-bound. Player tokens
          // retain their separate WEB_REMIX session/visitor binding policy.
          binding: PoTokenBinding.video,
          userAgent: userAgent,
        );
        if (!_poTokenManager.supports(gvsRequest)) {
          return StreamProvider(
            playable: false,
            statusMSG: 'WEB_REMIX requires a compatible video-bound GVS PO Token provider.',
          );
        }
        final gvsResult = await _poTokenManager.getToken(gvsRequest);
        if (gvsResult == null) {
          return StreamProvider(
            playable: false,
            statusMSG: 'Unable to generate a valid WEB_REMIX GVS PO Token.',
          );
        }
        gvsPoToken = gvsResult.token;
      }

      final playerJsUrl = _extractPlayerJsUrl(decoded);
      final decipheredFormats = await _streamUrlDecipherer.decipherFormats(
        formats,
        playerUrl: playerJsUrl,
      );
      final tokenizedFormats = _poTokenPolicy.attachGvsTokenToFormats(
        decipheredFormats,
        gvsPoToken,
      );
      final audioFormats = parseInnerTubeAudioFormats(
        tokenizedFormats,
        profile: deviceProfile,
        allowDecipheredN: true,
      );
      if (audioFormats.isEmpty) {
        final hasCipherOnlyAudio = formats.any((item) =>
            item is Map &&
            isAudioMimeType(item['mimeType']?.toString()) &&
            (item['signatureCipher'] != null || item['cipher'] != null) &&
            item['url'] == null);
        return StreamProvider(
          playable: false,
          statusMSG: hasCipherOnlyAudio
              ? 'Only cipher-protected audio formats were returned; the configured extractor could not resolve them.'
              : 'No validated direct audio formats',
        );
      }

      printINFO(
        'InnerTube $clientName returned ${audioFormats.length} validated audio formats',
      );
      return StreamProvider(
        playable: true,
        statusMSG: 'OK',
        audioFormats: audioFormats,
        // Never forward account cookies to googlevideo media hosts.
        streamHeaders: buildMediaRequestHeaders(userAgent),
      );
    } finally {
      timeoutTimer.cancel();
    }
  }

  /// Finds the player script associated with this exact InnerTube response.
  static Uri? _extractPlayerJsUrl(Map response) {
    final candidates = <dynamic>[
      (response['assets'] is Map) ? response['assets']['js'] : null,
      (response['playerConfig'] is Map &&
              response['playerConfig']['assets'] is Map)
          ? response['playerConfig']['assets']['js']
          : null,
      (response['playerResponse'] is Map &&
              response['playerResponse']['assets'] is Map)
          ? response['playerResponse']['assets']['js']
          : null,
    ];
    for (final candidate in candidates) {
      final raw = candidate?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final parsed = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
      final resolved = parsed == null
          ? null
          : parsed.hasScheme
              ? parsed
              : Uri.https('www.youtube.com', parsed.path);
      if (resolved != null &&
          resolved.scheme == 'https' &&
          (resolved.host == 'youtube.com' ||
              resolved.host == 'www.youtube.com' ||
              resolved.host == 'youtube-nocookie.com' ||
              resolved.host == 'www.youtube-nocookie.com')) {
        return resolved;
      }
    }
    return null;
  }

  static List<Audio> parseInnerTubeAudioFormats(
    List<dynamic> formats, {
    DeviceStreamProfile? profile,
    bool allowDecipheredN = false,
  }) {
    final parsed = <Audio>[];
    for (final item in formats) {
      if (item is! Map) continue;
      final mimeType = item['mimeType']?.toString();
      final rawUrl = item['url']?.toString();
      if (!isAudioMimeType(mimeType) ||
          !isValidAudioFormatUrl(rawUrl) ||
          !_isDirectlyPlayableInnerTubeUrl(
            rawUrl,
            allowDecipheredN: allowDecipheredN,
          ) ||
          _isSpatialOrWrappedAudio(item)) {
        // Raw parser callers fail closed for undeciphered n values.
        // The primary InnerTube path opts in only after StreamUrlDecipherer
        // has successfully transformed every required challenge.
        continue;
      }

      final codec = _codecFromMimeType(mimeType!);
      if (codec == null) continue;

      parsed.add(Audio(
        itag: _asInt(item['itag']),
        audioCodec: codec,
        bitrate: _asInt(item['bitrate'] ?? item['averageBitrate']),
        duration: _asInt(item['approxDurationMs']),
        loudnessDb: (item['loudnessDb'] as num?)?.toDouble() ?? 0.0,
        url: prepareStreamUrl(rawUrl!),
        size: _asInt(item['contentLength']),
      ));
    }
    return _applyDeviceProfile(parsed, profile);
  }

  /// Raw InnerTube URLs may contain an undeciphered "n" throttling token.
  /// Such URLs pass HTTPS validation but are not ready for media playback.
  static bool _isDirectlyPlayableInnerTubeUrl(
    String? rawUrl, {
    bool allowDecipheredN = false,
  }) {
    if (!isValidAudioFormatUrl(rawUrl)) return false;
    final uri = Uri.tryParse(rawUrl!.trim());
    return uri != null &&
        (allowDecipheredN || !uri.queryParameters.containsKey('n'));
  }

  static bool _isSpatialOrWrappedAudio(Map item) {
    if (item['isSpatialAudio'] == true || item['isSpatialAudioTrack'] == true) {
      return true;
    }

    for (final key in const ['spatialAudioType', 'audioSpatialFormat']) {
      final value = item[key]?.toString().trim().toLowerCase();
      if (value != null &&
          value.isNotEmpty &&
          value != 'none' &&
          value != 'false' &&
          value != '0' &&
          value != 'unknown' &&
          value != 'unspecified' &&
          value != 'spatial_audio_type_unspecified' &&
          value != 'audio_spatial_format_unspecified') {
        return true;
      }
    }

    final trackType = item['audioTrackType']?.toString().toLowerCase();
    if (trackType != null && trackType.contains('spatial')) return true;
    final track = item['audioTrack'];
    if (track is Map) {
      final nestedType = track['audioTrackType']?.toString().toLowerCase();
      if (nestedType != null && nestedType.contains('spatial')) return true;
      if (track['isSpatialAudio'] == true) return true;
    } else if (track is String && track.toLowerCase().contains('spatial')) {
      return true;
    }
    return false;
  }

  /// Keeps the requested itag when available, then falls back to the same
  /// codec. Legacy Android is intentionally AAC-only; other profiles may use
  /// the alternate audio codec if the preferred codec is absent.
  static List<Audio> _applyDeviceProfile(
    List<Audio> formats,
    DeviceStreamProfile? profile,
  ) {
    if (profile == null || formats.isEmpty) return _sortFormats(formats);

    List<Audio> formatsForCodec(Codec codec, int preferredItag) {
      final exact = formats.where((format) => format.itag == preferredItag).toList();
      if (exact.isNotEmpty) return exact;
      return formats.where((format) => format.audioCodec == codec).toList();
    }

    if (profile.prefersOpus) {
      // Keep AAC alongside Opus so the existing low-quality stream slot can
      // act as a decoder-compatible fallback without another network lookup.
      final opus = formatsForCodec(Codec.opus, 251);
      final aac = formatsForCodec(Codec.mp4a, 140);
      // The model uses first/last entries for low/high quality. Keep AAC in
      // the low slot and the preferred Opus stream in the high slot even when
      // an alternate AAC rendition advertises a larger nominal bitrate.
      return [..._sortFormats(aac), ..._sortFormats(opus)];
    }

    final aac = formatsForCodec(Codec.mp4a, 140);
    if (aac.isNotEmpty) return _sortFormats(aac);

    // On API 29+ devices AAC may be missing for a particular item. Opus is a
    // last-resort playable fallback; legacy/unknown API devices stay AAC-only.
    if (!profile.allowsOpus) return <Audio>[];
    return _sortFormats(
      formats.where((format) => format.audioCodec == Codec.opus).toList(),
    );
  }

  static Future<StreamProvider?> _fetchYoutubeExplode(
    String videoId, {
    DeviceStreamProfile? deviceProfile,
  }) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient
          .getManifest(videoId, requireWatchPage: false)
          .timeout(const Duration(seconds: 8));
      final audio = manifest.audioOnly.where((stream) {
        return isValidAudioFormatUrl(stream.url.toString()) &&
            _codecFromName(stream.audioCodec) != null;
      }).toList();

      if (audio.isEmpty) return null;
      final formats = _applyDeviceProfile(audio.map((stream) => Audio(
        itag: stream.tag,
        audioCodec: _codecFromName(stream.audioCodec)!,
        bitrate: stream.bitrate.bitsPerSecond,
        duration: 0,
        loudnessDb: 0.0,
        url: stream.url.toString(),
        size: stream.size.totalBytes,
      )).toList(), deviceProfile);

      if (formats.isEmpty) return null;
      printINFO('YouTubeExplode fallback returned validated audio formats');
      return StreamProvider(
        playable: true,
        statusMSG: 'OK',
        audioFormats: formats,
        streamHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
          'Referer': 'https://www.youtube.com/',
        },
      );
    } catch (error) {
      printINFO('YouTubeExplode fallback failed: $error');
      return null;
    } finally {
      yt.close();
    }
  }

  static Future<StreamProvider?> _fetchPipedStreams(
    String videoId,
    List<String> instances, {
    DeviceStreamProfile? deviceProfile,
  }) async {
    if (instances.isEmpty) return null;

    // Piped remains the final provider fallback. Its configured instances may
    // be checked concurrently, but only after InnerTube and YouTubeExplode fail.
    final completer = Completer<StreamProvider?>();
    var pending = instances.length;
    for (final instance in instances) {
      _fetchPipedInstance(
        instance,
        videoId,
        deviceProfile: deviceProfile,
      )
          .timeout(const Duration(seconds: 5), onTimeout: () => null)
          .then((result) {
        if (result != null && result.playable) {
          if (!completer.isCompleted) completer.complete(result);
          return;
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }, onError: (Object error) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  }

  static Future<StreamProvider?> _fetchPipedInstance(
    String baseUrl,
    String videoId, {
    DeviceStreamProfile? deviceProfile,
  }) async {
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      return null;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(base.replace(
            path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/streams/$videoId',
          ))
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['audioStreams'] is! List) return null;

      final formats = <Audio>[];
      for (final item in decoded['audioStreams'] as List) {
        if (item is! Map || _isSpatialOrWrappedAudio(item)) continue;
        final rawUrl = item['url']?.toString();
        final mimeType = item['mimeType']?.toString();
        final codecName =
            (item['codec'] ?? mimeType ?? '').toString();
        if (!isValidAudioFormatUrl(rawUrl)) continue;
        final codec = _codecFromName(codecName) ?? _codecFromMimeType(mimeType);
        if (codec == null) continue;
        if (mimeType != null &&
            mimeType.contains('/') &&
            !isAudioMimeType(mimeType)) {
          continue;
        }
        formats.add(Audio(
          itag: _asInt(item['itag']),
          audioCodec: codec,
          bitrate: _asInt(item['bitrate']),
          duration: 0,
          loudnessDb: 0.0,
          url: rawUrl!.trim(),
          size: _asInt(item['contentLength']),
        ));
      }

      final selectedFormats = _applyDeviceProfile(formats, deviceProfile);
      if (selectedFormats.isEmpty) return null;
      printINFO('Piped last-resort fallback returned validated audio formats');
      return StreamProvider(
        playable: true,
        statusMSG: 'OK',
        audioFormats: selectedFormats,
      );
    } catch (error) {
      printINFO('Piped fallback failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Codec? _codecFromMimeType(String? mimeType) {
    if (mimeType == null) return null;
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('mp4a') || normalized.contains('aac')) {
      return Codec.mp4a;
    }
    if (normalized.contains('opus')) return Codec.opus;
    return null;
  }

  static Codec? _codecFromName(String codecName) {
    final normalized = codecName.toLowerCase();
    if (normalized.contains('mp4a') ||
        normalized.contains('aac') ||
        normalized.contains('m4a')) {
      return Codec.mp4a;
    }
    if (normalized.contains('opus')) return Codec.opus;
    return null;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<Audio> _sortFormats(List<Audio> formats) {
    formats.sort((a, b) => a.bitrate.compareTo(b.bitrate));
    return formats;
  }

  Audio? get highestQualityAudio =>
      audioFormats == null || audioFormats!.isEmpty
          ? null
          : audioFormats!.last;

  Audio? get highestBitrateMp4aAudio {
    final matches =
        audioFormats?.where((item) => item.audioCodec == Codec.mp4a).toList();
    if (matches == null || matches.isEmpty) return highestQualityAudio;
    return _sortFormats(matches).last;
  }

  Audio? get highestBitrateOpusAudio {
    final matches =
        audioFormats?.where((item) => item.audioCodec == Codec.opus).toList();
    if (matches == null || matches.isEmpty) return highestQualityAudio;
    return _sortFormats(matches).last;
  }

  Audio? get lowQualityAudio =>
      audioFormats == null || audioFormats!.isEmpty
          ? null
          : audioFormats!.first;

  Map<String, dynamic> get hmStreamingData => {
        'playable': playable,
        'statusMSG': statusMSG,
        'lowQualityAudio': lowQualityAudio?.toJson(),
        'highQualityAudio': highestQualityAudio?.toJson(),
        if (streamHeaders != null) 'streamHeaders': streamHeaders,
      };
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;

  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
        'itag': itag,
        'audioCodec': audioCodec.toString(),
        'bitrate': bitrate,
        'loudnessDb': loudnessDb,
        'url': url,
        'approxDurationMs': duration,
        'size': size,
      };

  factory Audio.fromJson(dynamic json) => Audio(
        audioCodec: (json['audioCodec'] as String).contains('mp4a')
            ? Codec.mp4a
            : Codec.opus,
        itag: _asInt(json['itag']),
        duration: _asInt(json['approxDurationMs']),
        bitrate: _asInt(json['bitrate']),
        loudnessDb: (json['loudnessDb'] as num?)?.toDouble() ?? 0.0,
        url: json['url']?.toString() ?? '',
        size: _asInt(json['size']),
      );

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

enum Codec { mp4a, opus }
