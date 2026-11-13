import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/deep_link_service.dart';
import 'package:muziinap/utils/song_sharing_config.dart';

class _FakeAppLinkSource implements AppLinkSource {
  _FakeAppLinkSource({this.initialLink});

  final String? initialLink;
  late final StreamController<String> controller =
      StreamController<String>.broadcast(onListen: () {
    if (initialLink != null) controller.add(initialLink!);
  });

  @override
  Stream<String> get linkStream => controller.stream;

  Future<void> close() => controller.close();
}

const _canonical = 'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ';

Future<void> _flushEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  group('SongSharingConfig.parseVideoId', () {
    test('accepts canonical HTTPS URLs and one trailing slash', () {
      expect(SongSharingConfig.parseVideoId(_canonical), 'dQw4w9WgXcQ');
      expect(SongSharingConfig.parseVideoId('$_canonical/'), 'dQw4w9WgXcQ');
    });

    test('rejects encoded path identifiers before Uri normalization', () {
      for (final url in [
        'https://muziinap-site.vercel.app/song/dQw4w9WgXc%51',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXc%2F',
      ]) {
        expect(SongSharingConfig.parseVideoId(url), isNull);
      }
    });

    test('rejects invalid IDs and malformed URL forms', () {
      final urls = [
        'https://muziinap-site.vercel.app/song/',
        'https://muziinap-site.vercel.app/song/short',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ!!',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXc',
        'https://evil.example/song/dQw4w9WgXcQ',
        'http://muziinap-site.vercel.app/song/dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app:8443/song/dQw4w9WgXcQ',
        'https://user@muziinap-site.vercel.app/song/dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ?source=test',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ#section',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ/extra',
        'https://muziinap-site.vercel.app/song//dQw4w9WgXcQ',
        'https://muziinap-site.vercel.app/song/dQw4w9WgXcQ//',
        'https://[malformed/song/dQw4w9WgXcQ',
      ];

      for (final url in urls) {
        expect(SongSharingConfig.parseVideoId(url), isNull, reason: url);
      }
    });

    test('preserves case and accepts the default HTTPS port', () {
      expect(
        SongSharingConfig.parseVideoId(
          'https://MUZIINAP-SITE.VERCEL.APP:443/song/aZ09_-xYz12',
        ),
        'aZ09_-xYz12',
      );
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

    test('delivers the cold-start canonical link exactly once', () async {
      final initialSource = _FakeAppLinkSource(initialLink: _canonical);
      final initialService = DeepLinkService(source: initialSource);
      final requests = <SongLinkRequest>[];
      final delivered = Completer<void>();
      final subscription = initialService.songRequests.listen((request) {
        requests.add(request);
        if (!delivered.isCompleted) delivered.complete();
      });

      await initialService.start();
      await delivered.future.timeout(const Duration(seconds: 1));

      expect(requests, hasLength(1));
      expect(requests.single.videoId, 'dQw4w9WgXcQ');
      expect(requests.single.uri.toString(), _canonical);

      await subscription.cancel();
      await initialService.dispose();
      await initialSource.close();
    });

    test('normalizes valid song requests to the canonical URL', () async {
      final requests = <SongLinkRequest>[];
      final delivered = Completer<void>();
      final subscription = service.songRequests.listen((request) {
        requests.add(request);
        if (!delivered.isCompleted) delivered.complete();
      });

      await service.start();
      source.controller.add('$_canonical/');
      await delivered.future.timeout(const Duration(seconds: 1));

      expect(requests.single.uri.toString(), _canonical);
      await subscription.cancel();
    });

    test('subscribes to warm-start runtime links', () async {
      final requests = <SongLinkRequest>[];
      final delivered = Completer<void>();
      final subscription = service.songRequests.listen((request) {
        requests.add(request);
        if (!delivered.isCompleted) delivered.complete();
      });

      await service.start();
      source.controller.add(
        'https://muziinap-site.vercel.app/song/aqz-KE-bpKQ',
      );
      await delivered.future.timeout(const Duration(seconds: 1));

      expect(requests.single.videoId, 'aqz-KE-bpKQ');
      await subscription.cancel();
    });

    test('delivers multiple distinct incoming song links in order', () async {
      final requests = <SongLinkRequest>[];
      final delivered = Completer<void>();
      final subscription = service.songRequests.listen((request) {
        requests.add(request);
        if (requests.length == 2 && !delivered.isCompleted) delivered.complete();
      });

      await service.start();
      source.controller.add(_canonical);
      source.controller.add(
        'https://muziinap-site.vercel.app/song/aqz-KE-bpKQ',
      );
      await delivered.future.timeout(const Duration(seconds: 1));

      expect(
        requests.map((request) => request.videoId).toList(),
        ['dQw4w9WgXcQ', 'aqz-KE-bpKQ'],
      );
      await subscription.cancel();
    });

    test('deduplicates an initial link repeated by the runtime stream', () async {
      final initialSource = _FakeAppLinkSource(initialLink: _canonical);
      final initialService = DeepLinkService(
        source: initialSource,
        duplicateWindow: const Duration(seconds: 2),
      );
      final requests = <SongLinkRequest>[];
      final subscription = initialService.songRequests.listen(requests.add);

      await initialService.start();
      await _flushEvents();
      initialSource.controller.add(_canonical);
      await _flushEvents();

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

      await timedService.start();
      timedSource.controller.add(_canonical);
      await _flushEvents();
      now = now.add(const Duration(seconds: 3));
      timedSource.controller.add(_canonical);
      await _flushEvents();

      expect(requests, hasLength(2));
      await subscription.cancel();
      await timedService.dispose();
      await timedSource.close();
    });

    test('forwards existing YouTube imports unchanged to legacy handling',
        () async {
      final legacyLinks = <Uri>[];
      final delivered = Completer<void>();
      final subscription = service.legacyLinks.listen((uri) {
        legacyLinks.add(uri);
        if (!delivered.isCompleted) delivered.complete();
      });

      await service.start();
      const youtubeUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      source.controller.add(youtubeUrl);
      await delivered.future.timeout(const Duration(seconds: 1));

      expect(legacyLinks.single.toString(), youtubeUrl);
      await subscription.cancel();
    });

    test('rejects encoded canonical paths rather than importing normalized IDs',
        () async {
      final requests = <SongLinkRequest>[];
      final legacyLinks = <Uri>[];
      final requestSubscription = service.songRequests.listen(requests.add);
      final legacySubscription = service.legacyLinks.listen(legacyLinks.add);

      await service.start();
      source.controller.add(
        'https://muziinap-site.vercel.app/song/dQw4w9WgXc%51',
      );
      await _flushEvents();

      expect(requests, isEmpty);
      expect(legacyLinks, isEmpty);
      await requestSubscription.cancel();
      await legacySubscription.cancel();
    });

    test('does not deliver runtime links after disposal', () async {
      final requests = <SongLinkRequest>[];
      final subscription = service.songRequests.listen(requests.add);
      await service.start();
      await service.dispose();
      source.controller.add(_canonical);
      await _flushEvents();

      expect(requests, isEmpty);
      await subscription.cancel();
    });

    test('start is idempotent', () async {
      await Future.wait([service.start(), service.start()]);
      expect(service.isStarted, isTrue);
    });
  });
}
