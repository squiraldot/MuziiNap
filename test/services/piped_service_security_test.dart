import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/piped_service.dart';

void main() {
  group('normalizePipedInstanceUrl', () {
    test('accepts HTTPS origins and removes trailing slashes', () {
      expect(
        normalizePipedInstanceUrl('https://piped.example/'),
        'https://piped.example',
      );
      expect(
        normalizePipedInstanceUrl('https://piped.example/api/'),
        'https://piped.example/api',
      );
    });

    test('rejects plaintext HTTP endpoints', () {
      expect(
        () => normalizePipedInstanceUrl('http://piped.example'),
        throwsArgumentError,
      );
    });

    test('rejects credential-bearing URLs', () {
      expect(
        () => normalizePipedInstanceUrl('https://user:pass@piped.example'),
        throwsArgumentError,
      );
    });

    test('rejects query and fragment components', () {
      expect(
        () => normalizePipedInstanceUrl('https://piped.example/?redirect=x'),
        throwsArgumentError,
      );
      expect(
        () => normalizePipedInstanceUrl('https://piped.example/#fragment'),
        throwsArgumentError,
      );
    });

    test('rejects URLs without a valid host', () {
      expect(
        () => normalizePipedInstanceUrl('https:///login'),
        throwsArgumentError,
      );
    });
  });
}
