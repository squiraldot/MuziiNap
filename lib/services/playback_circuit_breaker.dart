import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Watches an active just_audio stream for a sustained loading/buffering stall.
///
/// The owner supplies the online signal and recovery callback so this service
/// does not own the player, resolver, queue, or app lifecycle.
class PlaybackCircuitBreaker {
  PlaybackCircuitBreaker({
    required Stream<ProcessingState> processingStateStream,
    required Stream<bool> playingStream,
    required Stream<bool> onlineStream,
    required Stream<bool> loadingIntentStream,
    required bool Function() shouldMonitorPlayback,
    required Future<bool> Function() checkOnline,
    required Duration Function() positionProvider,
    required Future<void> Function(Duration position, int retryNumber) onFrozen,
    required Future<void> Function() onRetriesExhausted,
    this.frozenThreshold = const Duration(milliseconds: 3501),
    this.maxRetriesPerTrack = 2,
  })  : _processingStateStream = processingStateStream,
        _playingStream = playingStream,
        _onlineStream = onlineStream,
        _loadingIntentStream = loadingIntentStream,
        _shouldMonitorPlayback = shouldMonitorPlayback,
        _checkOnline = checkOnline,
        _positionProvider = positionProvider,
        _onFrozen = onFrozen,
        _onRetriesExhausted = onRetriesExhausted {
    if (maxRetriesPerTrack < 0) {
      throw ArgumentError.value(maxRetriesPerTrack, 'maxRetriesPerTrack');
    }
    if (frozenThreshold <= Duration.zero) {
      throw ArgumentError.value(frozenThreshold, 'frozenThreshold');
    }
  }

  final Stream<ProcessingState> _processingStateStream;
  final Stream<bool> _playingStream;
  final Stream<bool> _onlineStream;
  final Stream<bool> _loadingIntentStream;
  final bool Function() _shouldMonitorPlayback;
  final Future<bool> Function() _checkOnline;
  final Duration Function() _positionProvider;
  final Future<void> Function(Duration position, int retryNumber) _onFrozen;
  final Future<void> Function() _onRetriesExhausted;

  /// Slightly above 3.5 seconds so a stall must exceed the requested threshold.
  final Duration frozenThreshold;
  final int maxRetriesPerTrack;

  StreamSubscription<ProcessingState>? _processingSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _onlineSubscription;
  StreamSubscription<bool>? _loadingIntentSubscription;
  Timer? _frozenTimer;

  String? _trackId;
  ProcessingState _processingState = ProcessingState.idle;
  bool _isPlaying = false;
  bool _isOnline = false;
  bool _isLoadingIntent = false;
  bool _recovering = false;
  bool _started = false;
  bool _disposed = false;
  int _retryCount = 0;
  bool _exhausted = false;

  int get retryCount => _retryCount;
  String? get trackId => _trackId;

  /// Starts observing streams once. The initial connectivity read completes
  /// before stream events are subscribed, avoiding a stale-read race.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    try {
      _isOnline = await _checkOnline();
    } catch (_) {
      _isOnline = false;
    }
    if (_disposed) return;

    _processingSubscription = _processingStateStream.listen((state) {
      _processingState = state;
      _evaluate();
    });
    _playingSubscription = _playingStream.listen((playing) {
      _isPlaying = playing;
      _evaluate();
    });
    _onlineSubscription = _onlineStream.listen((online) {
      _isOnline = online;
      _evaluate();
    });
    _loadingIntentSubscription = _loadingIntentStream.listen((loading) {
      _isLoadingIntent = loading;
      _evaluate();
    });
    _evaluate();
  }

  /// Retry budget belongs to a track, not a playback session. Re-selecting
  /// the same track (including an automatic retry) does not reset the budget.
  void setTrack(String? nextTrackId) {
    if (_disposed || _trackId == nextTrackId) return;
    _trackId = nextTrackId;
    _retryCount = 0;
    _exhausted = false;
    _cancelFrozenTimer();
    _evaluate();
  }

  void _evaluate() {
    if (_disposed ||
        !_started ||
        _recovering ||
        _trackId == null ||
        !_isOnline ||
        !(_isPlaying || _isLoadingIntent) ||
        !_shouldMonitorPlayback() ||
        _exhausted) {
      _cancelFrozenTimer();
      return;
    }

    _frozenTimer ??= Timer(frozenThreshold, _handleFrozenStream);
  }

  Future<void> _handleFrozenStream() async {
    _frozenTimer = null;
    if (_disposed ||
        _recovering ||
        _trackId == null ||
        !_isOnline ||
        !(_isPlaying || _isLoadingIntent) ||
        !_shouldMonitorPlayback() ||
        _exhausted) {
      _evaluate();
      return;
    }

    if (_retryCount >= maxRetriesPerTrack) {
      _exhausted = true;
      _recovering = true;
      try {
        await _onRetriesExhausted();
      } catch (_) {
        // The owner handles terminal UI/error reporting.
      } finally {
        _recovering = false;
      }
      return;
    }

    _recovering = true;
    final retryNumber = ++_retryCount;
    final cachedPosition = _positionProvider();
    try {
      await _onFrozen(cachedPosition, retryNumber);
    } catch (_) {
      // Recovery failures are owned/reported by the playback handler. The
      // circuit breaker must remain alive but never exceed its retry budget.
    } finally {
      _recovering = false;
      _evaluate();
    }
  }

  static bool isFrozenState(ProcessingState state) =>
      state == ProcessingState.buffering || state == ProcessingState.loading;

  void _cancelFrozenTimer() {
    _frozenTimer?.cancel();
    _frozenTimer = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelFrozenTimer();
    await _processingSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _onlineSubscription?.cancel();
    await _loadingIntentSubscription?.cancel();
    _processingSubscription = null;
    _playingSubscription = null;
    _onlineSubscription = null;
    _loadingIntentSubscription = null;
  }
}
