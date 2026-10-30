import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

/// App-lifetime owner for the AudioService handler.
///
/// AudioService's handler must extend BaseAudioHandler, so this GetxService
/// wrapper owns its lifetime while preserving Get.find<AudioHandler>().
class AudioPlaybackService extends GetxService {
  AudioPlaybackService(this.handler);

  final AudioHandler handler;

  @override
  void onClose() {
    // Final application teardown only; never call from a player route.
    // MyAudioHandler cancels its Dart subscriptions and disposes AudioPlayer.
    unawaited(handler.customAction('dispose'));
    super.onClose();
  }
}
