import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/stream_service.dart';

void main() {
  group('StreamProvider audio format validation', () {
    test('accepts HTTPS direct media URLs', () {
      expect(
        StreamProvider.isValidAudioFormatUrl(
          'https://rr.googlevideo.com/videoplayback?id=abc',
        ),
        isTrue,
      );
    });

    test('rejects non-HTTPS, relative, and malformed URLs', () {
      expect(StreamProvider.isValidAudioFormatUrl('http://example.com/audio'), isFalse);
      expect(StreamProvider.isValidAudioFormatUrl('/videoplayback'), isFalse);
      expect(StreamProvider.isValidAudioFormatUrl('not a url'), isFalse);
      expect(StreamProvider.isValidAudioFormatUrl(null), isFalse);
    });

    test('rejects URLs containing embedded credentials', () {
      expect(
        StreamProvider.isValidAudioFormatUrl(
          'https://user:password@example.com/audio',
        ),
        isFalse,
      );
    });

    test('accepts audio MIME types and rejects video or missing MIME types', () {
      expect(StreamProvider.isAudioMimeType('audio/mp4; codecs="mp4a.40.2"'), isTrue);
      expect(StreamProvider.isAudioMimeType('audio/webm; codecs="opus"'), isTrue);
      expect(StreamProvider.isAudioMimeType('video/mp4'), isFalse);
      expect(StreamProvider.isAudioMimeType(null), isFalse);
    });
  });
}
