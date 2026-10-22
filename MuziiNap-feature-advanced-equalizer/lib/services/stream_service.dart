import 'constant.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../utils/helper.dart';
import 'package:hive/hive.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  final Map<String, String>? streamHeaders;

  StreamProvider({
    required this.playable,
    this.audioFormats,
    this.statusMSG = "",
    this.streamHeaders,
  });

  static Future<StreamProvider> fetch(
    String videoId, {
    bool preferYoutubeExplode = false,
  }) async {
    // 1. Strip MPED prefix if present
    String cleanId = videoId;
    if (cleanId.startsWith("MPED")) {
      cleanId = cleanId.substring(4);
    }
    
    String lastStatusMsg = "Unknown error occurred";
    final appPrefsBox = Hive.box(appPrefsBoxName);
    final visitorData = appPrefsBox.get("visitorId");
    final visitorId = visitorData != null ? visitorData['id'] : '';

    // Keep the known public instances and the user's configured instance.
    final pipedInstances = [
      "https://pipedapi.kavin.rocks",
      "https://pipedapi.adminforge.de",
      "https://pipedapi.moomoo.me",
      "https://piped-api.lunar.icu",
    ];

    final piped = appPrefsBox.get('piped');
    if (piped != null &&
        piped['instApiUrl'] != null &&
        piped['instApiUrl'].toString().isNotEmpty) {
      pipedInstances.insert(0, piped['instApiUrl'].toString());
    }

    // Resolve the two primary extractors concurrently. Previously Piped was
    // awaited for up to 5 seconds before YouTubeExplode even started; dead
    // instances therefore delayed every first tap on affected networks.
    final fastResult = await _fetchFastStream(
      cleanId,
      pipedInstances,
      preferYoutubeExplode: preferYoutubeExplode,
    );
    if (fastResult != null) return fastResult;

    // Race every InnerTube client together. The first *playable* result wins;
    // failed/empty responses never prevent a slower client from succeeding.
    final innerTubeResult = await _fetchInnerTubeFallbacks(
      cleanId,
      visitorId,
    );
    if (innerTubeResult != null && innerTubeResult.playable) {
      return innerTubeResult;
    }
    if (innerTubeResult != null && innerTubeResult.statusMSG.isNotEmpty) {
      lastStatusMsg = innerTubeResult.statusMSG;
    }

    return StreamProvider(playable: false, statusMSG: lastStatusMsg);
  }

  static Future<StreamProvider?> _fetchInnerTubeFallbacks(
    String videoId,
    String visitorId,
  ) async {
    final clients = <({String name, String version, String userAgent, String id})>[
      (
        name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        version: '2.0',
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36',
        id: '85',
      ),
      (
        name: 'WEB_EMBEDDED',
        version: '1.20240104.01.00',
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        id: '56',
      ),
      (
        name: 'ANDROID',
        version: '20.10.38',
        userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        id: '3',
      ),
    ];

    final completer = Completer<StreamProvider?>();
    var pending = clients.length;
    var lastFailure = 'All InnerTube clients failed';

    void finish(StreamProvider? result, String clientName) {
      if (result != null && result.playable) {
        if (!completer.isCompleted) completer.complete(result);
        return;
      }
      if (result != null && result.statusMSG.isNotEmpty) {
        lastFailure = '$clientName: ${result.statusMSG}';
      }
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        completer.complete(
          StreamProvider(playable: false, statusMSG: lastFailure),
        );
      }
    }

    for (final client in clients) {
      _fetchInnerTube(
        videoId: videoId,
        clientName: client.name,
        clientVersion: client.version,
        userAgent: client.userAgent,
        clientId: client.id,
        visitorId: visitorId,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => StreamProvider(
          playable: false,
          statusMSG: 'InnerTube request timed out',
        ),
      ).then(
        (result) => finish(result, client.name),
        onError: (Object error) {
          printINFO('InnerTube ${client.name} race error: $error');
          finish(
            StreamProvider(playable: false, statusMSG: 'Connection error'),
            client.name,
          );
        },
      );
    }

    // Requests are independently bounded. Return immediately when the first
    // usable stream arrives; late results are ignored by the completed completer.
    return completer.future;
  }

  static Future<StreamProvider?> _fetchFastStream(
    String videoId,
    List<String> instances, {
    required bool preferYoutubeExplode,
  }) async {
    final completer = Completer<StreamProvider?>();
    var pending = 2;

    void finish(StreamProvider? result) {
      if (result != null && result.playable) {
        if (!completer.isCompleted) completer.complete(result);
        return;
      }
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    // Both pipelines race; the first usable result wins. Keep the other
    // request bounded so a broken public endpoint cannot stall playback.
    final pipedFuture = _fetchPipedStreams(videoId, instances);
    final youtubeFuture = _fetchYoutubeExplode(videoId);
    if (preferYoutubeExplode) {
      youtubeFuture.then(finish, onError: (Object _) => finish(null));
      pipedFuture.then(finish, onError: (Object _) => finish(null));
    } else {
      pipedFuture.then(finish, onError: (Object _) => finish(null));
      youtubeFuture.then(finish, onError: (Object _) => finish(null));
    }

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }

  static Future<StreamProvider?> _fetchYoutubeExplode(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 8));
      final audio = manifest.audioOnly
          .where((stream) => stream.url.toString().trim().isNotEmpty)
          .toList();
      if (audio.isEmpty) return null;

      printINFO("Successfully fetched stream from youtube_explode_dart");
      return StreamProvider(
        playable: true,
        statusMSG: "OK",
        audioFormats: audio
            .map((stream) => Audio(
                  itag: stream.tag,
                  audioCodec:
                      stream.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
                  bitrate: stream.bitrate.bitsPerSecond,
                  duration: 0,
                  loudnessDb: 0.0,
                  url: stream.url.toString(),
                  size: stream.size.totalBytes,
                ))
            .toList(),
        streamHeaders: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
          'Referer': 'https://www.youtube.com/',
        },
      );
    } catch (error) {
      printINFO("YoutubeExplode Error: $error");
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

    final completer = Completer<StreamProvider?>();
    var pending = instances.length;

    for (final instance in instances) {
      _fetchPipedInstance(instance, videoId).then((result) {
        if (result != null && result.playable) {
          if (!completer.isCompleted) completer.complete(result);
          return;
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }, onError: (Object _) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    // Bound the entire fallback phase. Individual requests also have bounded
    // connection, header, and body-read times below.
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  }

  static Future<StreamProvider?> _fetchPipedInstance(
    String baseUrl,
    String videoId,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/streams/$videoId'))
          .timeout(const Duration(seconds: 4));
      final response =
          await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != HttpStatus.ok) {
        printINFO("Piped HTTP Error ($baseUrl): ${response.statusCode}");
        return null;
      }

      final bodyString = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(bodyString);
      if (decoded is! Map || decoded['audioStreams'] is! List) return null;

      final audioStreams = (decoded['audioStreams'] as List)
          .whereType<Map>()
          .where((stream) =>
              stream['url'] is String &&
              (stream['url'] as String).trim().isNotEmpty)
          .toList();
      if (audioStreams.isEmpty) return null;

      printINFO("Successfully fetched stream from $baseUrl");
      return StreamProvider(
        playable: true,
        statusMSG: "OK",
        audioFormats: audioStreams.map((stream) {
          final codec =
              (stream['codec'] ?? stream['mimeType'] ?? '').toString();
          return Audio(
            itag: int.tryParse(stream['itag']?.toString() ?? '') ?? 0,
            audioCodec: codec.contains('mp') ? Codec.mp4a : Codec.opus,
            bitrate: int.tryParse(stream['bitrate']?.toString() ?? '') ?? 0,
            duration: 0,
            loudnessDb: 0.0,
            url: (stream['url'] as String).trim(),
            size: int.tryParse(stream['contentLength']?.toString() ?? '') ?? 0,
          );
        }).toList(),
        streamHeaders: null,
      );
    } catch (e) {
      printINFO("Piped API Error ($baseUrl): $e");
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<StreamProvider?> _fetchInnerTube({
    required String videoId,
    required String clientName,
    required String clientVersion,
    required String userAgent,
    required String clientId,
    required String visitorId,
  }) async {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await httpClient.postUrl(
          Uri.parse('https://music.youtube.com/youtubei/v1/player?key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30'))
          .timeout(const Duration(seconds: 4));
      
      request.headers.set('content-type', 'application/json');
      request.headers.set('X-YouTube-Client-Name', clientId);
      request.headers.set('X-YouTube-Client-Version', clientVersion);
      request.headers.set('User-Agent', userAgent);
      if (visitorId.isNotEmpty) {
        request.headers.set('X-Goog-Visitor-Id', visitorId);
      }

      final payload = {
        'context': {
          'client': {
            'clientName': clientName,
            'clientVersion': clientVersion,
            'userAgent': userAgent,
            'hl': 'en',
            'gl': 'US',
          },
          'user': {}
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      };

      request.write(jsonEncode(payload));
      final response = await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final bodyString = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
        final data = jsonDecode(bodyString);

        final streamingData = data['streamingData'];
        if (streamingData != null) {
          final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
          if (adaptiveFormats != null && adaptiveFormats.isNotEmpty) {
            final audioFormats = adaptiveFormats
                .where((f) => f['mimeType'].toString().contains('audio') && f['url'] != null && f['url'].toString().isNotEmpty)
                .map((e) {
              return Audio(
                itag: e['itag'] ?? 0,
                audioCodec: e['mimeType'].toString().contains('mp4a')
                    ? Codec.mp4a
                    : Codec.opus,
                bitrate: e['bitrate'] ?? e['averageBitrate'] ?? 0,
                duration: int.tryParse(e['approxDurationMs']?.toString() ?? '0') ?? 0,
                loudnessDb: (e['loudnessDb'] as num?)?.toDouble() ?? 0.0,
                url: e['url'] ?? '',
                size: int.tryParse(e['contentLength']?.toString() ?? '0') ?? 0,
              );
            }).toList();

            if (audioFormats.isNotEmpty) {
              printINFO('InnerTube fetched ${audioFormats.length} streams successfully via $clientName');
              return StreamProvider(
                playable: true,
                statusMSG: "OK",
                audioFormats: audioFormats,
                streamHeaders: {
                  'User-Agent': userAgent,
                },
              );
            } else {
              printINFO('InnerTube $clientName returned streamingData but no formats with direct URLs.');
              return StreamProvider(playable: false, statusMSG: "No direct streams available");
            }
          }
        } else {
          final playability = data['playabilityStatus'];
          final reason = playability?['reason'] ?? playability?['status'] ?? "Unknown error";
          printINFO('InnerTube $clientName returned no streamingData. Playability: $reason');
          return StreamProvider(playable: false, statusMSG: reason.toString());
        }
      } else {
        printINFO('InnerTube $clientName HTTP Error: ${response.statusCode}');
        return StreamProvider(playable: false, statusMSG: "HTTP ${response.statusCode}");
      }
    } catch (e) {
      printINFO('InnerTube $clientName Exception: $e');
      return StreamProvider(playable: false, statusMSG: "Connection error");
    } finally {
      httpClient.close(force: true);
    }
    return null;
  }

  Audio? get highestQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 140,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateMp4aAudio =>
      audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateOpusAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250,
          orElse: () => audioFormats!.first);

  Audio? get lowQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 249 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson(),
      if (streamHeaders != null) "streamHeaders": streamHeaders,
    };
  }
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
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size
      };

  factory Audio.fromJson(json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a")
          ? Codec.mp4a
          : Codec.opus,
      itag: json['itag'],
      duration: json["approxDurationMs"] ?? 0,
      bitrate: json["bitrate"] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json["size"] ?? 0);
}

enum Codec { mp4a, opus }
