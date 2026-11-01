import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:muziinap/services/audio_playback_service.dart';
import 'package:muziinap/services/downloader.dart';

class _FakeAudioHandler implements AudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('download cache manager is a GetxService', () {
    expect(DownloadCacheService(), isA<GetxService>());
    // Legacy call sites still resolve through the Downloader type alias.
    expect(Downloader(), isA<DownloadCacheService>());
  });

  test('audio playback lifetime owner is a GetxService', () {
    final service = AudioPlaybackService(_FakeAudioHandler());
    expect(service, isA<GetxService>());
  });
}
