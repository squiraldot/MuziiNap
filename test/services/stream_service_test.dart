import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/device_adaptive_stream_selector.dart';
import 'package:muziinap/services/stream_service.dart';
import 'package:muziinap/services/youtube/po_token/po_token_policy.dart';

void main() {
  group('InnerTube audio format validation', () {
    test('does not return cipher-only audio formats as playable URLs', () {
      final formats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'signatureCipher': 's=encrypted-signature&url=https%3A%2F%2Fexample.com',
        },
      ]);

      expect(formats, isEmpty);
    });

    test('rejects InnerTube URLs with an undeciphered n parameter', () {
      final formats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'url': 'https://media.example.com/audio?n=undecipheredToken',
          'bitrate': 128000,
        },
      ]);

      expect(formats, isEmpty);
    });

    test('accepts an n URL only after the deciphering pipeline marks it resolved', () {
      final formats = StreamProvider.parseInnerTubeAudioFormats(
        [
          {
            'itag': 140,
            'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
            'url': 'https://media.example.com/audio?n=decipheredToken',
            'bitrate': 128000,
          },
        ],
        allowDecipheredN: true,
      );

      expect(formats, hasLength(1));
      expect(
        Uri.parse(formats.single.url).queryParameters['n'],
        'decipheredToken',
      );
    });

    test('accepts a direct HTTPS audio URL', () {
      final formats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'url': 'https://media.example.com/audio',
          'bitrate': 128000,
        },
      ]);

      expect(formats, hasLength(1));
      expect(formats.single.url, 'https://media.example.com/audio');
    });

    test('rejects direct audio URLs containing sabr=1', () {
      final formats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'url': 'https://media.example.com/audio?expire=123&sabr=1',
          'bitrate': 128000,
        },
      ]);

      expect(formats, isEmpty);
      expect(
        StreamProvider.isValidAudioFormatUrl(
          'https://media.example.com/audio?sabr=1',
        ),
        isFalse,
      );
    });

    test('allows ordinary unrelated query parameters on direct audio URLs', () {
      const url = 'https://media.example.com/audio?expire=123&source=music';
      final formats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'url': url,
          'bitrate': 128000,
        },
      ]);

      expect(formats, hasLength(1));
      expect(formats.single.url, url);
    });

    test('allows a non-enabled sabr query value on direct audio URLs', () {
      const url = 'https://media.example.com/audio?sabr=0';
      expect(StreamProvider.isValidAudioFormatUrl(url), isTrue);
    });

    test('rejects a SABR-only response and continues with the next client', () async {
      final sabrOnlyResponse = {
        'streamingData': {
          'adaptiveFormats': [
            {
              'itag': 140,
              'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
              'bitrate': 128000,
            },
          ],
          'serverAbrStreamingUrl':
              'https://rr.googlevideo.com/videoplayback?sabr=1',
        },
      };
      final streamingData = sabrOnlyResponse['streamingData']!;
      final adaptiveFormats = streamingData['adaptiveFormats'] as List;

      final firstClientAttempt = () async {
        final formats = StreamProvider.parseInnerTubeAudioFormats(
          adaptiveFormats,
        );
        if (formats.isEmpty) {
          return StreamProvider(
            playable: false,
            statusMSG: 'No validated direct audio formats',
          );
        }
        return StreamProvider(playable: true, audioFormats: formats);
      }();

      final nextClientFormats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'url': 'https://media.example.com/fallback?expire=456',
          'bitrate': 128000,
        },
      ]);
      final nextClientAttempt = Future<StreamProvider>.value(
        StreamProvider(playable: true, audioFormats: nextClientFormats),
      );

      expect(
        StreamProvider.isValidAudioFormatUrl(
          streamingData['serverAbrStreamingUrl'] as String,
        ),
        isFalse,
      );
      expect(
        StreamProvider.parseInnerTubeAudioFormats(adaptiveFormats),
        isEmpty,
      );

      final rejectedAttempt = await firstClientAttempt;
      expect(rejectedAttempt.playable, isFalse);
      expect(
        rejectedAttempt.statusMSG,
        'No validated direct audio formats',
      );

      final result = await StreamProvider.firstPlayableResult([
        firstClientAttempt,
        nextClientAttempt,
      ]);

      expect(result.playable, isTrue);
      expect(result.audioFormats, hasLength(1));
      expect(
        result.audioFormats!.single.url,
        'https://media.example.com/fallback?expire=456',
      );
    });
  });

  group('GVS PO Token URL attachment', () {
    test('attaches pot to eligible direct Google Video Server URLs only', () {
      const policy = PoTokenPolicy();
      const directUrl =
          'https://rr.googlevideo.com/videoplayback?expire=123';
      const sabrUrl =
          'https://rr.googlevideo.com/videoplayback?expire=123&sabr=1';

      final formats = policy.attachGvsTokenToFormats([
        {'url': directUrl},
        {'url': sabrUrl},
      ], 'gvs-token');

      expect(
        Uri.parse(formats[0]['url'] as String).queryParameters['pot'],
        'gvs-token',
      );
      expect(formats[1]['url'], sabrUrl);
    });
  });

  group('Adaptive Android buffer configuration', () {
    test('uses fast-start 30 second buffer on capable Wi-Fi devices', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.wifi,
      );
      final config = profile.androidLoadControl;
      expect(config.minBufferDuration, const Duration(milliseconds: 1500));
      expect(config.maxBufferDuration, const Duration(seconds: 30));
      expect(config.bufferForPlaybackDuration, const Duration(seconds: 1));
      expect(
        config.bufferForPlaybackAfterRebufferDuration,
        const Duration(seconds: 2),
      );
    });

    test('caps buffer on low-RAM devices', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: true,
        networkType: DeviceNetworkType.wifi,
      );
      final config = profile.androidLoadControl;
      expect(config.minBufferDuration, const Duration(milliseconds: 2500));
      expect(config.maxBufferDuration, const Duration(seconds: 12));
      expect(config.bufferForPlaybackDuration, const Duration(seconds: 1));
      expect(
        config.bufferForPlaybackAfterRebufferDuration,
        const Duration(seconds: 2),
      );
    });

    test('uses a moderate buffer on mobile data', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.mobile,
      );
      final config = profile.androidLoadControl;
      expect(config.minBufferDuration, const Duration(seconds: 2));
      expect(config.maxBufferDuration, const Duration(seconds: 18));
    });
  });

  group('Device adaptive stream policy', () {
    test('updates network type without losing detected hardware capabilities', () {
      const wifiProfile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.wifi,
      );

      final mobileProfile =
          wifiProfile.withNetworkType(DeviceNetworkType.mobile);

      expect(mobileProfile.androidApiLevel, 35);
      expect(mobileProfile.isLowRamDevice, isFalse);
      expect(mobileProfile.networkType, DeviceNetworkType.mobile);
      expect(mobileProfile.preferredItag, 140);
    });

    test('prefers Opus 251 on API 29+ Wi-Fi devices with adequate RAM', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.wifi,
      );
      expect(profile.preferredItag, 251);
      expect(profile.isLegacyAndroid, isFalse);
    });

    test('prefers AAC 140 on low-RAM devices even on Wi-Fi', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: true,
        networkType: DeviceNetworkType.wifi,
      );
      expect(profile.preferredItag, 140);
    });

    test('prefers AAC 140 on cellular networks', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 35,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.mobile,
      );
      expect(profile.preferredItag, 140);
    });

    test('forces AAC on Android versions below API 29', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 28,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.wifi,
      );
      expect(profile.preferredItag, 140);
      expect(profile.isLegacyAndroid, isTrue);
      expect(profile.allowsOpus, isFalse);
    });

    test('treats an unavailable API level conservatively', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: null,
        isLowRamDevice: true,
        networkType: DeviceNetworkType.wifi,
      );
      expect(profile.preferredItag, 140);
      expect(profile.allowsOpus, isFalse);
      expect(profile.requiresWebClient, isTrue);
    });

    test('classifies native decoder failures for AAC retry', () {
      expect(
        DeviceAdaptiveStreamSelector.isDecoderCompatibilityFailure(
          Exception('MediaCodecRenderer: DecoderInitializationException'),
        ),
        isTrue,
      );
      expect(
        DeviceAdaptiveStreamSelector.isDecoderCompatibilityFailure(
          Exception('HTTP 403 while fetching media'),
        ),
        isFalse,
      );
    });

    test('serializes profile for safe transfer into resolver isolate', () {
      const profile = DeviceStreamProfile(
        androidApiLevel: 33,
        isLowRamDevice: false,
        networkType: DeviceNetworkType.wifi,
      );
      expect(DeviceStreamProfile.fromJson(profile.toJson()), profile);
    });
  });

  group('InnerTube adaptive format filtering', () {
    final formats = [
      {
        'itag': 251,
        'mimeType': 'audio/webm; codecs="opus"',
        'url': 'https://media.example.com/opus',
        'bitrate': 160000,
      },
      {
        'itag': 140,
        'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
        'url': 'https://media.example.com/aac',
        'bitrate': 128000,
      },
      {
        'itag': 999,
        'mimeType': 'video/webm; codecs="vp9,opus"',
        'url': 'https://media.example.com/video',
        'bitrate': 200000,
      },
      {
        'itag': 998,
        'mimeType': 'audio/webm; codecs="opus"',
        'url': 'https://media.example.com/spatial',
        'bitrate': 160000,
        'spatialAudioType': 'SPATIAL_AUDIO',
      },
    ];

    test('selects Opus 251 for a high-end Wi-Fi device', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        formats,
        profile: const DeviceStreamProfile(
          androidApiLevel: 35,
          isLowRamDevice: false,
          networkType: DeviceNetworkType.wifi,
        ),
      );
      expect(selected.map((format) => format.itag), [140, 251]);
      expect(selected.last.itag, 251);
      expect(selected.first.itag, 140);
      final provider = StreamProvider(playable: true, audioFormats: selected);
      expect(provider.lowQualityAudio?.itag, 140);
      expect(provider.highestQualityAudio?.itag, 251);
    });

    test('selects AAC 140 for a low-RAM or cellular device', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        formats,
        profile: const DeviceStreamProfile(
          androidApiLevel: 35,
          isLowRamDevice: true,
          networkType: DeviceNetworkType.wifi,
        ),
      );
      expect(selected.map((format) => format.itag), [140]);
    });

    test('cellular data selects AAC even when Opus is also available', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        formats,
        profile: const DeviceStreamProfile(
          androidApiLevel: 34,
          isLowRamDevice: false,
          networkType: DeviceNetworkType.mobile,
        ),
      );
      expect(selected.map((format) => format.itag), [140]);
    });

    test('legacy Android excludes Opus and keeps standard AAC', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        formats,
        profile: const DeviceStreamProfile(
          androidApiLevel: 28,
          isLowRamDevice: false,
          networkType: DeviceNetworkType.wifi,
        ),
      );
      expect(selected.map((format) => format.itag), [140]);
    });

    test('falls back to the preferred codec when the preferred itag is absent', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        [
          {
            'itag': 250,
            'mimeType': 'audio/webm; codecs="opus"',
            'url': 'https://media.example.com/opus-low',
            'bitrate': 70000,
          },
          {
            'itag': 141,
            'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
            'url': 'https://media.example.com/aac-high',
            'bitrate': 256000,
          },
        ],
        profile: const DeviceStreamProfile(
          androidApiLevel: 35,
          isLowRamDevice: false,
          networkType: DeviceNetworkType.wifi,
        ),
      );
      expect(selected.map((format) => format.itag), [141, 250]);
    });

    test('legacy devices fail closed when no AAC format exists', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        [
          {
            'itag': 251,
            'mimeType': 'audio/webm; codecs="opus"',
            'url': 'https://media.example.com/opus',
            'bitrate': 160000,
          },
        ],
        profile: const DeviceStreamProfile(
          androidApiLevel: 28,
          isLowRamDevice: false,
          networkType: DeviceNetworkType.wifi,
        ),
      );
      expect(selected, isEmpty);
    });

    test('drops spatial and video-wrapped tracks', () {
      final selected = StreamProvider.parseInnerTubeAudioFormats(
        formats,
        profile: const DeviceStreamProfile(
          androidApiLevel: 35,
          isLowRamDevice: false,
          networkType: DeviceNetworkType.wifi,
        ),
      );
      expect(selected.map((format) => format.itag), isNot(contains(998)));
      expect(selected.map((format) => format.itag), isNot(contains(999)));
    });
  });

  group('InnerTube request and media transport policy', () {
    test('uses a bounded 1.5 second first-choice VISIONOS handshake', () {
      expect(
        StreamProvider.requestTimeoutForClient('VISIONOS'),
        const Duration(milliseconds: 1500),
      );
    });

    test('uses the normal timeout for other clients in the race', () {
      expect(
        StreamProvider.requestTimeoutForClient('ANDROID'),
        const Duration(seconds: 5),
      );
    });

    test('does not apply the fast deadline when VISIONOS is later in the race', () {
      expect(
        StreamProvider.requestTimeoutForClient(
          'VISIONOS',
          isInitialAttempt: false,
        ),
        const Duration(seconds: 5),
      );
    });

    test('does not shorten the WEB_REMIX fallback timeout', () {
      expect(
        StreamProvider.requestTimeoutForClient('WEB_REMIX'),
        const Duration(seconds: 5),
      );
    });

    test('preserves server-issued stream query parameters verbatim', () {
      const signedUrl =
          'https://media.example.com/audio?expire=123&sig=abc%2Fdef&cpn=serverNonce';
      expect(StreamProvider.prepareStreamUrl(signedUrl), signedUrl);
    });

    test('rejects insecure or malformed media URLs', () {
      expect(
        () => StreamProvider.prepareStreamUrl('http://media.example.com/audio'),
        throwsFormatException,
      );
      expect(
        () => StreamProvider.prepareStreamUrl('not a URL'),
        throwsFormatException,
      );
    });

    test('builds native media headers without forwarding account cookies', () {
      expect(
        StreamProvider.buildMediaRequestHeaders('MuziiNap/1.0'),
        {
          'User-Agent': 'MuziiNap/1.0',
          'Accept': '*/*',
        },
      );
    });
  });

  group('InnerTube primary race', () {
    test('returns the first playable response without waiting for slower clients', () async {
      final slow = Completer<StreamProvider>();
      final fast = Completer<StreamProvider>();
      final winner = StreamProvider(
        playable: true,
        statusMSG: 'OK',
        audioFormats: [
          Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 128000,
            duration: 0,
            loudnessDb: 0,
            url: 'https://media.example.com/fast',
            size: 0,
          ),
        ],
      );

      final result = StreamProvider.firstPlayableResult([
        slow.future,
        fast.future,
      ]);
      fast.complete(winner);

      expect(await result, same(winner));
      expect(slow.isCompleted, isFalse);
    });

    test('invokes the winner callback once when a client succeeds', () async {
      final first = Completer<StreamProvider>();
      final second = Completer<StreamProvider>();
      var cancelledLosers = 0;
      final result = StreamProvider.firstPlayableResult(
        [first.future, second.future],
        onWinner: () => cancelledLosers++,
      );

      first.complete(StreamProvider(
        playable: true,
        statusMSG: 'OK',
      ));
      second.complete(StreamProvider(
        playable: true,
        statusMSG: 'late result',
      ));

      expect((await result).playable, isTrue);
      expect(cancelledLosers, 1);
    });

    test('waits for every primary client to fail before returning failure', () async {
      final first = Completer<StreamProvider>();
      final second = Completer<StreamProvider>();
      final result = StreamProvider.firstPlayableResult([
        first.future,
        second.future,
      ]);

      first.complete(StreamProvider(
        playable: false,
        statusMSG: 'WEB_REMIX unavailable',
      ));
      second.complete(StreamProvider(
        playable: false,
        statusMSG: 'ANDROID unavailable',
      ));

      final failure = await result;
      expect(failure.playable, isFalse);
      expect(
        failure.statusMSG,
        'WEB_REMIX unavailable; ANDROID unavailable',
      );
    });
  });

  group('Stream URL cache validation', () {
    final now = DateTime.utc(2026, 10, 30, 12);
    Map<String, dynamic> cacheEntry({
      required String lowUrl,
      required String highUrl,
      int? resolvedAt,
      bool includeHeaders = false,
    }) => {
      'playable': true,
      'statusMSG': 'OK',
      'streamResolverVersion': StreamProvider.streamResolverVersion,
      'lowQualityAudio': {'audioCodec': 'Codec.mp4a', 'url': lowUrl},
      'highQualityAudio': {'audioCodec': 'Codec.mp4a', 'url': highUrl},
      if (resolvedAt != null) 'resolvedAt': resolvedAt,
      if (includeHeaders) 'streamHeaders': <String, String>{},
    };

    test('invalidates cached URLs created by the previous resolver version', () {
      final entry = cacheEntry(
        lowUrl: 'https://piped.example/audio-low',
        highUrl: 'https://piped.example/audio-high',
        resolvedAt: now.millisecondsSinceEpoch,
      )..['streamResolverVersion'] = StreamProvider.streamResolverVersion - 1;

      expect(StreamProvider.isCachedStreamUsable(entry, now: now), isFalse);
    });

    test('accepts cached Piped-style URLs without stream headers', () {
      final entry = cacheEntry(
        lowUrl: 'https://piped.example/audio-low',
        highUrl: 'https://piped.example/audio-high',
        resolvedAt: now.millisecondsSinceEpoch,
      );

      expect(
        StreamProvider.isCachedStreamUsable(entry, now: now),
        isTrue,
      );
    });

    test('rejects a cache when the selected quality URL is expired', () {
      final entry = cacheEntry(
        lowUrl: 'https://media.example/audio?expire=1700000000',
        highUrl: 'https://media.example/audio?expire=1700000000',
        resolvedAt: now.millisecondsSinceEpoch,
      );

      expect(
        StreamProvider.isCachedStreamUsable(entry, now: now),
        isFalse,
      );
    });

    test('keeps a fresh high-quality URL when only low quality has expired', () {
      final futureExpiry =
          now.millisecondsSinceEpoch ~/ 1000 + const Duration(hours: 2).inSeconds;
      final entry = cacheEntry(
        lowUrl: 'https://media.example/audio-low?expire=1700000000',
        highUrl: 'https://media.example/audio-high?expire=$futureExpiry',
        resolvedAt: now.millisecondsSinceEpoch,
      );

      expect(
        StreamProvider.isCachedStreamUsable(
          entry,
          qualityIndex: 1,
          now: now,
        ),
        isTrue,
      );
      expect(
        StreamProvider.isCachedStreamUsable(
          entry,
          qualityIndex: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('uses a bounded cache age for URLs without explicit expiry', () {
      final fresh = cacheEntry(
        lowUrl: 'https://piped.example/audio-low',
        highUrl: 'https://piped.example/audio-high',
        resolvedAt: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
      final stale = cacheEntry(
        lowUrl: 'https://piped.example/audio-low',
        highUrl: 'https://piped.example/audio-high',
        resolvedAt: now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
      );

      expect(StreamProvider.isCachedStreamUsable(fresh, now: now), isTrue);
      expect(StreamProvider.isCachedStreamUsable(stale, now: now), isFalse);
    });

    test('rejects malformed cache records and missing quality URLs', () {
      expect(StreamProvider.isCachedStreamUsable(null, now: now), isFalse);
      expect(
        StreamProvider.isCachedStreamUsable(
          cacheEntry(
            lowUrl: 'https://piped.example/audio-low',
            highUrl: '',
            resolvedAt: now.millisecondsSinceEpoch,
          ),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('InnerTube primary race client preference', () {
    test('starts the primary client immediately and staggers fallbacks', () {
      expect(StreamProvider.clientStartDelayFor(0), Duration.zero);
      expect(
        StreamProvider.clientStartDelayFor(1),
        const Duration(milliseconds: 200),
      );
      expect(
        StreamProvider.clientStartDelayFor(4),
        const Duration(milliseconds: 800),
      );
    });

    test('prioritizes VISIONOS before the token-gated web clients', () {
      expect(
        StreamProvider.clientNamesFor().take(3).toList(),
        ['VISIONOS', 'WEB_REMIX', 'WEB_EMBEDDED'],
      );
    });

    test('keeps VISIONOS primary and promotes ANDROID for recovery', () {
      expect(
        StreamProvider.clientNamesFor(preferredClient: 'ANDROID').take(3).toList(),
        ['VISIONOS', 'ANDROID', 'WEB_REMIX'],
      );
    });

    test('includes every supported client in the primary race', () {
      expect(
        StreamProvider.clientNamesFor(preferredClient: 'ANDROID'),
        ['VISIONOS', 'ANDROID', 'WEB_REMIX', 'WEB_EMBEDDED', 'ANDROID_VR',
          'TVHTML5_SIMPLY_EMBEDDED_PLAYER'],
      );
    });
  });
}
