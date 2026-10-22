import 'package:flutter_test/flutter_test.dart';
import '../lib/models/home_mood.dart';

void main() {
  test('parses a mood navigation renderer', () {
    final mood = HomeMood.fromRenderer({
      'buttonText': {'runs': [{'text': 'Focus'}]},
      'navigationEndpoint': {
        'browseEndpoint': {
          'browseId': 'FEmusic_moods_and_genres_category',
          'params': 'mood-token',
        },
      },
      'thumbnail': {
        'thumbnails': [
          {'url': 'https://example.com/focus.jpg'},
        ],
      },
    });

    expect(mood, isNotNull);
    expect(mood!.title, 'Focus');
    expect(mood.browseId, 'FEmusic_moods_and_genres_category');
    expect(mood.params, 'mood-token');
    expect(mood.thumbnailUrl, 'https://example.com/focus.jpg');
  });

  test('rejects a renderer without a browse endpoint', () {
    expect(
      HomeMood.fromRenderer({
        'title': {'simpleText': 'Focus'},
      }),
      isNull,
    );
  });
}
