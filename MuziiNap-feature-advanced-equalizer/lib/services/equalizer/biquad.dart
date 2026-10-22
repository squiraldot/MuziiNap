import 'dart:math' as math;

class BiquadCoefficients {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  const BiquadCoefficients({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });
}

class BiquadCalculator {
  const BiquadCalculator._();

  static BiquadCoefficients peaking({
    required double sampleRate,
    required double frequency,
    required double gainDb,
    required double q,
  }) {
    if (!sampleRate.isFinite || sampleRate <= 0) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Sample rate must be positive',
      );
    }
    if (!frequency.isFinite ||
        frequency <= 0 ||
        frequency >= sampleRate / 2) {
      throw ArgumentError.value(
        frequency,
        'frequency',
        'Frequency must be below Nyquist',
      );
    }
    if (!gainDb.isFinite) {
      throw ArgumentError.value(gainDb, 'gainDb', 'Gain must be finite');
    }
    if (!q.isFinite || q <= 0) {
      throw ArgumentError.value(q, 'q', 'Q must be positive');
    }

    final omega = 2 * math.pi * frequency / sampleRate;
    final sinOmega = math.sin(omega);
    final cosOmega = math.cos(omega);
    final alpha = sinOmega / (2 * q);
    final amplitude = math.pow(10, gainDb / 40).toDouble();

    final b0 = 1 + alpha * amplitude;
    final b1 = -2 * cosOmega;
    final b2 = 1 - alpha * amplitude;
    final a0 = 1 + alpha / amplitude;
    final a1 = -2 * cosOmega;
    final a2 = 1 - alpha / amplitude;

    if (![b0, b1, b2, a0, a1, a2].every((value) => value.isFinite) ||
        a0.abs() < 1e-12) {
      throw StateError('Unable to calculate stable biquad coefficients');
    }

    return BiquadCoefficients(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }
}
