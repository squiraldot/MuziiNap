import 'package:flutter_test/flutter_test.dart';
import '../lib/services/home_section_list.dart';

void main() {
  group('findHomeSectionList', () {
    test('finds authenticated Home shelves inside a two-column response', () {
      final expected = <String, dynamic>{
        'contents': [
          {'musicCarouselShelfRenderer': {'contents': []}},
        ],
        'continuations': [
          {'nextContinuationData': {'continuation': 'next-page'}},
        ],
      };
      final response = {
        'responseContext': {'sectionListRenderer': {'contents': []}},
        'contents': {
          'twoColumnBrowseResultsRenderer': {
            'secondaryContents': {
              'sectionListRenderer': expected,
            },
          },
        },
      };

      expect(findHomeSectionList(response), same(expected));
    });

    test('prefers the primary tab Home feed over unrelated nested sections', () {
      final primary = <String, dynamic>{'contents': <dynamic>[]};
      final response = {
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': primary,
                  },
                },
              },
            ],
          },
        },
        'responseContext': {
          'sectionListRenderer': {'contents': ['unrelated']},
        },
      };

      expect(findHomeSectionList(response), same(primary));
    });

    test('ignores section lists without a contents list', () {
      final response = {
        'metadata': {
          'sectionListRenderer': {'continuations': []},
        },
        'contents': {
          'sectionListRenderer': {'contents': ['valid']},
        },
      };

      expect(
        findHomeSectionList(response)?['contents'],
        ['valid'],
      );
    });

    test('returns null when no Home section list exists', () {
      expect(findHomeSectionList({'contents': []}), isNull);
    });
  });
}
