/// Parsed timestamped lyrics used by the in-player lyrics timeline.
class TimedLyricLine {
  const TimedLyricLine({required this.startMs, required this.text});

  final int startMs;
  final String text;
}

class LyricsTimeline {
  LyricsTimeline._();

  static final RegExp _timestampPattern =
      RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

  /// Parses LRC timestamps, including multiple timestamps on one lyric line.
  /// Untimed/metadata lines are ignored because they cannot be safely sought.
  static List<TimedLyricLine> parse(String source) {
    final lines = <TimedLyricLine>[];
    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final matches = _timestampPattern.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;

      final text = rawLine.replaceAll(_timestampPattern, '').trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fraction = match.group(3) ?? '';
        final millis = fraction.isEmpty
            ? 0
            : int.parse(fraction.padRight(3, '0').substring(0, 3));
        lines.add(TimedLyricLine(
          startMs: (minutes * 60 + seconds) * 1000 + millis,
          text: text,
        ));
      }
    }
    lines.sort((a, b) => a.startMs.compareTo(b.startMs));
    return List.unmodifiable(lines);
  }

  /// Returns the latest line whose timestamp is not after [positionMs].
  static int activeIndex(List<TimedLyricLine> lines, int positionMs) {
    var low = 0;
    var high = lines.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = low + ((high - low) ~/ 2);
      if (lines[mid].startMs <= positionMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
