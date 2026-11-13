import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/media_item_lifecycle_guard.dart';

void main() {
  group('MediaItemLifecycleGuard', () {
    test('does not treat the initial null media item as a stop', () {
      final guard = MediaItemLifecycleGuard();

      expect(guard.shouldDismissFor(null), isFalse);
    });

    test('treats null as a stop after a real media item was received', () {
      final guard = MediaItemLifecycleGuard();

      expect(
        guard.shouldDismissFor(
          const MediaItem(id: 'song-1', title: 'Shared song'),
        ),
        isFalse,
      );
      expect(guard.shouldDismissFor(null), isTrue);
    });

    test('keeps treating subsequent null events as stopped after playback', () {
      final guard = MediaItemLifecycleGuard();

      guard.shouldDismissFor(
        const MediaItem(id: 'song-1', title: 'Shared song'),
      );

      expect(guard.shouldDismissFor(null), isTrue);
      expect(guard.shouldDismissFor(null), isTrue);
    });
  });
}
