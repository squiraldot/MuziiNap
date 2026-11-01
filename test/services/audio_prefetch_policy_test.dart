import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/audio_handler.dart';

void main() {
  group('MyAudioHandler.shouldPrefetchNextTrack', () {
    test('does not prefetch before 80 percent completion', () {
      expect(
        MyAudioHandler.shouldPrefetchNextTrack(
          const Duration(milliseconds: 7999),
          const Duration(milliseconds: 10000),
        ),
        isFalse,
      );
    });

    test('prefetches at 80 percent completion', () {
      expect(
        MyAudioHandler.shouldPrefetchNextTrack(
          const Duration(milliseconds: 8000),
          const Duration(milliseconds: 10000),
        ),
        isTrue,
      );
    });

    test('does not prefetch when duration is unknown or invalid', () {
      expect(
        MyAudioHandler.shouldPrefetchNextTrack(
          const Duration(seconds: 10),
          null,
        ),
        isFalse,
      );
      expect(
        MyAudioHandler.shouldPrefetchNextTrack(
          Duration.zero,
          Duration.zero,
        ),
        isFalse,
      );
    });
  });
}
