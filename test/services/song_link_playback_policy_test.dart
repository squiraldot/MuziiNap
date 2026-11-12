import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/song_link_playback_policy.dart';

void main() {
  group('SharedSongQueuePolicy', () {
    test('places a new shared song first and preserves existing order', () {
      expect(SharedSongQueuePolicy.prioritize<String>(
        ['a', 'b', 'c'], 'shared', (item) => item,
      ), ['shared', 'a', 'b', 'c']);
    });

    test('reuses an existing queue entry and removes duplicate IDs', () {
      final original = ['a', 'shared', 'b', 'shared', 'c'];
      final result = SharedSongQueuePolicy.prioritize<String>(
        original, 'shared', (item) => item,
      );
      expect(result, ['shared', 'a', 'b', 'c']);
      expect(identical(result.first, original[1]), isTrue);
    });

    test('preserves an empty queue except for the shared target', () {
      expect(SharedSongQueuePolicy.prioritize<String>(
        [], 'shared', (item) => item,
      ), ['shared']);
    });
  });
}
