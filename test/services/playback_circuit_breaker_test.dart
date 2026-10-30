import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:muziinap/services/playback_circuit_breaker.dart';

void main() {
  group('PlaybackCircuitBreaker', () {
    late StreamController<ProcessingState> processing;
    late StreamController<bool> playing;
    late StreamController<bool> online;
    late Duration position;
    var exhaustedCount = 0;

    setUp(() {
      processing = StreamController<ProcessingState>.broadcast();
      playing = StreamController<bool>.broadcast();
      online = StreamController<bool>.broadcast();
      position = const Duration(seconds: 42);
      exhaustedCount = 0;
    });

    tearDown(() async {
      await processing.close();
      await playing.close();
      await online.close();
    });

    PlaybackCircuitBreaker createBreaker(
      List<(Duration, int)> recoveries, {
      int maxRetries = 2,
    }) {
      return PlaybackCircuitBreaker(
        processingStateStream: processing.stream,
        playingStream: playing.stream,
        onlineStream: online.stream,
        checkOnline: () async => true,
        positionProvider: () => position,
        frozenThreshold: const Duration(milliseconds: 20),
        maxRetriesPerTrack: maxRetries,
        onFrozen: (cachedPosition, retry) async {
          recoveries.add((cachedPosition, retry));
        },
        onRetriesExhausted: () async {
          exhaustedCount++;
        },
      );
    }

    test('recovers a continuously buffering active stream while online', () async {
      final recoveries = <(Duration, int)>[];
      final breaker = createBreaker(recoveries);
      await breaker.start();
      breaker.setTrack('track-1');
      playing.add(true);
      processing.add(ProcessingState.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(recoveries, hasLength(1));
      expect(recoveries.single.$1, position);
      expect(recoveries.single.$2, 1);
      await breaker.dispose();
    });

    test('does not recover while paused or offline', () async {
      final recoveries = <(Duration, int)>[];
      final breaker = createBreaker(recoveries);
      await breaker.start();
      breaker.setTrack('track-1');
      online.add(false);
      playing.add(false);
      processing.add(ProcessingState.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(recoveries, isEmpty);

      online.add(true);
      playing.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(recoveries, hasLength(1));
      await breaker.dispose();
    });

    test('caps recovery at two attempts per track and resets on track change', () async {
      final recoveries = <(Duration, int)>[];
      final breaker = createBreaker(recoveries);
      await breaker.start();
      breaker.setTrack('track-1');
      playing.add(true);
      processing.add(ProcessingState.loading);
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(recoveries.map((item) => item.$2), [1, 2]);
      expect(exhaustedCount, 1);

      breaker.setTrack('track-2');
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(recoveries.map((item) => item.$2), [1, 2, 1]);
      expect(exhaustedCount, 1);
      await breaker.dispose();
    });

    test('ready state resets the continuous frozen interval', () async {
      final recoveries = <(Duration, int)>[];
      final breaker = createBreaker(recoveries);
      await breaker.start();
      breaker.setTrack('track-1');
      playing.add(true);
      processing.add(ProcessingState.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      processing.add(ProcessingState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(recoveries, isEmpty);
      processing.add(ProcessingState.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(recoveries, hasLength(1));
      await breaker.dispose();
    });
  });
}
