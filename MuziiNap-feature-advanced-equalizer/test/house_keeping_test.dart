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
