import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// App-lifetime owner for the AudioService handler and Android audio focus.
///
/// AudioService's handler must extend BaseAudioHandler, so this GetxService
/// owns its lifetime while preserving Get.find<AudioHandler>().
class AudioPlaybackService extends GetxService {
  AudioPlaybackService(this.handler);

  /// Configure audio focus before exposing the playback service to the UI.
  static Future<AudioPlaybackService> create(AudioHandler handler) async {
    final service = AudioPlaybackService(handler);
    await service._configureAudioSession();
    return service;
  }

  final AudioHandler handler;
  final List<StreamSubscription<dynamic>> _sessionSubscriptions = [];
  bool _closed = false;

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _sessionSubscriptions.add(
      session.interruptionEventStream.listen(
        (event) {
          if (_closed) return;
          if (event.begin) {
            switch (event.type) {
              case AudioInterruptionType.duck:
                unawaited(_sendFocusAction('audioFocusDuck'));
                break;
              case AudioInterruptionType.pause:
                // Calls and non-duckable transient/permanent focus losses must
                // stop playback. We deliberately do not auto-resume on "end".
                unawaited(_sendFocusAction('audioFocusPause'));
                break;
              case AudioInterruptionType.unknown:
                // Unknown focus loss is handled conservatively like a pause.
                unawaited(_sendFocusAction('audioFocusPause'));
                break;
            }
          } else if (event.type == AudioInterruptionType.duck) {
            unawaited(_sendFocusAction('audioFocusRestore'));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Audio focus interruption stream failed: $error');
        },
      ),
    );

    _sessionSubscriptions.add(
      session.becomingNoisyEventStream.listen(
        (_) {
          if (!_closed) {
            // Wired headphones/Bluetooth route disconnected: pause immediately
            // to avoid unexpectedly playing through the device speaker.
            unawaited(_sendFocusAction('audioFocusNoisy'));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Audio becoming-noisy stream failed: $error');
        },
      ),
    );
  }

  Future<void> _sendFocusAction(String action) async {
    try {
      await handler.customAction(action);
    } catch (error, stackTrace) {
      debugPrint('Unable to apply $action to the audio engine: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void onClose() {
    _closed = true;
    for (final subscription in _sessionSubscriptions) {
      unawaited(subscription.cancel());
    }
    _sessionSubscriptions.clear();
    // Final application teardown only; never call from a player route.
    // MyAudioHandler cancels its Dart subscriptions and disposes AudioPlayer.
    unawaited(handler.customAction('dispose'));
    super.onClose();
  }
}
