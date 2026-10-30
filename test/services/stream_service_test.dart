import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/device_adaptive_stream_selector.dart';
import 'package:muziinap/services/stream_service.dart';

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
  });

  group('Device adaptive stream policy', () {
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
    test('uses a bounded 800 ms first-client handshake budget', () {
      expect(
        StreamProvider.requestTimeoutForClient('WEB_REMIX'),
        const Duration(milliseconds: 800),
      );
    });

    test('uses the normal timeout for fallback clients', () {
      expect(
        StreamProvider.requestTimeoutForClient('ANDROID'),
        const Duration(seconds: 5),
      );
    });

    test('does not apply the fast deadline when WEB_REMIX is a later fallback', () {
      expect(
        StreamProvider.requestTimeoutForClient(
          'WEB_REMIX',
          isInitialAttempt: false,
        ),
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

  group('StreamProvider client fallback order', () {
    test('starts with WEB_REMIX for the primary authenticated request', () {
      expect(
        StreamProvider.clientNamesFor(),
        startsWith(['WEB_REMIX', 'ANDROID']),
      );
    });

    test('moves ANDROID to the front after a playback source failure', () {
      expect(
        StreamProvider.clientNamesFor(preferredClient: 'ANDROID'),
        startsWith(['ANDROID', 'WEB_REMIX']),
      );
    });

    test('keeps remaining supported clients as deterministic fallbacks', () {
      expect(
        StreamProvider.clientNamesFor(preferredClient: 'ANDROID'),
        ['ANDROID', 'WEB_REMIX', 'ANDROID_VR',
          'TVHTML5_SIMPLY_EMBEDDED_PLAYER'],
      );
    });
  });
}
