import 'dart:async';
import 'dart:convert';

import 'package:jni/jni.dart';
import 'package:flutter/services.dart';
import '../native_bindings/andrid_utils.dart';

import '../models/equalizer.dart';

/// Pure helper used to make rapid slider changes deterministic in tests.
class EqualizerApplyGate {
  int? _sessionId;
  String? _configJson;

  bool shouldApply(int sessionId, String configJson) {
    return _sessionId != sessionId || _configJson != configJson;
  }

  void markApplied(int sessionId, String configJson) {
    _sessionId = sessionId;
    _configJson = configJson;
  }

  void clearSession(int sessionId) {
    if (_sessionId == sessionId) {
      _sessionId = null;
      _configJson = null;
    }
  }
}

class EqualizerService {
  static const MethodChannel _pcmDspChannel = MethodChannel('muziinap/pcm_dsp');
  static Equalizer? _equalizer;
  static final EqualizerApplyGate _applyGate = EqualizerApplyGate();
  static int? _activeSessionId;

  static int? get activeSessionId => _activeSessionId;

  static Equalizer get _instance => _equalizer ??= Equalizer();

  static bool openEqualizer(int sessionId) {
    final activity = JObject.fromReference(Jni.getCurrentActivity());
    try {
      final context = JObject.fromReference(Jni.getCachedApplicationContext());
      try {
        return _instance.openEqualizer(sessionId, context, activity);
      } finally {
        context.release();
      }
    } finally {
      activity.release();
    }
  }

  static Future<void> _pushPcmConfig(String configJson) async {
    try {
      await _pcmDspChannel.invokeMethod<bool>(
        'setConfig',
        <String, Object>{'config': configJson},
      );
    } catch (_) {
      // Native PCM processing is Android-only; keep the legacy effect fallback
      // available if the local just_audio fork isn't present on this platform.
    }
  }

  static bool applyConfig(int sessionId, EqualizerConfig config) {
    final configJson = jsonEncode(config.toJson());
    unawaited(_pushPcmConfig(configJson));
    if (sessionId <= 0) return false;

    if (!_applyGate.shouldApply(sessionId, configJson)) {
      return true;
    }

    // The custom PCM processor owns the graphic/parametric EQ, preamp,
    // output gain, stereo balance, and width. Keep the native Android effect
    // for its compressor/virtualizer path but flatten overlapping controls so
    // the same EQ curve is not applied twice.
    final nativeConfig = Map<String, Object>.from(config.toJson())
      ..['preamp'] = 0.0
      ..['outputGain'] = 0.0
      ..['bands'] = config.bands.map((band) {
        return Map<String, Object>.from(band.toJson())..['gainDb'] = 0.0;
      }).toList(growable: false);
    final nativeAdvanced = Map<String, Object>.from(config.advancedDsp.toJson())
      ..['stereoBalance'] = 0.0
      ..['stereoWidth'] = 1.0;
    nativeConfig['advancedDsp'] = nativeAdvanced;
    final nativeConfigJson = jsonEncode(nativeConfig);
    final context = nativeConfigJson.toJString();
    try {
      final success = _instance.applyEqualizerConfig(sessionId, context);
      if (success) {
        _applyGate.markApplied(sessionId, configJson);
      }
      return success;
    } finally {
      context.release();
    }
  }

  static void initAudioEffect(int sessionId) {
    if (sessionId <= 0 || _activeSessionId == sessionId) return;

    // Android can replace the playback session after player recreation or
    // output-route changes. Release the previous session before attaching the
    // native effects to the new one, otherwise DynamicsProcessing/Virtualizer
    // instances and control-session broadcasts can be left behind.
    final previousSessionId = _activeSessionId;
    if (previousSessionId != null) {
      endAudioEffect(previousSessionId);
    }

    final context = JObject.fromReference(Jni.getCachedApplicationContext());
    try {
      _instance.initAudioEffect(sessionId, context);
      _activeSessionId = sessionId;
    } finally {
      context.release();
    }
  }

  static void endAudioEffect(int sessionId) {
    if (sessionId <= 0) return;
    if (_activeSessionId == sessionId) _activeSessionId = null;
    _applyGate.clearSession(sessionId);

    final context = JObject.fromReference(Jni.getCachedApplicationContext());
    try {
      _instance.endAudioEffect(sessionId, context);
    } finally {
      context.release();
    }
  }
}
