import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/ui/splash_navigation_guard.dart';

void main() {
  group('SplashNavigationGuard', () {
    test('falls through when the intro never reports completion', () async {
      var navigated = false;
      final guard = SplashNavigationGuard(onTimeout: () => navigated = true);

      guard.arm(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(navigated, isTrue);
      guard.dispose();
    });

    test('does not navigate after the intro completes', () async {
      var navigated = false;
      final guard = SplashNavigationGuard(onTimeout: () => navigated = true);

      guard.arm(const Duration(milliseconds: 10));
      guard.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(navigated, isFalse);
      guard.dispose();
    });

    test('rearming replaces the previous completion deadline', () async {
      var timeoutCount = 0;
      final guard = SplashNavigationGuard(onTimeout: () => timeoutCount++);

      guard.arm(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      guard.arm(const Duration(milliseconds: 40));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(timeoutCount, 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(timeoutCount, 1);
      guard.dispose();
    });

    test('dispose cancels a pending fallback', () async {
      var navigated = false;
      final guard = SplashNavigationGuard(onTimeout: () => navigated = true);

      guard.arm(const Duration(milliseconds: 10));
      guard.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(navigated, isFalse);
    });
  });
}
