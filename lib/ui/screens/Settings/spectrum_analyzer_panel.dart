import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/equalizer.dart';
import '../../../services/equalizer.dart';
import '../../../services/spectrum_analyzer.dart';

enum SpectrumDisplayMode { spectrum, eqCurve, both }

class SpectrumAnalyzerPanel extends StatefulWidget {
  const SpectrumAnalyzerPanel({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  final EqualizerConfig config;
  final ValueChanged<EqualizerConfig> onConfigChanged;

  @override
  State<SpectrumAnalyzerPanel> createState() => _SpectrumAnalyzerPanelState();
}

class _SpectrumAnalyzerPanelState extends State<SpectrumAnalyzerPanel> {
  late final SpectrumAnalyzerController _controller;
  Timer? _sessionTimer;
  SpectrumDisplayMode _mode = SpectrumDisplayMode.both;
  bool _permissionDenied = false;
  int? _startedSessionId;

  @override
  void initState() {
    super.initState();
    _controller = SpectrumAnalyzerController();
    _controller.addListener(_refresh);
    _startForCurrentSession();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) => _syncSession());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _startForCurrentSession() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }
    final sessionId = EqualizerService.activeSessionId;
    if (sessionId == null || sessionId <= 0) return;
    final started = await _controller.start(sessionId);
    if (mounted) {
      setState(() {
        _startedSessionId = started ? sessionId : null;
        _permissionDenied = !started;
      });
    }
  }

  Future<void> _syncSession() async {
    final sessionId = EqualizerService.activeSessionId;
    if (sessionId == _startedSessionId) return;
    if (sessionId == null || sessionId <= 0) {
      await _controller.stop();
      if (mounted) setState(() => _startedSessionId = null);
      return;
    }
    await _startForCurrentSession();
  }

  void _editFromGraph(Offset position, Size size) {
    if (widget.config.bands.isEmpty) return;
    final x = (position.dx / size.width).clamp(0.0, 1.0).toDouble();
    final minLog = math.log(31) / math.ln10;
    final maxLog = math.log(16000) / math.ln10;
    final targetLog = minLog + x * (maxLog - minLog);
    var index = 0;
    var distance = double.infinity;
    for (var i = 0; i < widget.config.bands.length; i++) {
      final bandLog = math.log(widget.config.bands[i].frequency) / math.ln10;
      final currentDistance = (bandLog - targetLog).abs();
      if (currentDistance < distance) {
        distance = currentDistance;
        index = i;
      }
    }
    final y = (position.dy / size.height).clamp(0.0, 1.0).toDouble();
    final gain = (15 - y * 30).clamp(-15.0, 15.0).toDouble();
    final bands = List<EqualizerBand>.from(widget.config.bands);
    bands[index] = bands[index].copyWith(gainDb: gain);
    widget.onConfigChanged(widget.config.copyWith(bands: bands));
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _controller.removeListener(_refresh);
    unawaited(_controller.stop());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(MediaQuery.sizeOf(context).width - 32, 220);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Spectrum Analyzer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _permissionDenied
                  ? 'Playback visualization permission is unavailable on this device.'
                  : _controller.isRunning
                      ? 'Realtime playback spectrum • ' + _controller.sampleRateHz.toString() + ' Hz'
                      : 'Start playback to visualize the current audio session.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SegmentedButton<SpectrumDisplayMode>(
              segments: const [
                ButtonSegment(value: SpectrumDisplayMode.spectrum, label: Text('Spectrum')),
                ButtonSegment(value: SpectrumDisplayMode.eqCurve, label: Text('EQ Curve')),
                ButtonSegment(value: SpectrumDisplayMode.both, label: Text('Both')),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: _mode == SpectrumDisplayMode.spectrum
                  ? null
                  : (details) => _editFromGraph(details.localPosition, size),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CustomPaint(
                  painter: _SpectrumPainter(
                    levels: _controller.levels,
                    peakHold: _controller.peakHoldEnabled ? _controller.peakHold : const [],
                    config: widget.config,
                    showSpectrum: _mode != SpectrumDisplayMode.eqCurve,
                    showEqCurve: _mode != SpectrumDisplayMode.spectrum,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Smoothing'),
                Expanded(
                  child: Slider(
                    value: _controller.smoothing,
                    min: 0,
                    max: 0.95,
                    onChanged: _controller.setSmoothing,
                  ),
                ),
                const Text('Peak'),
                Switch(
                  value: _controller.peakHoldEnabled,
                  onChanged: _controller.setPeakHoldEnabled,
                ),
              ],
            ),
            if (_controller.peakHoldEnabled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _controller.clearPeakHold,
                  child: const Text('Clear peaks'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({
    required this.levels,
    required this.peakHold,
    required this.config,
    required this.showSpectrum,
    required this.showEqCurve,
  });

  final List<double> levels;
  final List<double> peakHold;
  final EqualizerConfig config;
  final bool showSpectrum;
  final bool showEqCurve;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final spectrumPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.fill;
    final peakPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final curvePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var index = 0; index <= 8; index++) {
      final x = size.width * index / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (showSpectrum && levels.isNotEmpty) {
      final width = size.width / levels.length;
      for (var index = 0; index < levels.length; index++) {
        final level = levels[index].clamp(0.0, 1.0);
        final height = level * size.height;
        canvas.drawRect(
          Rect.fromLTWH(index * width, size.height - height, math.max(1, width - 1), height),
          spectrumPaint,
        );
      }
    }

    if (showSpectrum && peakHold.isNotEmpty) {
      final width = size.width / peakHold.length;
      for (var index = 0; index < peakHold.length; index++) {
        final y = size.height * (1 - peakHold[index].clamp(0.0, 1.0));
        canvas.drawLine(Offset(index * width, y), Offset((index + 1) * width, y), peakPaint);
      }
    }

    if (showEqCurve && config.bands.isNotEmpty) {
      final sorted = [...config.bands]..sort((a, b) => a.frequency.compareTo(b.frequency));
      final path = Path();
      for (var index = 0; index < sorted.length; index++) {
        final band = sorted[index];
        final x = _logX(band.frequency, size.width);
        final y = size.height * (1 - ((band.gainDb + 15) / 30));
        final point = Offset(x, y.clamp(0.0, size.height));
        if (index == 0) path.moveTo(point.dx, point.dy);
        else path.lineTo(point.dx, point.dy);
        canvas.drawCircle(point, 4, curvePaint);
      }
      canvas.drawPath(path, curvePaint);
    }
  }

  double _logX(double frequency, double width) {
    final minLog = math.log(31) / math.ln10;
    final maxLog = math.log(16000) / math.ln10;
    final value = math.log(frequency.clamp(31.0, 16000.0)) / math.ln10;
    return ((value - minLog) / (maxLog - minLog)).clamp(0.0, 1.0) * width;
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) => true;
}
