import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/home_lyrics_widget_coordinator.dart';

void main() {
  group('HomeLyricsWidgetCoordinator', () {
    late StreamController<MediaItem?> mediaItems;
    late StreamController<Duration> positions;
    late StreamController<PlaybackState> playbackStates;
    late List<List<Object>> published;
    late List<String> requests;

    MediaItem song(String id, {Duration? duration}) => MediaItem(
          id: id,
          title: 'Track $id',
          artist: 'Artist',
          duration: duration,
        );

    HomeLyricsWidgetCoordinator createCoordinator({
      required Future<Map<String, dynamic>?> Function(
        MediaItem,
        int, {
        bool forceReload,
      }) loader,
    }) {
      final handler = _FakeAudioHandler(
        mediaItemStream: mediaItems.stream,
        playbackStateStream: playbackStates.stream,
      );
      return HomeLyricsWidgetCoordinator(
        audioHandler: handler,
        positionStream: positions.stream,
        lyricsLoader: loader,
        offsetLoader: (_) async => 0,
        retryDelay: const Duration(milliseconds: 10),\n        widgetPublisher: (previous, current, next, index) async {
          published.add([previous, current, next, index]);
        },
      );
    }

    setUp(() {
      mediaItems = StreamController<MediaItem?>.broadcast();
      positions = StreamController<Duration>.broadcast();
      playbackStates = StreamController<PlaybackState>.broadcast();
      published = [];
      requests = [];
    });

    tearDown(() async {
      await mediaItems.close();
      await positions.close();
      await playbackStates.close();
    });

    test('loads lyrics on track events without a PlayerController', () async {
      final coordinator = createCoordinator(loader: (track, duration,
          {required bool forceReload}) async {
        requests.add(track.id);
        return {'synced': '[00:01.00]hello', 'plainLyrics': 'hello'};
      });
      await coordinator.start();
      mediaItems.add(song('first', duration: const Duration(minutes: 3)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, ['first']);
      expect(published.any((line) => line[1] == 'hello'), isTrue);
      coordinator.onClose();
    });

    test('clears the old track and ignores a stale lookup response', () async {
      final first = Completer<Map<String, dynamic>?>();
      final coordinator = createCoordinator(loader: (track, duration,
          {forceReload = false}) {
        requests.add(track.id);
        if (track.id == 'old') return first.future;
        return Future.value({'synced': '[00:01.00]new line'});
      });
      await coordinator.start();
      mediaItems.add(song('old'));
      await Future<void>.delayed(Duration.zero);
      mediaItems.add(song('new'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      first.complete({'synced': '[00:01.00]old line'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(published.first, ['', '', '', -1]);
      expect(published.any((line) => line[1] == 'new line'), isTrue);
      expect(published.any((line) => line[1] == 'old line'), isFalse);
      coordinator.onClose();
    });

    test('retries when duration metadata arrives after the track', () async {
      final coordinator = createCoordinator(loader: (track, duration,
          {forceReload = false}) async {
        requests.add('${track.id}:$duration');
        return duration > 0
            ? {'synced': '[00:01.00]duration ready'}
            : null;
      });
      await coordinator.start();
      mediaItems.add(song('late-duration'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      mediaItems.add(song('late-duration',
          duration: const Duration(minutes: 2)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests.any((request) => request == 'late-duration:0'), isTrue);
      expect(requests.any((request) => request == 'late-duration:120'), isTrue);
      expect(published.any((line) => line[1] == 'duration ready'), isTrue);
      coordinator.onClose();
    });

    test('seeking updates the previous/current/next widget lines', () async {
      final coordinator = createCoordinator(loader: (track, duration,
          {forceReload = false}) async => {
            'synced':
                '[00:01.00]one\n[00:02.00]two\n[00:03.00]three',
          });
      await coordinator.start();
      mediaItems.add(song('seek', duration: const Duration(minutes: 3)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      positions.add(const Duration(milliseconds: 2500));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(published.last, ['one', 'two', 'three', 1]);
      coordinator.onClose();
    });
  });
}

class _FakeAudioHandler extends BaseAudioHandler {
  _FakeAudioHandler({
    required Stream<MediaItem?> mediaItemStream,
    required Stream<PlaybackState> playbackStateStream,
  }) {
    mediaItemStream.listen((item) => mediaItem.add(item));
    playbackStateStream.listen((state) => playbackState.add(state));
  }
}
