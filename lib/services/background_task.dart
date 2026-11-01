import 'dart:core';
import 'package:flutter/services.dart';

import 'device_adaptive_stream_selector.dart';
import './stream_service.dart';

//Not in use for now

Future<Map<String, dynamic>> getStreamInfo(
  String songId,
  dynamic token, {
  bool preferYoutubeExplode = false,
  String? preferredClient,
  Map<String, String>? authenticatedHeaders,
  Map<String, Object?>? deviceProfile,
}) async {
  if (songId.startsWith("MPED")) {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final profile = deviceProfile == null
      ? null
      : DeviceStreamProfile.fromJson(deviceProfile);
  final playerResponse = await StreamProvider.fetch(
    songId,
    preferYoutubeExplode: preferYoutubeExplode,
    preferredClient: preferredClient,
    authenticatedHeaders: authenticatedHeaders,
    deviceProfile: profile,
  );
  final result = playerResponse.hmStreamingData;
  if (profile != null) result['deviceProfile'] = profile.toJson();
  return result;
}
