import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/stream_service.dart';

void main() {
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
