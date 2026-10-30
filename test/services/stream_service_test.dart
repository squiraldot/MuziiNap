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
