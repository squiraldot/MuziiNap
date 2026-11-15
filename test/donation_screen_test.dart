import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/ui/screens/Settings/donation_screen.dart';

void main() {
  testWidgets('starts with the burger meal selected', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    expect(find.text('₹99'), findsOneWidget);
    expect(find.text("We're Hungry but our Pocket is Lonely😭"), findsOneWidget);
    expect(find.text('Feed These Hungry Devs 🍔'), findsOneWidget);
  });

  testWidgets('selecting a meal updates the selected amount', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    await tester.tap(find.text('Choti Fries'));
    await tester.pumpAndSettle();

    expect(find.text('₹29'), findsOneWidget);
  });

  testWidgets('custom amount input accepts a user-entered amount', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    await tester.enterText(find.byKey(const Key('custom-donation-amount')), '150');
    await tester.pump();

    expect(find.text('₹150'), findsOneWidget);
  });

  testWidgets('donation frequency and optional message are interactive', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    await tester.tap(find.text('Monthly Support'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('donation-message')),
      'Keep building!',
    );
    await tester.pump();

    expect(find.text('Monthly Support'), findsOneWidget);
    expect(find.text('14 / 200'), findsOneWidget);
  });
}
