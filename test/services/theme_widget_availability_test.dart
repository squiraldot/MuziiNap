import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/theme_widget_availability.dart';

void main() {
  group('ThemeWidgetAvailability', () {
    test('allows a distinct design when capacity remains', () {
      final availability = ThemeWidgetAvailability.fromStatus({
        'activeCount': 1,
        'pendingCount': 0,
        'remainingCapacity': 1,
        'widgets': [
          {'themeId': 'dragon-ball-z', 'designId': 'widget-1'},
        ],
      });
      expect(availability.canAdd('dragon-ball-z', 'widget-2'), isTrue);
    });

    test('rejects duplicate installed and pending identities regardless of size', () {
      final availability = ThemeWidgetAvailability.fromStatus({
        'activeCount': 1,
        'pendingCount': 1,
        'remainingCapacity': 0,
        'widgets': [
          {'themeId': 'dragon-ball-z', 'designId': 'widget-1', 'size': '4x2'},
        ],
        'pendingWidgets': [
          {'themeId': 'dragon-ball-z', 'designId': 'widget-2', 'size': '4x3'},
        ],
      });
      expect(availability.canAdd('dragon-ball-z', 'widget-1'), isFalse);
      expect(availability.canAdd('dragon-ball-z', 'widget-2'), isFalse);
    });

    test('rejects when both slots are occupied', () {
      final availability = ThemeWidgetAvailability.fromStatus({
        'activeCount': 2, 'pendingCount': 0, 'remainingCapacity': 0,
        'widgets': const [],
      });
      expect(availability.reasonFor('dragon-ball-z', 'widget-3'),
          'Both theme widget slots are occupied.');
    });

    test('fails closed during a recovery conflict', () {
      final availability = ThemeWidgetAvailability.fromStatus({
        'activeCount': 1, 'pendingCount': 0, 'remainingCapacity': 1,
        'recoveryConflict': true, 'widgets': const [],
      });
      expect(availability.canAdd('dragon-ball-z', 'widget-2'), isFalse);
    });
  });
}
