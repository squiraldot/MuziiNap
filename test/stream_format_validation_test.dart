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

    test('rejects non-HTTPS, relative, malformed, and credential URLs', () {
      expect(
        StreamProvider.isValidAudioFormatUrl('http://example.com/audio'),
        isFalse,
      );
      expect(StreamProvider.isValidAudioFormatUrl('/videoplayback'), isFalse);
      expect(StreamProvider.isValidAudioFormatUrl('not a url'), isFalse);
      expect(StreamProvider.isValidAudioFormatUrl(null), isFalse);
      expect(
        StreamProvider.isValidAudioFormatUrl(
          'https://user:password@example.com/audio',
        ),
        isFalse,
      );
    });

    test('accepts audio MIME types and rejects video or missing MIME types', () {
      expect(
        StreamProvider.isAudioMimeType('audio/mp4; codecs="mp4a.40.2"'),
        isTrue,
      );
      expect(
        StreamProvider.isAudioMimeType('audio/webm; codecs="opus"'),
        isTrue,
      );
      expect(StreamProvider.isAudioMimeType('video/mp4'), isFalse);
      expect(StreamProvider.isAudioMimeType(null), isFalse);
    });

    test('keeps only supported direct audio formats and sorts by bitrate', () {
      final formats = StreamProvider.parseInnerTubeAudioFormats([
        {
          'itag': 251,
          'mimeType': 'audio/webm; codecs="opus"',
          'bitrate': 160000,
          'url': 'https://rr.googlevideo.com/high',
        },
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'bitrate': 128000,
          'url': 'https://rr.googlevideo.com/medium',
        },
        {
          'itag': 249,
          'mimeType': 'audio/webm; codecs="opus"',
          'bitrate': 50000,
          'url': 'https://rr.googlevideo.com/low',
        },
        {
          'itag': 18,
          'mimeType': 'video/mp4',
          'bitrate': 500000,
          'url': 'https://rr.googlevideo.com/video',
        },
        {
          'itag': 999,
          'mimeType': 'audio/mp4; codecs="unknown"',
          'bitrate': 90000,
          'url': 'https://rr.googlevideo.com/unknown-codec',
        },
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'bitrate': 120000,
          'url': 'http://rr.googlevideo.com/insecure',
        },
        {
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'bitrate': 120000,
          'signatureCipher': 's=encrypted',
        },
      ]);

      expect(formats, hasLength(3));
      expect(formats.map((format) => format.bitrate).toList(), [
        50000,
        128000,
        160000,
      ]);
      expect(formats.first.audioCodec, Codec.opus);
      expect(formats[1].audioCodec, Codec.mp4a);
      expect(formats.last.url, 'https://rr.googlevideo.com/high');
    });

    test('uses the lowest and highest bitrate as low and high quality', () {
      final provider = StreamProvider(
        playable: true,
        audioFormats: [
          Audio(
            itag: 249,
            audioCodec: Codec.opus,
            bitrate: 50000,
            duration: 0,
            loudnessDb: 0,
            url: 'https://rr.googlevideo.com/low',
            size: 0,
          ),
          Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 128000,
            duration: 0,
            loudnessDb: 0,
            url: 'https://rr.googlevideo.com/high',
            size: 0,
          ),
        ],
      );

      expect(provider.lowQualityAudio?.bitrate, 50000);
      expect(provider.highestQualityAudio?.bitrate, 128000);
    });
  });
}
