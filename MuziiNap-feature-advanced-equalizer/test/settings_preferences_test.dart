import 'package:flutter_test/flutter_test.dart';
import '../lib/ui/screens/Settings/settings_preferences.dart';

void main() {
  test('uses the Android default only when no preference is stored', () {
    expect(resolveBottomNavBarPreference(storedValue: null), isTrue);
  });

  test('restores a saved navigation preference instead of overwriting it', () {
    expect(resolveBottomNavBarPreference(storedValue: false), isFalse);
    expect(resolveBottomNavBarPreference(storedValue: true), isTrue);
  });
}
