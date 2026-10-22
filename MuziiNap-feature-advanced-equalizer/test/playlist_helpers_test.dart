import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/playlist_helpers.dart';

void main() {
  group('findStoredSongIndexById', () {
    test('returns the positional index for a matching song id', () {
      final storedSongs = [
        {'videoId': 'first'},
        {'videoId': 'target'},
        {'videoId': 'last'},
      ];

      expect(findStoredSongIndexById(storedSongs, 'target'), 1);
    });

    test('returns -1 when the selected song was already removed', () {
      final storedSongs = [
        {'videoId': 'first'},
        {'videoId': 'last'},
      ];

      expect(findStoredSongIndexById(storedSongs, 'missing'), -1);
    });

    test('ignores malformed stored entries instead of throwing', () {
      final storedSongs = [
        null,
        'unexpected',
        {'otherKey': 'value'},
        {'videoId': 'target'},
      ];

      expect(findStoredSongIndexById(storedSongs, 'target'), 3);
    });
  });
}
