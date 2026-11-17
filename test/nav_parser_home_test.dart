import 'package:flutter_test/flutter_test.dart';
import '../lib/services/nav_parser.dart';

void main() {
  test('reads Quick picks title from an alternate carousel header renderer', () {
    final sections = parseMixedContent([
      {
        'musicCarouselShelfRenderer': {
          'header': {
            'musicCarouselShelfHeaderBasicRenderer': {
              'title': {
                'runs': [
                  {'text': 'Quick picks'},
                ],
              },
            },
          },
          'contents': [
            {
              'musicTwoRowItemRenderer': {
                'title': {
                  'runs': [
                    {
                      'text': 'Example song',
                      'navigationEndpoint': {
                        'watchEndpoint': {'videoId': 'example-video'},
                      },
                    },
                  ],
                },
                'subtitle': {
                  'runs': [
                    {'text': 'Example artist'},
                  ],
                },
                'navigationEndpoint': {
                  'watchEndpoint': {'videoId': 'example-video'},
                },
                'thumbnailRenderer': {
                  'musicThumbnailRenderer': {
                    'thumbnail': {
                      'thumbnails': [
                        {'url': 'https://example.com/song.jpg'},
                      ],
                    },
                  },
                },
              },
            },
          ],
        },
      },
    ]);

    expect(sections, hasLength(1));
    expect(sections.single['title'], 'Quick picks');
    expect(sections.single['contents'], hasLength(1));
  });
}
