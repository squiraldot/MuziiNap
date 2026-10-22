import 'package:flutter_test/flutter_test.dart';
import '../lib/services/update_checker.dart';

void main() {
  group('SemanticVersion', () {
    test('compares v1.0.0 and v1.0.1 numerically', () {
      final current = SemanticVersion.tryParse('v1.0.0')!;
      final next = SemanticVersion.tryParse('v1.0.1')!;

      expect(next.compareTo(current), greaterThan(0));
      expect(current.compareTo(next), lessThan(0));
    });

    test('orders major, minor, patch, and prerelease versions', () {
      expect(
        SemanticVersion.tryParse('2.0.0')!
            .compareTo(SemanticVersion.tryParse('1.99.99')!),
        greaterThan(0),
      );
      expect(
        SemanticVersion.tryParse('1.2.0')!
            .compareTo(SemanticVersion.tryParse('1.1.99')!),
        greaterThan(0),
      );
      expect(
        SemanticVersion.tryParse('1.0.2')!
            .compareTo(SemanticVersion.tryParse('1.0.1')!),
        greaterThan(0),
      );
      expect(
        SemanticVersion.tryParse('1.0.0')!
            .compareTo(SemanticVersion.tryParse('1.0.0-rc.1')!),
        greaterThan(0),
      );
      expect(
        SemanticVersion.tryParse('1.0.0-rc.2')!
            .compareTo(SemanticVersion.tryParse('1.0.0-rc.10')!),
        lessThan(0),
      );
    });

    test('rejects malformed versions', () {
      expect(SemanticVersion.tryParse('v1.0'), isNull);
      expect(SemanticVersion.tryParse('1.0.0-01'), isNull);
      expect(SemanticVersion.tryParse('release-latest'), isNull);
    });
  });

  group('UpdateChecker.selectLatestStableRelease', () {
    test('ignores drafts, prereleases, and malformed tags', () {
      final latest = UpdateChecker.selectLatestStableRelease([
        {'tag_name': 'v9.0.0', 'draft': true, 'prerelease': false},
        {'tag_name': 'v8.0.0', 'draft': false, 'prerelease': true},
        {'tag_name': 'not-a-version', 'draft': false, 'prerelease': false},
        {'tag_name': 'v1.0.0', 'draft': false, 'prerelease': false, 'body': 'First'},
        {'tag_name': 'v1.0.2', 'draft': false, 'prerelease': false, 'body': 'Latest'},
        {'tag_name': 'v1.0.1', 'draft': false, 'prerelease': false, 'body': 'Older'},
      ]);

      expect(latest?.version, '1.0.2');
      expect(latest?.notes, 'Latest');
    });

    test('handles no eligible release and empty release notes', () {
      expect(
        UpdateChecker.selectLatestStableRelease([
          {'tag_name': 'v2.0.0', 'draft': true, 'prerelease': false},
          {'tag_name': 'v2.1.0-rc.1', 'draft': false, 'prerelease': false},
        ]),
        isNull,
      );

      final release = UpdateChecker.selectLatestStableRelease([
        {'tag_name': 'v1.0.0', 'draft': false, 'prerelease': false},
      ]);
      expect(release?.notes, isEmpty);
    });
  });
}
