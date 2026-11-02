import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:muziinap/services/playback_error_message.dart';

void main() {
  group('playbackErrorMessage', () {
    test('preserves the native player error code and message', () {
      final error = PlayerException(2001, 'Decoder initialization failed', 0);

      expect(
        playbackErrorMessage(error),
        'Playback error (2001): Decoder initialization failed',
      );
    });

    test('preserves the original message from non-player exceptions', () {
      final error = Exception('SocketException: Failed host lookup');

      expect(
        playbackErrorMessage(error),
        'Exception: SocketException: Failed host lookup',
      );
    });

    test('never returns an empty message', () {
      expect(playbackErrorMessage(Exception('   ')), 'Playback failed (Exception)');
    });
  });
}
