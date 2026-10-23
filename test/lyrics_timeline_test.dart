import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/utils/lyrics_timeline.dart';

void main() {
  group('LyricsTimeline.parse', () {
    test('parses LRC timestamps and sorts lines chronologically', () {
      final lines = LyricsTimeline.parse(
        '[00:02.50]second line\n[00:01.00]first line',
      );

      expect(lines.map((line) => line.startMs).toList(), [1000, 2500]);
      expect(lines.map((line) => line.text).toList(),
          ['first line', 'second line']);
    });

    test('supports multiple timestamps on one line', () {
      final lines = LyricsTimeline.parse(
        '[00:01.20][00:03.40]repeated line',
      );

      expect(lines.map((line) => line.startMs).toList(), [1200, 3400]);
      expect(lines.map((line) => line.text).toList(),
          ['repeated line', 'repeated line']);
    });

    test('ignores metadata and untimed lines', () {
      final lines = LyricsTimeline.parse(
        '[ar:Artist]\nuntimed text\n[00:04.5]timed text',
      );

      expect(lines.length, 1);
      expect(lines.single.startMs, 4500);
      expect(lines.single.text, 'timed text');
    });
  });

  group('LyricsTimeline.activeIndex', () {
    final lines = LyricsTimeline.parse(
      '[00:01.00]first\n[00:02.00]second\n[00:03.00]third',
    );

    test('returns no active line before the first timestamp', () {
      expect(LyricsTimeline.activeIndex(lines, 0), -1);
    });

    test('returns the most recent line at the playback position', () {
      expect(LyricsTimeline.activeIndex(lines, 2500), 1);
      expect(LyricsTimeline.activeIndex(lines, 3000), 2);
    });
  });
}
