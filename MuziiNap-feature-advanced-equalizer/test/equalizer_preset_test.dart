import 'package:flutter_test/flutter_test.dart';
import '../lib/models/equalizer.dart';
import '../lib/models/equalizer_preset.dart';

void main() {
  group('EqualizerPreset', () {
    test('round-trips metadata and EQ config', () {
      final now = DateTime.utc(2026, 10, 6, 12, 0);
      final preset = EqualizerPreset(
        id: 'custom-1',
        name: 'My Bass',
        author: 'User',
        description: 'A custom bass profile',
        createdAt: now,
        updatedAt: now,
        isBuiltIn: false,
        config: EqualizerConfig.graphic10Band().copyWith(preampDb: -3),
      );

      expect(EqualizerPreset.fromJson(preset.toJson()), equals(preset));
    });

    test('rejects empty custom preset names', () {
      final now = DateTime.utc(2026, 10, 6);
      expect(
        () => EqualizerPreset(
          id: 'custom-1',
          name: '   ',
          author: 'User',
          description: '',
          createdAt: now,
          updatedAt: now,
          isBuiltIn: false,
          config: EqualizerConfig.graphic10Band(),
        ),
        throwsArgumentError,
      );
    });

    test('built-in presets are immutable and curated', () {
      final presets = EqualizerBuiltInPresets.all;

      expect(presets.length, greaterThanOrEqualTo(18));
      expect(presets.map((preset) => preset.name).toSet(), containsAll([
        'Flat',
        'Bass Boost',
        'Deep Bass',
        'Vocal',
        'Pop',
        'Rock',
        'Jazz',
        'Classical',
        'Acoustic',
        'EDM',
        'Hip-Hop',
        'Metal',
        'Podcast',
        'Warm',
        'Bright',
        'Night',
        'Cinematic',
        'Loud',
      ]));
      expect(presets.every((preset) => preset.isBuiltIn), isTrue);
      expect(
        presets.every((preset) => preset.config.bands.every((band) => band.enabled)),
        isTrue,
      );
      expect(
        presets.any((preset) => preset.name == 'Bass Boost' && preset.config.bands.any((band) => band.gainDb > 0)),
        isTrue,
      );
      expect(
        presets.any((preset) => preset.name == 'Vocal' && preset.config.bands.any((band) => band.gainDb > 0)),
        isTrue,
      );
    });
  });
}
