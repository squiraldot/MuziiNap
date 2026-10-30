import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/house_keeping.dart';

void main() {
  group('shouldRemoveSongUrlCacheEntry', () {
    test('removes missing or malformed cache records', () {
      expect(shouldRemoveSongUrlCacheEntry(null), isTrue);
      expect(shouldRemoveSongUrlCacheEntry([]), isTrue);
      expect(shouldRemoveSongUrlCacheEntry(['metadata']), isTrue);
      expect(shouldRemoveSongUrlCacheEntry(['metadata', null]), isTrue);
      expect(shouldRemoveSongUrlCacheEntry(['metadata', 'not-a-stream-map']), isTrue);
      expect(shouldRemoveSongUrlCacheEntry(['metadata', {'other': 'value'}]), isTrue);
    });

    test('removes records with an empty URL', () {
      expect(
        shouldRemoveSongUrlCacheEntry(['metadata', {'url': ''}]),
        isTrue,
      );
    });

    test('keeps current map-shaped stream cache entries without mandatory headers', () {
      final now = DateTime.utc(2026, 10, 30, 12);
      final cacheEntry = {
        'playable': true,
        'resolvedAt': now.millisecondsSinceEpoch,
        'lowQualityAudio': {'url': 'https://piped.example/audio-low'},
        'highQualityAudio': {'url': 'https://piped.example/audio-high'},
      };

      expect(
        shouldRemoveSongUrlCacheEntry(cacheEntry, now: now),
        isFalse,
      );
    });

    test('removes stale map-shaped stream cache entries', () {
      final now = DateTime.utc(2026, 10, 30, 12);
      final cacheEntry = {
        'playable': true,
        'resolvedAt': now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
        'lowQualityAudio': {'url': 'https://piped.example/audio-low'},
        'highQualityAudio': {'url': 'https://piped.example/audio-high'},
      };

      expect(
        shouldRemoveSongUrlCacheEntry(cacheEntry, now: now),
        isTrue,
      );
    });

    test('keeps a record with a future stream URL expiry', () {
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7200;
      final cacheEntry = [
        'metadata',
        {'url': 'https://example.com/audio?expire=$expiry&token=test'},
      ];

      expect(shouldRemoveSongUrlCacheEntry(cacheEntry), isFalse);
    });
  });
}
