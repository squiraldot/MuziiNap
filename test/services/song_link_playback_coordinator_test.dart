import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/song_link_playback_coordinator.dart';

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

void main() {
  group('SongLinkPlaybackCoordinator', () {
    test('resolves metadata and plays the exact requested video', () async {
      final played = <MediaItem>[];
      final coordinator = SongLinkPlaybackCoordinator(
        resolveSong: (id) async => _song(id),
        playSong: (song) async => played.add(song),
      );
      await coordinator.handle('dQw4w9WgXcQ');
      expect(played.map((song) => song.id), ['dQw4w9WgXcQ']);
      coordinator.dispose();
    });

    test('ignores invalid IDs without resolving metadata', () async {
      var resolveCount = 0;
      final coordinator = SongLinkPlaybackCoordinator(
        resolveSong: (id) async { resolveCount++; return _song(id); },
        playSong: (_) async {},
      );
      await coordinator.handle('not-valid');
      expect(resolveCount, 0);
      coordinator.dispose();
    });

    test('metadata failure does not call playback and reports failure', () async {
      var playCount = 0;
      final failures = <Object>[];
      final coordinator = SongLinkPlaybackCoordinator(
        resolveSong: (_) async => null,
        playSong: (_) async { playCount++; },
        onFailure: failures.add,
      );
      await coordinator.handle('dQw4w9WgXcQ');
      expect(playCount, 0);
      expect(failures, hasLength(1));
      coordinator.dispose();
    });

    test('a mismatched metadata item is rejected', () async {
      var playCount = 0;
      final failures = <Object>[];
      final coordinator = SongLinkPlaybackCoordinator(
        resolveSong: (_) async => _song('aqz-KE-bpKQ'),
        playSong: (_) async { playCount++; },
        onFailure: failures.add,
      );
      await coordinator.handle('dQw4w9WgXcQ');
      expect(playCount, 0);
      expect(failures, hasLength(1));
      coordinator.dispose();
    });

    test('latest request wins when metadata responses complete out of order', () async {
      final first = Completer<MediaItem?>();
      final second = Completer<MediaItem?>();
      final played = <MediaItem>[];
      final coordinator = SongLinkPlaybackCoordinator(
        resolveSong: (id) => id == 'dQw4w9WgXcQ' ? first.future : second.future,
        playSong: (song) async => played.add(song),
      );
      final firstRequest = coordinator.handle('dQw4w9WgXcQ');
      final secondRequest = coordinator.handle('aqz-KE-bpKQ');
      second.complete(_song('aqz-KE-bpKQ'));
      await secondRequest;
      first.complete(_song('dQw4w9WgXcQ'));
      await firstRequest;
      expect(played.map((song) => song.id), ['aqz-KE-bpKQ']);
      coordinator.dispose();
    });

    test('disposed coordinator ignores pending metadata results', () async {
      final pending = Completer<MediaItem?>();
      final played = <MediaItem>[];
      final coordinator = SongLinkPlaybackCoordinator(
        resolveSong: (_) => pending.future,
        playSong: (song) async => played.add(song),
      );
      final request = coordinator.handle('dQw4w9WgXcQ');
      coordinator.dispose();
      pending.complete(_song('dQw4w9WgXcQ'));
      await request;
      expect(played, isEmpty);
    });
  });
}
