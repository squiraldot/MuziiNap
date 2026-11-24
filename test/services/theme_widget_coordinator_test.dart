import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/theme_widget_coordinator.dart';

void main() {
  group('ThemeWidgetCoordinator', () {
    late _FakeAudioHandler handler;
    late List<(String, String, bool)> published;

    setUp(() {
      handler = _FakeAudioHandler();
      published = [];
    });

    tearDown(() {
      handler.close();
    });

    test('publishes track metadata and playback state without artwork', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (title, artist, isPlaying) async {
          published.add((title, artist, isPlaying));
        },
      );

      await coordinator.start();
      handler.mediaItem.add(MediaItem(
        id: 'track-1',
        title: 'Track One',
        artist: 'Artist One',
        artUri: Uri.parse('https://example.com/art.jpg'),
      ));
      handler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(Duration.zero);

      expect(published.last, ('Track One', 'Artist One', true));
      expect(published.last, isNot(contains('https://example.com/art.jpg')));
      coordinator.onClose();
    });

    test('publishes pause changes for the current track', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (title, artist, isPlaying) async {
          published.add((title, artist, isPlaying));
        },
      );

      await coordinator.start();
      handler.mediaItem.add(MediaItem(id: 'track-2', title: 'Second', artist: 'Singer'));
      handler.playbackState.add(PlaybackState(playing: true));
      handler.playbackState.add(PlaybackState(playing: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(published.last, ('Second', 'Singer', false));
      coordinator.onClose();
    });

    test('does not publish duplicate state snapshots', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (title, artist, isPlaying) async {
          published.add((title, artist, isPlaying));
        },
      );

      await coordinator.start();
      handler.mediaItem.add(MediaItem(id: 'track-3', title: 'Same', artist: 'Singer'));
      handler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      handler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(published, [('Same', 'Singer', true)]);
      coordinator.onClose();
    });
  });
}

class _FakeAudioHandler extends BaseAudioHandler {
  void close() {
    mediaItem.close();
    playbackState.close();
  }
}
