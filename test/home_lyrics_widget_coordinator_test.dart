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
        required bool forceReload,
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
        retryDelay: const Duration(milliseconds: 10),
        attemptDelay: const Duration(milliseconds: 1),
        widgetPublisher: (previous, current, next, index) async {
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
      positions.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, ['first']);
      expect(published.any((line) => line[1] == 'hello'), isTrue);
      coordinator.onClose();
    });

    test('clears the old track and ignores a stale lookup response', () async {
      final first = Completer<Map<String, dynamic>?>();
      final coordinator = createCoordinator(loader: (track, duration,
          {required bool forceReload}) {
        requests.add(track.id);
        if (track.id == 'old') return first.future;
        return Future.value({'synced': '[00:01.00]new line'});
      });
      await coordinator.start();
      mediaItems.add(song('old'));
      await Future<void>.delayed(Duration.zero);
      mediaItems.add(song('new'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      positions.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      first.complete({'synced': '[00:01.00]old line'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(published.first, ['', '', '', -1]);
      expect(published.any((line) => line[1] == 'new line'), isTrue);
      expect(published.any((line) => line[1] == 'old line'), isFalse);
      coordinator.onClose();
    });

    test('retries when duration metadata arrives after the track', () async {
      final coordinator = createCoordinator(loader: (track, duration,
          {required bool forceReload}) async {
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
      positions.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests.any((request) => request == 'late-duration:0'), isTrue);
      expect(requests.any((request) => request == 'late-duration:120'), isTrue);
      expect(published.any((line) => line[1] == 'duration ready'), isTrue);
      coordinator.onClose();
    });

    test('temporary provider failures are retried without a player screen', () async {
      var attempts = 0;
      final coordinator = createCoordinator(loader: (track, duration,
          {required bool forceReload}) async {
        attempts++;
        if (attempts <= 3) return null;
        return {'synced': '[00:01.00]recovered'};
      });
      await coordinator.start();
      mediaItems.add(song('temporary-failure'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      positions.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(attempts, greaterThanOrEqualTo(4));
      expect(published.any((line) => line[1] == 'recovered'), isTrue);
      coordinator.onClose();
    });

    test('late clear completion from an older track cannot invalidate the active lookup', () async {
      final oldClear = Completer<void>();
      final currentClear = Completer<void>();
      final currentLyrics = Completer<Map<String, dynamic>?>();
      var clearCount = 0;
      final requested = <String>[];
      final handler = _FakeAudioHandler(
        mediaItemStream: mediaItems.stream,
        playbackStateStream: playbackStates.stream,
      );
      final coordinator = HomeLyricsWidgetCoordinator(
        audioHandler: handler,
        positionStream: positions.stream,
        offsetLoader: (_) async => 0,
        retryDelay: const Duration(seconds: 1),
        widgetPublisher: (previous, current, next, index) async {
          if (index == -1) {
            clearCount++;
            if (clearCount == 2) await oldClear.future;
            if (clearCount == 3) await currentClear.future;
          } else {
            published.add([previous, current, next, index]);
          }
        },
        lyricsLoader: (track, duration, {required bool forceReload}) {
          requested.add(track.id);
          if (track.id == 'current') return currentLyrics.future;
          return Future.value({'synced': '[00:00.00]old'});
        },
      );

      await coordinator.start();
      mediaItems.add(song('old'));
      await Future<void>.delayed(Duration.zero);
      mediaItems.add(song('current'));
      await Future<void>.delayed(Duration.zero);

      // Complete the newer track's clear first, then leave its lyrics lookup
      // in flight while the older track's delayed clear completes.
      currentClear.complete();
      await Future<void>.delayed(Duration.zero);
      oldClear.complete();
      await Future<void>.delayed(Duration.zero);
      currentLyrics.complete({'synced': '[00:00.00]current'});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requested, ['current']);
      expect(published.any((line) => line[1] == 'current'), isTrue);
      expect(published.any((line) => line[1] == 'old'), isFalse);
      coordinator.onClose();
    });

    test('stale playback-state position cannot rewind the live position stream', () async {
      final coordinator = createCoordinator(loader: (track, duration,
          {required bool forceReload}) async => {
            'synced': '[00:00.00]one\\n[00:01.00]two',
          });
      await coordinator.start();
      mediaItems.add(song('position-race', duration: const Duration(minutes: 3)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      positions.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      playbackStates.add(PlaybackState(
        updatePosition: Duration.zero,
        updateTime: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(published.last[1], 'two');
      coordinator.onClose();
    });

    test('seeking updates the previous/current/next widget lines', () async {
      final coordinator = createCoordinator(loader: (track, duration,
          {required bool forceReload}) async => {
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
