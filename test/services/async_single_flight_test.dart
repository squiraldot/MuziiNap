import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/async_single_flight.dart';

void main() {
  group('AsyncSingleFlight', () {
    test('shares one pending operation across concurrent callers', () async {
      final gate = AsyncSingleFlight<String>();
      final completer = Completer<String>();
      var starts = 0;

      final first = gate.run(() {
        starts++;
        return completer.future;
      });
      final second = gate.run(() {
        starts++;
        return Future<String>.value('unexpected');
      });

      expect(identical(first, second), isTrue);
      expect(starts, 1);

      completer.complete('visitor-data');
      expect(await first, 'visitor-data');
      expect(await second, 'visitor-data');
    });

    test('allows a fresh operation after the previous one completes', () async {
      final gate = AsyncSingleFlight<int>();
      var starts = 0;

      final first = await gate.run(() async => ++starts);
      final second = await gate.run(() async => ++starts);

      expect(first, 1);
      expect(second, 2);
    });

    test('clears a failed operation so a later caller can retry', () async {
      final gate = AsyncSingleFlight<String>();
      var starts = 0;

      await expectLater(
        gate.run(() async {
          starts++;
          throw StateError('temporary failure');
        }),
        throwsStateError,
      );

      final recovered = await gate.run(() async {
        starts++;
        return 'recovered';
      });

      expect(recovered, 'recovered');
      expect(starts, 2);
    });
  });
}
