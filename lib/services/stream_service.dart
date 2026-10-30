import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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

  static const Duration _requestTimeout = Duration(seconds: 5);
  static const Duration _initialHandshakeTimeout =
      Duration(milliseconds: 800);

  // Reuse one IO client so repeated player requests share pooled keep-alive
  // connections instead of paying a fresh TCP/TLS handshake on every track.
  static final Dio _innerTubeDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    sendTimeout: _requestTimeout,
    receiveTimeout: _requestTimeout,
    responseType: ResponseType.json,
    validateStatus: (status) => status != null,
  ))..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        return HttpClient()
          ..connectionTimeout = const Duration(seconds: 4)
          ..idleTimeout = const Duration(seconds: 30)
          ..maxConnectionsPerHost = 6;
      },
    );

  static const String _innerTubeApiKey =
      'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

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

  /// A slow initial WEB_REMIX handshake is cancelled before trying ANDROID.
  static Duration requestTimeoutForClient(
    String clientName, {
    bool isInitialAttempt = true,
  }) {
    if (clientName == 'WEB_REMIX' && isInitialAttempt) {
      return _initialHandshakeTimeout;
    }
    return _requestTimeout;
  }

  static Future<StreamProvider> fetch(
    String videoId, {
    bool preferYoutubeExplode = false,
    String? preferredClient,
    Map<String, String>? authenticatedHeaders,
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
    List<String> pipedInstances = [];

    try {
      final prefs = Hive.box(appPrefsBoxName);
      final visitorData = prefs.get('visitorId');
      if (visitorData is Map) {
        visitorId = (visitorData['id'] ?? '').toString();
      } else if (visitorData is String) {
        visitorId = visitorData;
      }

      pipedInstances = _getPipedInstances(prefs);
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
    );
    if (innerTube.playable) return innerTube;
    if (innerTube.statusMSG.isNotEmpty) lastFailure = innerTube.statusMSG;

    // 2. Secondary: YouTubeExplode is invoked only after all primary clients
    // fail to provide at least one validated direct audio URL.
    final youtubeExplode = await _fetchYoutubeExplode(cleanId);
    if (youtubeExplode != null && youtubeExplode.playable) {
      return youtubeExplode;
    }

    // 3. Optional last resort: configured/public Piped instances.
    final piped = await _fetchPipedStreams(cleanId, pipedInstances);
    if (piped != null && piped.playable) return piped;

    return StreamProvider(playable: false, statusMSG: lastFailure);
  }

  static List<String> _getPipedInstances(Box prefs) {
    const defaults = <String>[
      'https://pipedapi.kavin.rocks',
      'https://pipedapi.adminforge.de',
      'https://pipedapi.moomoo.me',
      'https://piped-api.lunar.icu',
    ];
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
    for (final instance in defaults) {
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
      name: 'WEB_REMIX',
      version: '1.20260707.12.00',
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/140.0.0.0 Safari/537.36',
      id: '67',
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

  /// Exposes deterministic client ordering for diagnostics and unit tests.
  static List<String> clientNamesFor({String? preferredClient}) =>
      _orderedClients(preferredClient)
          .map((client) => client.name)
          .toList(growable: false);

  static List<
      ({
        String name,
        String version,
        String userAgent,
        String id,
      })> _orderedClients(String? preferredClient) {
    final clients = List.of(_innerTubeClients);
    final index = clients.indexWhere((client) => client.name == preferredClient);
    if (index > 0) {
      final preferred = clients.removeAt(index);
      clients.insert(0, preferred);
    }
    return clients;
  }

  static Future<StreamProvider> _fetchInnerTubeClients(
    String videoId,
    String visitorId, {
    String? preferredClient,
    Map<String, String>? authenticatedHeaders,
  }) async {
    var lastFailure = 'All InnerTube clients failed';
    final clients = _orderedClients(preferredClient);
    for (var index = 0; index < clients.length; index++) {
      final client = clients[index];
      final requestTimeout = requestTimeoutForClient(
        client.name,
        isInitialAttempt: index == 0,
      );
      try {
        final result = await _fetchInnerTube(
          videoId: videoId,
          clientName: client.name,
          clientVersion: client.version,
          userAgent: client.userAgent,
          clientId: client.id,
          visitorId: visitorId,
          authenticatedHeaders: authenticatedHeaders,
          requestTimeout: requestTimeout,
        );

        if (result.playable) return result;
        if (result.statusMSG.isNotEmpty) {
          lastFailure = '${client.name}: ${result.statusMSG}';
        }
      } on TimeoutException {
        lastFailure =
            '${client.name}: request timed out after ${requestTimeout.inMilliseconds} ms';
      } catch (error) {
        lastFailure = error is DioException &&
                error.type == DioExceptionType.cancel
            ? '${client.name}: handshake exceeded ${requestTimeout.inMilliseconds} ms'
            : '${client.name}: request failed';
        printINFO('InnerTube ${client.name} failed: $error');
      }
    }
    return StreamProvider(playable: false, statusMSG: lastFailure);
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
  }) async {
    final cancelToken = CancelToken();
    final timeoutTimer = Timer(
      requestTimeout,
      () => cancelToken.cancel('InnerTube handshake deadline exceeded'),
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
        'hl': 'en',
        'gl': 'US',
      };
      if (visitorId.isNotEmpty) clientContext['visitorData'] = visitorId;

      final response = await _innerTubeDio.post<dynamic>(
        uri.toString(),
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
        ),
        data: {
          'context': {'client': clientContext, 'user': <String, dynamic>{}},
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        },
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
        final normalizedReason = reasonText.toLowerCase();
        final diagnostic = normalizedReason.contains('potoken') ||
                normalizedReason.contains('proof of origin') ||
                normalizedReason.contains('proof-of-origin')
            ? 'YouTube requires a PoToken for this client; no proof-token provider is configured.'
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

      final audioFormats = parseInnerTubeAudioFormats(formats);
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

  static List<Audio> parseInnerTubeAudioFormats(List<dynamic> formats) {
    final parsed = <Audio>[];
    for (final item in formats) {
      if (item is! Map) continue;
      final mimeType = item['mimeType']?.toString();
      final rawUrl = item['url']?.toString();
      if (!isAudioMimeType(mimeType) ||
          !isValidAudioFormatUrl(rawUrl)) {
        // signatureCipher/cipher-only formats are intentionally not selected:
        // this extractor does not currently implement player-JS deciphering.
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
    return _sortFormats(parsed);
  }

  static Future<StreamProvider?> _fetchYoutubeExplode(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 8));
      final audio = manifest.audioOnly.where((stream) {
        return isValidAudioFormatUrl(stream.url.toString()) &&
            _codecFromName(stream.audioCodec) != null;
      }).toList();

      if (audio.isEmpty) return null;
      final formats = audio.map((stream) => Audio(
        itag: stream.tag,
        audioCodec: _codecFromName(stream.audioCodec)!,
        bitrate: stream.bitrate.bitsPerSecond,
        duration: 0,
        loudnessDb: 0.0,
        url: stream.url.toString(),
        size: stream.size.totalBytes,
      )).toList();

      printINFO('YouTubeExplode fallback returned validated audio formats');
      return StreamProvider(
        playable: true,
        statusMSG: 'OK',
        audioFormats: _sortFormats(formats),
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
    List<String> instances,
  ) async {
    if (instances.isEmpty) return null;

    // Piped remains the final provider fallback. Its configured instances may
    // be checked concurrently, but only after InnerTube and YouTubeExplode fail.
    final completer = Completer<StreamProvider?>();
    var pending = instances.length;
    for (final instance in instances) {
      _fetchPipedInstance(instance, videoId)
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
    String videoId,
  ) async {
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
        if (item is! Map) continue;
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

      if (formats.isEmpty) return null;
      printINFO('Piped last-resort fallback returned validated audio formats');
      return StreamProvider(
        playable: true,
        statusMSG: 'OK',
        audioFormats: _sortFormats(formats),
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
