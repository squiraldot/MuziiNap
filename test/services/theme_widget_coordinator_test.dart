import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/theme_widget_coordinator.dart';

void main() {
  group('ThemeWidgetCoordinator', () {
    late _FakeAudioHandler handler;
    late List<ThemeWidgetPlaybackSnapshot> published;

    setUp(() {
      handler = _FakeAudioHandler();
      published = [];
    });

    test('publishes metadata and transport state without artwork', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (snapshot) async => published.add(snapshot),
      );

      await coordinator.start();
      handler.mediaItem.add(MediaItem(
        id: 'track-1',
        title: 'Track One',
        artist: 'Artist One',
        artUri: Uri.parse('https://example.com/art.jpg'),
        duration: const Duration(minutes: 3),
      ));
      handler.playbackState.add(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 12),
        shuffleMode: AudioServiceShuffleMode.all,
        repeatMode: AudioServiceRepeatMode.one,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(published.last.title, 'Track One');
      expect(published.last.artist, 'Artist One');
      expect(published.last.isPlaying, isTrue);
      expect(published.last.positionMs, 12000);
      expect(published.last.durationMs, 180000);
      expect(published.last.shuffleEnabled, isTrue);
      expect(published.last.repeatMode, 'ONE');
      expect(published.last.toChannelArguments().containsKey('artUri'), isFalse);
      coordinator.onClose();
    });

    test('publishes pause changes for the current track', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (snapshot) async => published.add(snapshot),
      );
      await coordinator.start();
      handler.mediaItem.add(MediaItem(id: 'track-2', title: 'Second', artist: 'Singer'));
      handler.playbackState.add(PlaybackState(playing: true));
      handler.playbackState.add(PlaybackState(playing: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(published.last.title, 'Second');
      expect(published.last.isPlaying, isFalse);
      coordinator.onClose();
    });

    test('does not publish duplicate snapshots', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (snapshot) async => published.add(snapshot),
      );
      await coordinator.start();
      handler.mediaItem.add(MediaItem(id: 'track-3', title: 'Same', artist: 'Singer'));
      handler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final count = published.length;
      handler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(published.length, count);
      coordinator.onClose();
    });

    test('handles unknown duration without a negative or overflowing position', () async {
      final coordinator = ThemeWidgetCoordinator(
        audioHandler: handler,
        publisher: (snapshot) async => published.add(snapshot),
      );
      await coordinator.start();
      handler.mediaItem.add(MediaItem(id: 'track-4', title: 'Unknown', artist: 'Singer'));
      handler.playbackState.add(PlaybackState(
        updatePosition: const Duration(seconds: 30),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(published.last.durationMs, 0);
      expect(published.last.positionMs, 30000);
      coordinator.onClose();
    });
  });
}

class _FakeAudioHandler extends BaseAudioHandler {}
