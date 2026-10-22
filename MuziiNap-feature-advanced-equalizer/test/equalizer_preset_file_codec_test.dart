import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/models/equalizer.dart';
import '../lib/models/equalizer_preset.dart';
import '../lib/services/equalizer_preset_file_codec.dart';

void main() {
  final baseConfig = EqualizerConfig.graphic10Band().copyWith(
    enabled: true,
    preampDb: -3,
    outputGainDb: 1.5,
    limiterEnabled: true,
  );

  test('accepts mneq filenames case-insensitively and rejects other extensions', () {
    expect(EqualizerPresetFileCodec.isSupportedFileName('My_Preset.mneq'), isTrue);
    expect(EqualizerPresetFileCodec.isSupportedFileName('MY_PRESET.MNEQ'), isTrue);
    expect(EqualizerPresetFileCodec.isSupportedFileName('My_Preset.json'), isFalse);
    expect(EqualizerPresetFileCodec.isSupportedFileName('My_Preset.mneq.bak'), isFalse);
  });

  test('exports a portable v2 mneq document and imports it losslessly', () {
    final preset = EqualizerPreset(
      id: 'custom-1',
      name: 'My Bass',
      author: 'User',
      description: 'Test preset',
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 3),
      isBuiltIn: false,
      config: baseConfig,
    );

    final encoded = EqualizerPresetFileCodec.encode(preset);
    final json = jsonDecode(encoded) as Map<String, Object?>;

    expect(json['format'], 'muziinap-eq');
    expect(json['version'], 3);
    expect(json['name'], 'My Bass');
    expect(json['author'], 'User');
    expect(json.containsKey('id'), isFalse);
    expect(json.containsKey('createdAt'), isFalse);

    final imported = EqualizerPresetFileCodec.decode(encoded);

    expect(imported.name, preset.name);
    expect(imported.author, preset.author);
    expect(imported.description, preset.description);
    expect(imported.isBuiltIn, isFalse);
    expect(_portableConfigJson(imported.config), equals(_portableConfigJson(preset.config)));
  });



  test('preserves advanced DSP controls in mneq v2', () {
    final preset = EqualizerPreset(
      id: 'soundfx-1',
      name: 'SoundFX',
      author: 'User',
      description: 'Advanced DSP preset',
      createdAt: DateTime.utc(2026, 2, 1),
      updatedAt: DateTime.utc(2026, 2, 1),
      isBuiltIn: false,
      config: baseConfig.copyWith(
        advancedDsp: AdvancedDspConfig(
          bassBoostEnabled: true,
          bassBoostAmountDb: 7,
          compressorEnabled: true,
          compressorRatio: 4,
          soundFxEnabled: true,
          xBassAmountDb: 6,
          xTrebleAmountDb: 3,
          surroundEnabled: true,
          surroundAmount: 0.5,
        ),
      ),
    );

    final imported = EqualizerPresetFileCodec.decode(
      EqualizerPresetFileCodec.encode(preset),
    );

    expect(imported.config.advancedDsp, equals(preset.config.advancedDsp));
  });

  test('imports v2 presets with advanced DSP fields', () {
    final imported = EqualizerPresetFileCodec.decode(
      jsonEncode({
        'format': 'muziinap-eq',
        'version': 2,
        'name': 'Legacy v2',
        'author': 'User',
        'enabled': true,
        'preamp': 0,
        'outputGain': 0,
        'limiterEnabled': true,
        'advancedDsp': {
          'enabled': true,
          'bassBoostEnabled': true,
          'bassBoostAmountDb': 4,
          'stereoBalance': -0.25,
          'stereoWidth': 1.4,
        },
        'bands': [
          {
            'type': 'peaking',
            'frequency': 1000,
            'gainDb': 0,
            'q': 1,
            'enabled': true,
          },
        ],
      }),
    );

    expect(imported.config.advancedDsp.bassBoostAmountDb, 4);
    expect(imported.config.advancedDsp.stereoBalance, -0.25);
    expect(imported.config.advancedDsp.stereoWidth, 1.4);
  });

  test('continues importing v1 presets with advanced DSP defaults', () {
    final imported = EqualizerPresetFileCodec.decode(
      jsonEncode({
        'format': 'muziinap-eq',
        'version': 1,
        'name': 'Legacy',
        'author': 'User',
        'enabled': true,
        'preamp': 0,
        'bands': [
          {
            'type': 'peaking',
            'frequency': 1000,
            'gainDb': 0,
            'q': 1,
            'enabled': true,
          },
        ],
      }),
    );

    expect(imported.config.advancedDsp, equals(AdvancedDspConfig()));
  });

  test('exports built-in presets without making the portable file mutable', () {
    final builtIn = EqualizerBuiltInPresets.all.first;

    final encoded = EqualizerPresetFileCodec.encode(builtIn);
    final imported = EqualizerPresetFileCodec.decode(encoded);

    expect(imported.isBuiltIn, isFalse);
    expect(imported.name, builtIn.name);
    expect(_portableConfigJson(imported.config), equals(_portableConfigJson(builtIn.config)));
  });

  test('rejects malformed json and unsupported formats', () {
    expect(
      () => EqualizerPresetFileCodec.decode('{broken'),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => EqualizerPresetFileCodec.decode(
        jsonEncode({'format': 'other-eq', 'version': 1}),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects future schema versions instead of silently misreading them', () {
    expect(
      () => EqualizerPresetFileCodec.decode(
        jsonEncode({
          'format': 'muziinap-eq',
          'version': 4,
          'name': 'Future',
          'author': 'Someone',
          'enabled': true,
          'preamp': 0,
          'bands': <Object?>[],
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported equalizer preset version'),
        ),
      ),
    );
  });

  test('rejects invalid numeric values through the shared EQ validation', () {
    expect(
      () => EqualizerPresetFileCodec.decode(
        jsonEncode({
          'format': 'muziinap-eq',
          'version': 1,
          'name': 'Unsafe',
          'author': 'User',
          'enabled': true,
          'preamp': 0,
          'bands': [
            {
              'type': 'peaking',
              'frequency': 1000,
              'gainDb': 999,
              'q': 1,
              'enabled': true,
            },
          ],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('imports optional v1 fields with safe defaults for forward-compatible files',
      () {
    final imported = EqualizerPresetFileCodec.decode(
      jsonEncode({
        'format': 'muziinap-eq',
        'version': 1,
        'name': 'Minimal',
        'author': 'User',
        'enabled': true,
        'preamp': 0,
        'bands': [
          {
            'type': 'peaking',
            'frequency': 1000,
            'gainDb': 2,
            'q': 1,
            'enabled': true,
          },
        ],
      }),
    );

    expect(imported.config.outputGainDb, 0);
    expect(imported.config.limiterEnabled, true);
    expect(imported.config.bands.single.frequency, 1000);
  });
}

Map<String, Object?> _portableConfigJson(EqualizerConfig config) {
  final json = Map<String, Object?>.from(config.toJson());
  final bands = (json['bands'] as List).cast<Map<String, Object?>>();
  json['bands'] = bands.map((band) {
    final portableBand = Map<String, Object?>.from(band);
    portableBand.remove('id');
    return portableBand;
  }).toList(growable: false);
  return json;
}
