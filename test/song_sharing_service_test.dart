import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/song_sharing_service.dart';

void main() {
  const service = SongSharingService();
  const videoId = 'dQw4w9WgXcQ';
  const canonicalLink =
      'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ';

  MediaItem songWithId(String id) => MediaItem(
        id: id,
        title: 'Test Song',
        artist: 'Test Artist',
      );

  group('SongSharingService', () {
    test('generates the canonical MuziiNap song URL', () {
      expect(
        service.generateSongLink(songWithId(videoId)),
        canonicalLink,
      );
    });

    test('generates the same canonical URL for QR content', () {
      final song = songWithId(videoId);

      expect(service.generateSongQr(song), service.generateSongLink(song));
      expect(service.generateSongQr(song), canonicalLink);
    });

    test('preserves valid YouTube video ID characters in the URL path', () {
      const validId = 'aZ09_-xYz12';
      final link = service.generateSongLink(songWithId(validId));

      expect(Uri.parse(link!).pathSegments, ['song', validId]);
      expect(link, 'https://muziinap-site.vercel.app/song/$validId');
    });

    test('rejects an empty video ID', () {
      expect(service.generateSongLink(songWithId('')), isNull);
    });

    test('rejects whitespace and malformed video IDs', () {
      for (final id in [
        ' dQw4w9WgXcQ',
        'dQw4w9WgXcQ ',
        'dQw4w9WgXc',
        'dQw4w9WgXcQQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'dQw4w9WgX%2F',
        'abcdefghijk!',
      ]) {
        expect(
          service.generateSongLink(songWithId(id)),
          isNull,
          reason: 'Expected malformed video ID "$id" to be rejected.',
        );
      }
    });

    test('supports MediaItem songs with optional metadata omitted', () {
      final song = MediaItem(id: videoId, title: 'Minimal Song');

      expect(service.generateSongLink(song), canonicalLink);
    });
  });
}
