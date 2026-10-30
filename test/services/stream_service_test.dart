import 'package:flutter_test/flutter_test.dart';
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
