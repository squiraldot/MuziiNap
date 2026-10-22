import 'dart:async';

import 'package:flutter/services.dart';

class PresetShareService {
  static const _methodChannel = MethodChannel('muziinap/preset_share_method');
  static const _eventChannel = EventChannel('muziinap/preset_share');

  static Future<String?> getInitialPreset() {
    return _methodChannel.invokeMethod<String>('getInitialPreset');
  }

  static Stream<String> get incomingPresets {
    return _eventChannel
        .receiveBroadcastStream()
        .where((value) => value is String)
        .cast<String>();
  }
}
