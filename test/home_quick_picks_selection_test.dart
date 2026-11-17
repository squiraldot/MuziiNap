import 'package:flutter_test/flutter_test.dart';
import '../lib/models/quick_picks.dart';
import '../lib/utils/home_quick_picks_selection.dart';

void main() {
  group('selectHomeQuickPicks', () {
    test('promotes the named Quick picks shelf even when another shelf comes first', () {
      final quickPicks = QuickPicks([], title: 'Quick picks for you');
      final sections = <dynamic>[
        'Playlist shelf',
        quickPicks,
        'Listen again',
      ];

      final selection = selectHomeQuickPicks(sections);

      expect(selection.quickPicks, same(quickPicks));
      expect(selection.remainingSections, ['Playlist shelf', 'Listen again']);
    });

    test('does not mistake Listen again for the Quick picks shelf', () {
      final listenAgain = QuickPicks([], title: 'Listen again');

      final selection = selectHomeQuickPicks([listenAgain, 'Albums']);

      expect(selection.quickPicks, isNull);
      expect(selection.remainingSections, [listenAgain, 'Albums']);
    });

    test('leaves sections intact when Quick picks is absent', () {
      final sections = <dynamic>['Albums', 'Playlists'];

      final selection = selectHomeQuickPicks(sections);

      expect(selection.quickPicks, isNull);
      expect(selection.remainingSections, sections);
    });
  });
}
