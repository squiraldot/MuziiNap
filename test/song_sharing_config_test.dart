import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/utils/song_sharing_config.dart';

void main() {
  group('SongSharingConfig', () {
    test('parses canonical URL', () {
      expect(SongSharingConfig.parseVideoId(Uri.parse(
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
      )), 'dQw4w9WgXcQ');
    });

    test('accepts one trailing slash and generates slashless canonical URL', () {
      expect(SongSharingConfig.parseVideoId(Uri.parse(
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ/',
      )), 'dQw4w9WgXcQ');
      expect(SongSharingConfig.canonicalUrl('dQw4w9WgXcQ'),
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ');
    });

    test('accepts all supported ID characters and preserves case', () {
      expect(SongSharingConfig.parseVideoId(Uri.parse(
        'https://muziinap-site.vercel.app/song/aZ09_-BcDeF',
      )), 'aZ09_-BcDeF');
    });

    test('rejects empty, short, long and malformed identifiers', () {
      for (final id in ['', 'short', 'dQw4w9WgX', 'dQw4w9WgXcQx',
        'dQw4w9WgX!Q', 'dQw4w9WgX Q', 'dQw4w9WgX%2F']) {
        expect(SongSharingConfig.parseVideoId(Uri.parse(
          'https://muziinap-site.vercel.app/song/$id',
        )), isNull, reason: 'Should reject $id');
      }
    });

    test('rejects unsupported schemes, hosts, ports and credentials', () {
      for (final url in [
        'http://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
        'ftp://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
        'https://example.com/song/dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app:8443/song/dQw4w9WgXcQ',
        'https://user@muziinap-site.vercel.app/song/dQw4w9WgXcQ',
      ]) {
        expect(SongSharingConfig.parseVideoId(Uri.parse(url)), isNull,
          reason: 'Should reject $url');
      }
    });

    test('rejects malformed and unknown paths', () {
      for (final path in ['/song', '/song/', '/Song/dQw4w9WgXcQ',
        '/song//dQw4w9WgXcQ', '/song/dQw4w9WgXcQ/extra',
        '/song/dQw4w9WgXcQ//', '/other/dQw4w9WgXcQ']) {
        expect(SongSharingConfig.parseVideoId(Uri.parse(
          'https://muziinap-site.vercel.app$path',
        )), isNull, reason: 'Should reject $path');
      }
    });

    test('rejects query parameters and fragments', () {
      for (final suffix in ['?utm_source=share', '?v=dQw4w9WgXcQ', '#fragment']) {
        expect(SongSharingConfig.parseVideoId(Uri.parse(
          'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ$suffix',
        )), isNull, reason: 'Should reject $suffix');
      }
    });

    test('canonical generation rejects invalid IDs', () {
      for (final id in ['', 'short', 'dQw4w9WgX!Q']) {
        expect(() => SongSharingConfig.canonicalUrl(id), throwsArgumentError);
      }
    });
  });
}
