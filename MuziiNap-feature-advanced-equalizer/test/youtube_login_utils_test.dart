import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/youtube_login_utils.dart';

void main() {
  test('uses Google ServiceLogin for YouTube Music authentication', () {
    expect(
      buildYouTubeLoginUrl(),
      'https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&passive=true&continue=https%3A%2F%2Fmusic.youtube.com%2F',
    );
  });
}
