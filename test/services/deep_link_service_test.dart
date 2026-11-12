import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/deep_link_service.dart';
import 'package:muziinap/utils/song_sharing_config.dart';

class _FakeAppLinkSource implements AppLinkSource {
  _FakeAppLinkSource({this.initialLink});

  final Uri? initialLink;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> getInitialLink() async => initialLink;

  @override
  Stream<Uri> get uriLinkStream => controller.stream;

  Future<void> close() => controller.close();
}

void main() {
  group('SongSharingConfig.parseVideoId', () {
    test('accepts a canonical HTTPS song URL', () {
      expect(
        SongSharingConfig.parseVideoId(
          Uri.parse('https://muziinap-site.vercel.app/song/dQw4w9WgXcQ'),
        ),
        'dQw4w9WgXcQ',
      );
    });

    test('accepts the canonical URL with one trailing slash', () {
      expect(
        SongSharingConfig.parseVideoId(
          Uri.parse('https://muziinap-site.vercel.app/song/dQw4w9WgXcQ/'),
        ),
        'dQw4w9WgXcQ',
      );
    });

    test('rejects invalid video ID lengths and alphabets', () {
      for (final id in ['', 'short', 'dQw4w9WgXcQ!!', 'dQw4w9WgXc']) {
        expect(
          SongSharingConfig.parseVideoId(
            Uri.parse('https://muziinap-site.vercel.app/song/$id'),
          ),
          isNull,
        );
      }
    });

    test('rejects unsupported hosts, schemes, paths, query and fragment', () {
      final urls = [
        'https://evil.example/song/dQw4w9WgXcQ',
        'http://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app/other/dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ?source=test',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ#section',
      ];

      for (final url in urls) {
        expect(SongSharingConfig.parseVideoId(Uri.parse(url)), isNull);
      }
    });

    test('rejects encoded path identifiers and non-default ports', () {
      expect(
        SongSharingConfig.parseVideoId(
          Uri.parse('https://muziinap-site.vercel.app/song/dQw4w9WgXc%51'),
        ),
        isNull,
      );
      expect(
        SongSharingConfig.parseVideoId(
          Uri.parse('https://muziinap-site.vercel.app:8443/song/dQw4w9WgXcQ'),
        ),
        isNull,
      );
    });

    test('malformed URL text cannot be parsed into a request URI', () {
      expect(Uri.tryParse('https://[malformed'), isNull);
    });
  });

  group('DeepLinkService', () {
    late _FakeAppLinkSource source;
    late DeepLinkService service;

    setUp(() {
      source = _FakeAppLinkSource();
      service = DeepLinkService(
        source: source,
        duplicateWindow: const Duration(seconds: 2),
      );
    });

    tearDown(() async {
      await service.dispose();
      await source.close();
    });

    test('delivers the initial canonical song link', () async {
      final initial = Uri.parse(
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
      );
      final initialSource = _FakeAppLinkSource(initialLink: initial);
      final initialService = DeepLinkService(source: initialSource);
      final requests = <SongLinkRequest>[];
      final subscription = initialService.songRequests.listen(requests.add);

      await initialService.start();

      expect(requests, hasLength(1));
      expect(requests.single.videoId, 'dQw4w9WgXcQ');
      expect(requests.single.uri, initial);

      await subscription.cancel();
      await initialService.dispose();
      await initialSource.close();
    });

    test('normalizes valid song requests to the canonical URL', () async {
      final requests = <SongLinkRequest>[];
      final subscription = service.songRequests.listen(requests.add);

      await service.start();
      source.controller.add(
        Uri.parse('https://muziinap-site.vercel.app/song/dQw4w9WgXcQ/'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(requests.single.uri.toString(),
          'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ');

      await subscription.cancel();
    });

    test('subscribes to runtime links and emits valid song requests', () async {
      final requests = <SongLinkRequest>[];
      final subscription = service.songRequests.listen(requests.add);

      await service.start();
      source.controller.add(
        Uri.parse('https://muziinap-site.vercel.app/song/aqz-KE-bpKQ'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(1));
      expect(requests.single.videoId, 'aqz-KE-bpKQ');

      await subscription.cancel();
    });

    test('delivers multiple distinct incoming song links in order', () async {
      final requests = <SongLinkRequest>[];
      final subscription = service.songRequests.listen(requests.add);

      await service.start();
      source.controller.add(
        Uri.parse('https://muziinap-site.vercel.app/song/dQw4w9WgXcQ'),
      );
      source.controller.add(
        Uri.parse('https://muziinap-site.vercel.app/song/aqz-KE-bpKQ'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        requests.map((request) => request.videoId).toList(),
        ['dQw4w9WgXcQ', 'aqz-KE-bpKQ'],
      );

      await subscription.cancel();
    });

    test('does not emit unsupported or malformed canonical requests', () async {
      final requests = <SongLinkRequest>[];
      final subscription = service.songRequests.listen(requests.add);

      await service.start();
      for (final url in [
        'https://evil.example/song/dQw4w9WgXcQ',
        'http://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app/song/not-valid',
      ]) {
        source.controller.add(Uri.parse(url));
      }
      await Future<void>.delayed(Duration.zero);

      expect(requests, isEmpty);
      await subscription.cancel();
    });

    test('deduplicates an initial link repeated by the runtime stream', () async {
      final initial = Uri.parse(
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
      );
      final initialSource = _FakeAppLinkSource(initialLink: initial);
      final initialService = DeepLinkService(
        source: initialSource,
        duplicateWindow: const Duration(seconds: 2),
      );
      final requests = <SongLinkRequest>[];
      final subscription = initialService.songRequests.listen(requests.add);

      await initialService.start();
      initialSource.controller.add(initial);
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(1));

      await subscription.cancel();
      await initialService.dispose();
      await initialSource.close();
    });

    test('allows a repeated song link after the duplicate window', () async {
      var now = DateTime.utc(2026, 1, 1);
      final timedSource = _FakeAppLinkSource();
      final timedService = DeepLinkService(
        source: timedSource,
        clock: () => now,
        duplicateWindow: const Duration(seconds: 2),
      );
      final requests = <SongLinkRequest>[];
      final subscription = timedService.songRequests.listen(requests.add);
      final uri = Uri.parse(
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
      );

      await timedService.start();
      timedSource.controller.add(uri);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 3));
      timedSource.controller.add(uri);
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(2));

      await subscription.cancel();
      await timedService.dispose();
      await timedSource.close();
    });

    test('forwards non-song links for existing YouTube import handling', () async {
      final legacyLinks = <Uri>[];
      final subscription = service.legacyLinks.listen(legacyLinks.add);

      await service.start();
      final youtube = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      source.controller.add(youtube);
      await Future<void>.delayed(Duration.zero);

      expect(legacyLinks, [youtube]);
      await subscription.cancel();
    });

    test('start is idempotent', () async {
      await Future.wait([service.start(), service.start()]);
      expect(service.isStarted, isTrue);
    });
  });
}
