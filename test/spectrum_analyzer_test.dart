import 'package:flutter_test/flutter_test.dart';
import '../lib/services/spectrum_analyzer.dart';

void main() {
  group('SpectrumFrame', () {
    test('maps FFT magnitudes to logarithmic display bins', () {
      final frame = SpectrumFrame(
        magnitudes: List<double>.generate(33, (index) => index.toDouble()),
        sampleRateHz: 48000,
        captureSize: 64,
      );

      final bins = frame.toLogBins(
        minFrequencyHz: 31,
        maxFrequencyHz: 16000,
        binCount: 16,
      );

      expect(bins, hasLength(16));
      expect(bins.every((value) => value.isFinite), isTrue);
      expect(bins.every((value) => value >= 0), isTrue);
    });

    test('normalizes magnitudes and clamps invalid values', () {
      final frame = SpectrumFrame(
        magnitudes: [0, double.nan, double.infinity, 2, 4],
        sampleRateHz: 48000,
        captureSize: 8,
      );

      final normalized = frame.normalized();
      expect(normalized, [0, 0, 0, 0.5, 1]);
    });

    test('peak hold retains previous peaks', () {
      final previous = [0.2, 0.8, 0.4];
      final current = [0.5, 0.3, 0.9];

      expect(
        SpectrumFrame.mergePeakHold(previous, current),
        [0.5, 0.8, 0.9],
      );
    });
  });
}
