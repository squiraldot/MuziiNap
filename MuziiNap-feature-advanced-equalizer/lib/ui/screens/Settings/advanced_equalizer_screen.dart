import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../models/equalizer.dart';
import '../../../services/constant.dart';
import '../../player/player_controller.dart';
import 'advanced_dsp_panel.dart';
import 'autoeq_panel.dart';
import 'equalizer_preset_panel.dart';
import 'parametric_equalizer_editor.dart';
import 'spectrum_analyzer_panel.dart';

class AdvancedEqualizerScreen extends StatefulWidget {
  const AdvancedEqualizerScreen({super.key});

  @override
  State<AdvancedEqualizerScreen> createState() =>
      _AdvancedEqualizerScreenState();
}

class _AdvancedEqualizerScreenState extends State<AdvancedEqualizerScreen> {
  late EqualizerConfig _config;
  bool _saving = false;
  bool _parametricMode = false;
  Future<void> _previewQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _config = _loadConfig();
    _parametricMode = _config.bands.length != 10;
  }

  EqualizerConfig _loadConfig() {
    final saved = Hive.box(appPrefsBoxName).get('equalizerConfig');
    if (saved is String) {
      try {
        return EqualizerConfig.fromJson(
          Map<String, Object?>.from(jsonDecode(saved) as Map),
        );
      } catch (_) {}
    }
    return EqualizerConfig.graphic10Band();
  }

  Future<void> _preview(EqualizerConfig config) {
    setState(() => _config = config);
    _previewQueue = _previewQueue.then(
      (_) => Get.find<PlayerController>().applyEqualizerConfig(config),
    );
    return _previewQueue;
  }

  Future<void> _commit(EqualizerConfig config) async {
    setState(() {
      _config = config;
      _saving = true;
    });
    try {
      await _previewQueue;
      await Get.find<PlayerController>().setEqualizerConfig(config);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewBandGain(int index, double gainDb) async {
    final bands = List<EqualizerBand>.from(_config.bands);
    bands[index] = bands[index].copyWith(gainDb: gainDb);
    await _preview(_config.copyWith(bands: bands));
  }

  Future<void> _previewBandGainFromGraph(Offset position, Size size) async {
    if (_config.bands.isEmpty || size.width <= 0 || size.height <= 0) return;
    final x = (position.dx / size.width).clamp(0.0, 1.0).toDouble();
    final minLog = math.log(31) / math.ln10;
    final maxLog = math.log(16000) / math.ln10;
    final targetLog = minLog + x * (maxLog - minLog);
    var index = 0;
    var distance = double.infinity;
    for (var i = 0; i < _config.bands.length; i++) {
      final bandLog = math.log(_config.bands[i].frequency) / math.ln10;
      final d = (bandLog - targetLog).abs();
      if (d < distance) {
        distance = d;
        index = i;
      }
    }
    final y = (position.dy / size.height).clamp(0.0, 1.0).toDouble();
    final gain = (15 - y * 30).clamp(-15.0, 15.0).toDouble();
    await _previewBandGain(index, gain);
  }

  @override
  Widget build(BuildContext context) {
    final frequencies =
        _config.bands.map((band) => band.frequency.round()).toList();

    final switchTheme = Theme.of(context).switchTheme.copyWith(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : Colors.grey.shade500),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.grey.shade700 : Colors.grey.shade900),
      trackOutlineColor: WidgetStateProperty.all(Colors.grey.shade700),
    );

    return Theme(
      data: Theme.of(context).copyWith(switchTheme: switchTheme),
      child: Scaffold(
        appBar: AppBar(
        title: const Text('Advanced Equalizer'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            onPressed: _saving
                ? null
                : () => _commit(EqualizerConfig.graphic10Band()),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Advanced Equalizer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: _config.enabled,
                onChanged: (value) =>
                    _commit(_config.copyWith(enabled: value)),
              ),
            ],
          ),
          Text(
            'Changes are applied to the current playback session.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          EqualizerPresetPanel(
            config: _config,
            persistChanges: _saving,
            onApplyConfig: (config) => _commit(config),
          ),
          const SizedBox(height: 16),
          Center(
            child: ToggleButtons(
              isSelected: [_parametricMode == false, _parametricMode],
              onPressed: _saving
                  ? null
                  : (index) => setState(() => _parametricMode = index == 1),
              borderRadius: BorderRadius.circular(10),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Graphic'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Parametric'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_parametricMode)
            ParametricEqualizerEditor(
              config: _config,
              enabled: _config.enabled,
              onChanged: (config) => _commit(config),
            )
          else
            LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, 190);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) =>
                    _previewBandGainFromGraph(details.localPosition, size),
                onPanEnd: (_) => _commit(_config),
                child: SizedBox(
                  height: size.height,
                  width: size.width,
                  child: CustomPaint(
                    painter: _EqualizerCurvePainter(
                      bands: _config.bands,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('Preamp'),
              const Spacer(),
              Text(_config.preampDb.toStringAsFixed(1) + ' dB'),
            ],
          ),
          Slider(
            min: -15,
            max: 15,
            value: _config.preampDb,
            onChanged: (value) =>
                _preview(_config.copyWith(preampDb: value)),
            onChangeEnd: (value) =>
                _commit(_config.copyWith(preampDb: value)),
          ),
          if (!_parametricMode) ...[
            const SizedBox(height: 8),
            const Text(
              'Bands',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _config.bands.length; i++)
              _BandSlider(
                frequency: frequencies[i],
                gainDb: _config.bands[i].gainDb,
                enabled: _config.enabled,
                onChanged: (value) => _previewBandGain(i, value),
                onChangeEnd: (value) => _commit(
                  _config.copyWith(
                    bands: [
                      for (var j = 0; j < _config.bands.length; j++)
                        j == i
                            ? _config.bands[j].copyWith(gainDb: value)
                            : _config.bands[j],
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          AutoEqPanel(
            onApplyConfig: (config) async {
              setState(() => _parametricMode = true);
              await _commit(config);
            },
          ),
          const SizedBox(height: 12),
          SpectrumAnalyzerPanel(
            config: _config,
            onConfigChanged: (config) => _preview(config),
          ),
          const SizedBox(height: 12),
          AdvancedDspPanel(
            config: _config.advancedDsp,
            enabled: _config.enabled,
            onPreview: (advanced) =>
                _preview(_config.copyWith(advancedDsp: advanced)),
            onCommit: (advanced) =>
                _commit(_config.copyWith(advancedDsp: advanced)),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Limiter'),

            subtitle:
                const Text('Protects against clipping when boosting bands.'),
            value: _config.limiterEnabled,
            onChanged: _config.enabled
                ? (value) =>
                    _commit(_config.copyWith(limiterEnabled: value))
                : null,
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GainField extends StatefulWidget {
  const _GainField({
    required this.gainDb,
    required this.enabled,
    required this.onSubmitted,
  });

  final double gainDb;
  final bool enabled;
  final ValueChanged<double> onSubmitted;

  @override
  State<_GainField> createState() => _GainFieldState();
}

class _GainFieldState extends State<_GainField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.gainDb.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _GainField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gainDb != widget.gainDb) {
      _controller.text = widget.gainDb.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Gain in decibels',
      value: widget.gainDb.toStringAsFixed(1) + ' dB',
      textField: true,
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          suffixText: ' dB',
        ),
        onSubmitted: (value) {
          final parsed = double.tryParse(value);
          if (parsed != null) {
            widget.onSubmitted(parsed.clamp(-15.0, 15.0).toDouble());
          }
        },
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.frequency,
    required this.gainDb,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int frequency;
  final double gainDb;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            frequency >= 1000
                ? (frequency ~/ 1000).toString() + 'k'
                : frequency.toString(),
            textAlign: TextAlign.end,
          ),
        ),
        Expanded(
          child: Slider(
            min: -15,
            max: 15,
            value: gainDb,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ),
        SizedBox(
          width: 68,
          child: _GainField(
            gainDb: gainDb,
            enabled: enabled,
            onSubmitted: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _EqualizerCurvePainter extends CustomPainter {
  const _EqualizerCurvePainter({
    required this.bands,
  });

  final List<EqualizerBand> bands;
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final curvePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var i = 0; i <= 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < bands.length; i++) {
      final x = _frequencyX(bands[i].frequency, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final path = Path();
    for (var i = 0; i < bands.length; i++) {
      final x = _frequencyX(bands[i].frequency, size.width);
      final y =
          ((15 - bands[i].gainDb) / 30).clamp(0.0, 1.0).toDouble() * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 5, dotPaint);
    }

    canvas.drawPath(path, curvePaint);

    final zeroY = size.height / 2;
    final zeroPaint = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
  }

  double _frequencyX(double frequency, double width) {
    final minLog = math.log(31) / math.ln10;
    final maxLog = math.log(16000) / math.ln10;
    final valueLog = math.log(frequency.clamp(31.0, 16000.0).toDouble()) / math.ln10;
    return ((valueLog - minLog) / (maxLog - minLog)).clamp(0.0, 1.0).toDouble() * width;
  }

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) {
    return oldDelegate.bands != bands;
  }
}
