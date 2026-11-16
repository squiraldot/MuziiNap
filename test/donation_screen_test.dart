import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/ui/screens/Settings/donation_screen.dart';

void main() {
  testWidgets('uses the active app theme for donation controls and colors', (tester) async {
    final appTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      cardColor: Color(0xFF121212),
      colorScheme: ColorScheme.dark(
        primary: Colors.white,
        onPrimary: Colors.black,
        onSurface: Colors.white,
      ),
      dividerColor: Color(0x33FFFFFF),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 23),
        titleMedium: TextStyle(color: Colors.white),
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: Colors.white70),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(theme: appTheme, home: DonationScreen()),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, appTheme.scaffoldBackgroundColor);
  });

  testWidgets('shows updated pizza copy and keeps the supporters area reserved', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    expect(find.text('Support Us'), findsOneWidget);
    expect(find.text('Feed our Developers\\n(Pizzaa🍕)'), findsOneWidget);
    expect(find.text('Buy a Pizzaa for Us!🍕'), findsOneWidget);
    expect(find.text('Secure Payment with Stripe'), findsOneWidget);
    expect(find.byKey(const Key('latest-supporters-panel')), findsOneWidget);
    expect(find.text('Currently no one Feeding Us! (TT)'), findsOneWidget);
    final illustration = tester.widget<CachedNetworkImage>(
      find.byKey(const Key('donation-illustration')),
    );
    expect(
      illustration.imageUrl,
      'https://raw.githubusercontent.com/squiraldot/MuziiNap-Official/refs/heads/main/assets/donation_illustration.png',
    );
    expect(find.text('Choose Our Next Meal 🍟'), findsNothing);
    expect(find.text('Leave a Message for These Hungry Humans 💌'), findsNothing);
  });

  testWidgets('removes the retired meal and message form controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));

    expect(find.text('₹29 Choti Fries'), findsNothing);
    expect(find.text('₹59 Cold Drink'), findsNothing);
    expect(find.text('₹99 Burger'), findsNothing);
    expect(find.text('₹199 Full Meal'), findsNothing);
    expect(find.byKey(const Key('custom-donation-amount')), findsNothing);
    expect(find.byKey(const Key('donation-message')), findsNothing);
  });

  testWidgets('Buy a Pizzaa CTA opens the Buy Me a Coffee page', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    String? launchedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launchedUrl = call.arguments['url'] as String?;
      }
      return true;
    });

    await tester.pumpWidget(const MaterialApp(home: DonationScreen()));
    await tester.tap(find.text('Buy a Pizzaa for Us!🍕'));
    await tester.pumpAndSettle();

    expect(launchedUrl, 'https://buymeacoffee.com/realmerrmist');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
