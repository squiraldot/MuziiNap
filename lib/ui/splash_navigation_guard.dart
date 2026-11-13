import 'dart:async';

import 'package:flutter/foundation.dart';

/// Guarantees that the intro route cannot remain visible forever if the
/// platform video player fails to emit its completion event.
class SplashNavigationGuard {
  SplashNavigationGuard({
    required VoidCallback onTimeout,
    this.completionGrace = const Duration(seconds: 2),
  }) : _onTimeout = onTimeout;

  final VoidCallback _onTimeout;
  final Duration completionGrace;
  Timer? _timer;
  bool _finished = false;

  void arm(Duration mediaDuration) {
    if (_finished) return;
    _timer?.cancel();
    final fallback = mediaDuration + completionGrace;
    _timer = Timer(
      fallback.isNegative ? Duration.zero : fallback,
      _finish,
    );
  }

  void complete() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _timer = null;
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer = null;
    _onTimeout();
  }

  void dispose() {
    _finished = true;
    _timer?.cancel();
    _timer = null;
  }
}
