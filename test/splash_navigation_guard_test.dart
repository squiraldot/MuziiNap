import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/ui/splash_navigation_guard.dart';

void main() {
  group('SplashNavigationGuard', () {
    testWidgets('falls through when the intro never reports completion',
        (tester) async {
      var navigated = false;
      final guard = SplashNavigationGuard(
        onTimeout: () => navigated = true,
        completionGrace: Duration.zero,
      );

      guard.arm(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));

      expect(navigated, isTrue);
      guard.dispose();
    });

    testWidgets('does not navigate after the intro completes', (tester) async {
      var navigated = false;
      final guard = SplashNavigationGuard(
        onTimeout: () => navigated = true,
        completionGrace: Duration.zero,
      );

      guard.arm(const Duration(milliseconds: 10));
      guard.complete();
      await tester.pump(const Duration(milliseconds: 20));

      expect(navigated, isFalse);
      guard.dispose();
    });

    testWidgets('rearming replaces the previous completion deadline',
        (tester) async {
      var timeoutCount = 0;
      final guard = SplashNavigationGuard(
        onTimeout: () => timeoutCount++,
        completionGrace: Duration.zero,
      );

      guard.arm(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 5));
      guard.arm(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 15));

      expect(timeoutCount, 0);
      await tester.pump(const Duration(milliseconds: 25));
      expect(timeoutCount, 1);
      guard.dispose();
    });

    testWidgets('dispose cancels a pending fallback', (tester) async {
      var navigated = false;
      final guard = SplashNavigationGuard(
        onTimeout: () => navigated = true,
        completionGrace: Duration.zero,
      );

      guard.arm(const Duration(milliseconds: 10));
      guard.dispose();
      await tester.pump(const Duration(milliseconds: 20));

      expect(navigated, isFalse);
    });
  });
}
