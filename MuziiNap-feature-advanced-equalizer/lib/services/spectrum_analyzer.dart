import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'equalizer.dart';

class SpectrumFrame {
  const SpectrumFrame({
    required this.magnitudes,
    required this.sampleRateHz,
    required this.captureSize,
  });

  final List<double> magnitudes;
  final int sampleRateHz;
  final int captureSize;

  List<double> normalized() {
    if (magnitudes.isEmpty) return const [];
    final cleaned = [
      for (final value in magnitudes)
        value.isFinite && value > 0 ? value : 0.0,
    ];
    final maxValue = cleaned.fold<double>(
      0,
      (max, value) => math.max(max, value),
    );
    if (maxValue <= 0) return List<double>.filled(cleaned.length, 0);
    return [for (final value in cleaned) (value / maxValue).clamp(0.0, 1.0)];
  }

  List<double> toLogBins({
    double minFrequencyHz = 31,
    double maxFrequencyHz = 16000,
    int binCount = 48,
  }) {
    if (magnitudes.isEmpty || sampleRateHz <= 0 || captureSize <= 0) {
      return List<double>.filled(binCount, 0);
    }

    final source = normalized();
    final nyquist = sampleRateHz / 2;
    final maxFrequency = math.min(maxFrequencyHz, nyquist);
    final minFrequency = math.max(1, minFrequencyHz);
    if (maxFrequency <= minFrequency || binCount <= 0) {
      return List<double>.filled(math.max(0, binCount), 0);
    }

    final output = <double>[];
    final minLog = math.log(minFrequency);
    final maxLog = math.log(maxFrequency);

    for (var index = 0; index < binCount; index++) {
      final start = minLog + (maxLog - minLog) * index / binCount;
      final end = minLog + (maxLog - minLog) * (index + 1) / binCount;
      final startFrequency = math.exp(start);
      final endFrequency = math.exp(end);
      final startIndex =
          (startFrequency * captureSize / sampleRateHz).floor().clamp(
                0,
                source.length - 1,
              );
      final endIndex =
          (endFrequency * captureSize / sampleRateHz).ceil().clamp(
                startIndex + 1,
                source.length,
              );
      var peak = 0.0;
      for (var sourceIndex = startIndex;
          sourceIndex < endIndex;
          sourceIndex++) {
        peak = math.max(peak, source[sourceIndex]);
      }
      output.add(peak);
    }
    return output;
  }

  static List<double> mergePeakHold(
    List<double> previous,
    List<double> current,
  ) {
    final length = math.min(previous.length, current.length);
    return [
      for (var index = 0; index < length; index++)
        math.max(previous[index], current[index]).clamp(0.0, 1.0),
      if (current.length > length)
        ...current.skip(length).map((value) => value.clamp(0.0, 1.0)),
    ];
  }
}

class SpectrumAnalyzerController extends ChangeNotifier {
  SpectrumAnalyzerController({
    this.updateInterval = const Duration(milliseconds: 60),
    this.binCount = 48,
  });

  final Duration updateInterval;
  final int binCount;

  static const _channel = MethodChannel('muziinap/spectrum_analyzer');

  Timer? _timer;
  int? _sessionId;
  bool _running = false;
  bool _peakHoldEnabled = false;
  double _smoothing = 0.35;
  List<double> _levels = const [];
  List<double> _peakHold = const [];
  int _sampleRateHz = 0;

  List<double> get levels => _levels;
  List<double> get peakHold => _peakHold;
  int get sampleRateHz => _sampleRateHz;
  bool get isRunning => _running;
  bool get peakHoldEnabled => _peakHoldEnabled;
  double get smoothing => _smoothing;

  Future<bool> start(int sessionId) async {
    if (sessionId <= 0) return false;
    await stop();
    try {
      final result = await _channel.invokeMethod<bool>('start', {
        'sessionId': sessionId,
        'captureSize': 1024,
      });
      if (result != true) return false;
      _sessionId = sessionId;
      _running = true;
      _timer = Timer.periodic(updateInterval, (_) => _poll());
      notifyListeners();
      await _poll();
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_running) {
      try {
        await _channel.invokeMethod<void>('stop');
      } catch (_) {}
    }
    _sessionId = null;
    _running = false;
    _levels = const [];
    _peakHold = const [];
    _sampleRateHz = 0;
    notifyListeners();
  }

  void setPeakHoldEnabled(bool enabled) {
    _peakHoldEnabled = enabled;
    if (!enabled) _peakHold = const [];
    notifyListeners();
  }

  void setSmoothing(double value) {
    _smoothing = value.clamp(0.0, 0.95);
    notifyListeners();
  }

  void clearPeakHold() {
    _peakHold = const [];
    notifyListeners();
  }

  Future<void> _poll() async {
    if (!_running || _sessionId == null) return;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getFft');
      if (result == null) return;
      final raw = result['magnitudes'];
      if (raw is! List) return;
      final frame = SpectrumFrame(
        magnitudes: [
          for (final value in raw)
            value is num ? value.toDouble() : 0.0,
        ],
        sampleRateHz: (result['sampleRateHz'] as num?)?.toInt() ?? 0,
        captureSize: (result['captureSize'] as num?)?.toInt() ?? 0,
      );
      final next = frame.toLogBins(binCount: binCount);
      final smoothed = _levels.length == next.length
          ? [
              for (var index = 0; index < next.length; index++)
                _levels[index] * _smoothing + next[index] * (1 - _smoothing),
            ]
          : next;
      _levels = smoothed;
      _sampleRateHz = frame.sampleRateHz;
      if (_peakHoldEnabled) {
        _peakHold = _peakHold.length == smoothed.length
            ? SpectrumFrame.mergePeakHold(_peakHold, smoothed)
            : List<double>.from(smoothed);
      }
      notifyListeners();
    } catch (_) {
      // Analyzer failure must never affect playback.
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}

int? currentAndroidAudioSessionId() {
  try {
    return EqualizerService.activeSessionId;
  } catch (_) {
    return null;
  }
}
