import 'package:flutter_test/flutter_test.dart';
import '../lib/services/equalizer.dart';

void main() {
  group('EqualizerApplyGate', () {
    test('applies a configuration until that session/config is marked', () {
      final gate = EqualizerApplyGate();

      expect(gate.shouldApply(1, '{"bass":1}'), isTrue);

      gate.markApplied(1, '{"bass":1}');

      expect(gate.shouldApply(1, '{"bass":1}'), isFalse);
    });

    test('applies when the session or configuration changes', () {
      final gate = EqualizerApplyGate();
      gate.markApplied(1, '{"bass":1}');

      expect(gate.shouldApply(2, '{"bass":1}'), isTrue);
      expect(gate.shouldApply(1, '{"bass":2}'), isTrue);
    });

    test('clearing a different session leaves the applied state intact', () {
      final gate = EqualizerApplyGate();
      gate.markApplied(1, '{"bass":1}');

      gate.clearSession(2);

      expect(gate.shouldApply(1, '{"bass":1}'), isFalse);
    });

    test('clearing the active session allows the configuration to reapply',
        () {
      final gate = EqualizerApplyGate();
      gate.markApplied(1, '{"bass":1}');

      gate.clearSession(1);

      expect(gate.shouldApply(1, '{"bass":1}'), isTrue);
    });
  });
}
