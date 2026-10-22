import 'dart:core';
import 'package:flutter/services.dart';
import './stream_service.dart';

//Not in use for now

Future<Map<String, dynamic>> getStreamInfo(
  String songId,
  dynamic token, {
  bool preferYoutubeExplode = false,
}) async {
  if (songId.startsWith("MPED")) {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final playerResponse = await StreamProvider.fetch(
    songId,
    preferYoutubeExplode: preferYoutubeExplode,
  );
  return playerResponse.hmStreamingData;
}
