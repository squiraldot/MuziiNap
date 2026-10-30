import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:muziinap/services/playback_circuit_breaker.dart';

void main() {
  group('PlaybackCircuitBreaker', () {
    late StreamController<ProcessingState> processing;
    late StreamController<bool> playing;
    late StreamController<bool> online;
    late StreamController<bool> loadingIntent;
    late Duration position;
    var playbackRequested = false;
    var exhaustedCount = 0;

    setUp(() {
      processing = StreamController<ProcessingState>.broadcast();
      playing = StreamController<bool>.broadcast();
      online = StreamController<bool>.broadcast();
      loadingIntent = StreamController<bool>.broadcast();
      position = const Duration(seconds: 42);
      playbackRequested = false;
      exhaustedCount = 0;
    });

    tearDown(() async {
      await processing.close();
      await playing.close();
      await online.close();
      await loadingIntent.close();
    });

    PlaybackCircuitBreaker createBreaker(
      List<(Duration, int)> recoveries, {
      int maxRetries = 2,
    }) {
      return PlaybackCircuitBreaker(
        processingStateStream: processing.stream,
        playingStream: playing.stream,
        onlineStream: online.stream,
        loadingIntentStream: loadingIntent.stream,
        shouldMonitorPlayback: () => playbackRequested,
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
      playbackRequested = true;
      playing.add(true);
      processing.add(ProcessingState.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(recoveries, hasLength(1));
      expect(recoveries.single.$1, position);
      expect(recoveries.single.$2, 1);
      await breaker.dispose();
    });

    test('recovers a stuck handler loading spinner before player play starts', () async {
      final recoveries = <(Duration, int)>[];
      final breaker = createBreaker(recoveries);
      await breaker.start();
      breaker.setTrack('track-1');
      playbackRequested = true;
      loadingIntent.add(true);
      processing.add(ProcessingState.loading);
      // The just_audio playing stream is still false while setAudioSource is loading.
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(recoveries, hasLength(1));
      expect(recoveries.single.$1, position);
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
      playbackRequested = true;
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
      playbackRequested = true;
      playing.add(true);
      processing.add(ProcessingState.loading);
      await Future<void>.delayed(const Duration(milliseconds: 90));
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
      playbackRequested = true;
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
