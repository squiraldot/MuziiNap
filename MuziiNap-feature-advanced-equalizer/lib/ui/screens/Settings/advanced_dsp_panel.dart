import 'package:flutter/material.dart';

import '../../../models/equalizer.dart';

class AdvancedDspPanel extends StatelessWidget {
  const AdvancedDspPanel({
    super.key,
    required this.config,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
  });

  final AdvancedDspConfig config;
  final bool enabled;
  final ValueChanged<AdvancedDspConfig> onPreview;
  final ValueChanged<AdvancedDspConfig> onCommit;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'Advanced DSP',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('Bass, loudness, compressor, limiter and SoundFX'),
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('DSP engine'),
          subtitle: const Text('Enable advanced processing'),
          value: config.enabled,
          onChanged: enabled
              ? (value) => onCommit(config.copyWith(enabled: value))
              : null,
        ),
        _section(
          title: 'Bass Boost',
          enabled: enabled && config.enabled,
          value: config.bassBoostEnabled,
          onEnabled: (value) =>
              onCommit(config.copyWith(bassBoostEnabled: value)),
          children: [
            _slider(
              label: 'Amount',
              value: config.bassBoostAmountDb,
              min: 0,
              max: 12,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(bassBoostAmountDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(bassBoostAmountDb: value)),
            ),
            _slider(
              label: 'Frequency',
              value: config.bassBoostFrequencyHz,
              min: 40,
              max: 180,
              suffix: ' Hz',
              onChanged: (value) =>
                  onPreview(config.copyWith(bassBoostFrequencyHz: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(bassBoostFrequencyHz: value)),
            ),
            _slider(
              label: 'Q',
              value: config.bassBoostQ,
              min: 0.2,
              max: 2,
              suffix: '',
              onChanged: (value) =>
                  onPreview(config.copyWith(bassBoostQ: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(bassBoostQ: value)),
            ),
          ],
        ),
        _section(
          title: 'Loudness',
          enabled: enabled && config.enabled,
          value: config.loudnessEnabled,
          onEnabled: (value) =>
              onCommit(config.copyWith(loudnessEnabled: value)),
          children: [
            _slider(
              label: 'Amount',
              value: config.loudnessAmountDb,
              min: 0,
              max: 12,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(loudnessAmountDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(loudnessAmountDb: value)),
            ),
          ],
        ),
        _section(
          title: 'Compressor',
          enabled: enabled && config.enabled,
          value: config.compressorEnabled,
          onEnabled: (value) =>
              onCommit(config.copyWith(compressorEnabled: value)),
          children: [
            _slider(
              label: 'Threshold',
              value: config.compressorThresholdDb,
              min: -60,
              max: 0,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(compressorThresholdDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(compressorThresholdDb: value)),
            ),
            _slider(
              label: 'Ratio',
              value: config.compressorRatio,
              min: 1,
              max: 20,
              suffix: ':1',
              onChanged: (value) =>
                  onPreview(config.copyWith(compressorRatio: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(compressorRatio: value)),
            ),
            _slider(
              label: 'Attack',
              value: config.compressorAttackMs,
              min: 0.1,
              max: 100,
              suffix: ' ms',
              onChanged: (value) =>
                  onPreview(config.copyWith(compressorAttackMs: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(compressorAttackMs: value)),
            ),
            _slider(
              label: 'Release',
              value: config.compressorReleaseMs,
              min: 10,
              max: 1000,
              suffix: ' ms',
              onChanged: (value) =>
                  onPreview(config.copyWith(compressorReleaseMs: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(compressorReleaseMs: value)),
            ),
            _slider(
              label: 'Knee',
              value: config.compressorKneeDb,
              min: 0,
              max: 40,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(compressorKneeDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(compressorKneeDb: value)),
            ),
            _slider(
              label: 'Makeup',
              value: config.compressorMakeupGainDb,
              min: -12,
              max: 12,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(compressorMakeupGainDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(compressorMakeupGainDb: value)),
            ),
          ],
        ),
        _section(
          title: 'Limiter',
          enabled: enabled && config.enabled,
          value: true,
          showSwitch: false,
          onEnabled: (_) {},
          children: [
            _slider(
              label: 'Ceiling',
              value: config.limiterCeilingDb,
              min: -12,
              max: 0,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(limiterCeilingDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(limiterCeilingDb: value)),
            ),
            _slider(
              label: 'Release',
              value: config.limiterReleaseMs,
              min: 10,
              max: 1000,
              suffix: ' ms',
              onChanged: (value) =>
                  onPreview(config.copyWith(limiterReleaseMs: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(limiterReleaseMs: value)),
            ),
          ],
        ),
        _section(
          title: 'MuziiNap SoundFX',
          enabled: enabled && config.enabled,
          value: config.soundFxEnabled,
          onEnabled: (value) =>
              onCommit(config.copyWith(soundFxEnabled: value)),
          children: [
            _slider(
              label: 'XBass',
              value: config.xBassAmountDb,
              min: 0,
              max: 12,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(xBassAmountDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(xBassAmountDb: value)),
            ),
            _slider(
              label: 'XTreble',
              value: config.xTrebleAmountDb,
              min: 0,
              max: 12,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(xTrebleAmountDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(xTrebleAmountDb: value)),
            ),
            _slider(
              label: 'PowerBass',
              value: config.powerBassAmountDb,
              min: 0,
              max: 12,
              suffix: ' dB',
              onChanged: (value) =>
                  onPreview(config.copyWith(powerBassAmountDb: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(powerBassAmountDb: value)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dynamic Bass'),
              value: config.dynamicBassEnabled,
              onChanged: (value) =>
                  onCommit(config.copyWith(dynamicBassEnabled: value)),
            ),
            if (config.dynamicBassEnabled)
              _slider(
                label: 'Dynamic amount',
                value: config.dynamicBassAmountDb,
                min: 0,
                max: 12,
                suffix: ' dB',
                onChanged: (value) =>
                    onPreview(config.copyWith(dynamicBassAmountDb: value)),
                onChangeEnd: (value) =>
                    onCommit(config.copyWith(dynamicBassAmountDb: value)),
              ),
          ],
        ),
        _section(
          title: 'Stereo',
          enabled: enabled && config.enabled,
          value: config.surroundEnabled,
          onEnabled: (value) =>
              onCommit(config.copyWith(surroundEnabled: value)),
          children: [
            _slider(
              label: 'Balance',
              value: config.stereoBalance,
              min: -1,
              max: 1,
              suffix: '',
              onChanged: (value) =>
                  onPreview(config.copyWith(stereoBalance: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(stereoBalance: value)),
            ),
            _slider(
              label: 'Width',
              value: config.stereoWidth,
              min: 1,
              max: 2,
              suffix: 'x',
              onChanged: (value) =>
                  onPreview(config.copyWith(stereoWidth: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(stereoWidth: value)),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Balance is applied per channel. Width is combined with Android surround virtualization when supported.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        _section(
          title: 'Surround',
          enabled: enabled && config.enabled,
          value: config.surroundEnabled,
          onEnabled: (value) =>
              onCommit(config.copyWith(surroundEnabled: value)),
          children: [
            _slider(
              label: 'Width',
              value: config.surroundAmount,
              min: 0,
              max: 1,
              suffix: '',
              onChanged: (value) =>
                  onPreview(config.copyWith(surroundAmount: value)),
              onChangeEnd: (value) =>
                  onCommit(config.copyWith(surroundAmount: value)),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Uses the Android spatial/virtualizer effect when supported by the device.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required bool enabled,
    required bool value,
    required ValueChanged<bool> onEnabled,
    required List<Widget> children,
    bool showSwitch = true,
  }) {
    return ExpansionTile(
      enabled: enabled,
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (showSwitch)
            Switch.adaptive(
              value: value,
              onChanged: enabled ? onEnabled : null,
            ),
        ],
      ),
      children: children,
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(value.toStringAsFixed(value.abs() >= 10 ? 0 : 1) + suffix),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
