import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/ui/screens/Settings/donation_screen.dart';

void main() {
  testWidgets('starts with the burger meal selected and About-style header', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    expect(find.text('Support Us'), findsOneWidget);
    expect(find.text('₹99 Burger'), findsOneWidget);
    expect(find.text("We're Hungry but our Pocket is Lonely😭"), findsOneWidget);
    expect(find.text('Feed These Hungry Devs 🍔'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
  });

  testWidgets('shows meal labels without repeating their leading emojis', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    expect(find.text('₹29 Choti Fries'), findsOneWidget);
    expect(find.text('₹59 Cold Drink'), findsOneWidget);
    expect(find.text('₹99 Burger'), findsOneWidget);
    expect(find.text('₹199 Full Meal'), findsOneWidget);
    expect(find.text('₹29 Choti Fries 🍟'), findsNothing);
    expect(find.text('₹59 Cold Drink 🥤'), findsNothing);
  });

  testWidgets('does not show donation frequency choices', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    expect(find.text('How Often Will You Feed Us? 😂'), findsNothing);
    expect(find.text('One-time Donation'), findsNothing);
    expect(find.text('Monthly Support'), findsNothing);
  });

  testWidgets('selecting a meal updates the selected amount', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    await tester.tap(find.text('₹29 Choti Fries'));
    await tester.pumpAndSettle();

    expect(find.text('₹29 Choti Fries'), findsOneWidget);
  });

  testWidgets('custom amount input accepts a user-entered amount', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    await tester.enterText(find.byKey(const Key('custom-donation-amount')), '150');
    await tester.pump();

    expect(find.text('150'), findsOneWidget);
  });

  testWidgets('optional message remains editable', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    await tester.enterText(
      find.byKey(const Key('donation-message')),
      'Keep building!',
    );
    await tester.pump();

    expect(find.text('Keep building!'), findsOneWidget);
    expect(find.text('14 / 200'), findsOneWidget);
  });
}
