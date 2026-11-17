import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/supporters_api_service.dart';
import '../lib/ui/screens/Settings/donation_screen.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.status, this.body);
  final int status;
  final String body;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['application/json']});
  @override
  void close({bool force = false}) {}
}
SupportersApiService _service(int status, String body) {
  final dio = Dio()..httpClientAdapter = _ResponseAdapter(status, body);
  return SupportersApiService(dio: dio);
}

void main() {
  testWidgets('uses active app theme', (tester) async {
    final theme = ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(primary: Colors.white, onPrimary: Colors.black, onSurface: Colors.white));
    await tester.pumpWidget(MaterialApp(theme: theme,
      home: DonationScreen(supportersService: _service(503, '{}'))));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, theme.scaffoldBackgroundColor);
  });

  testWidgets('preserves donation design and displays 503 as unavailable', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DonationScreen(supportersService: _service(503, '{}'))));
    await tester.pumpAndSettle();
    expect(find.text('Support Us'), findsOneWidget);
    expect(find.text('Feed our Developers\n(Pizzaa🍕)'), findsOneWidget);
    expect(find.text('Buy a Pizzaa for Us!🍕'), findsOneWidget);
    expect(find.text('Secure Payment with Stripe'), findsOneWidget);
    expect(find.byKey(const Key('latest-supporters-panel')), findsNothing);
    expect(find.text('Currently no one Feeding Us! (TT)'), findsNothing);
    final image = tester.widget<CachedNetworkImage>(find.byKey(const Key('donation-illustration')));
    expect(image.imageUrl, 'https://raw.githubusercontent.com/squiraldot/MuziiNap-Official/refs/heads/main/assets/donation_illustration.png');
  });

  testWidgets('renders live supporter fields', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DonationScreen(supportersService: _service(200,
      '{"total":1,"supporters":[{"name":"Alex","message":"Keep up the music!","amount":15,"currency":"USD","supported_at":"2026-11-15T10:00:00.000Z"}]}'))));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('“Keep up the music!”'), findsOneWidget);
    expect(find.textContaining('USD 15'), findsOneWidget);
    expect(find.byKey(const Key('latest-supporters-panel')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('supporters-heading'))).textAlign,
        TextAlign.center);
    final panel = tester.getRect(find.byKey(const Key('latest-supporters-panel')));
    final heading = tester.getRect(find.byKey(const Key('supporters-heading')));
    expect(heading.center.dx, closeTo(panel.center.dx, 1));
  });

  testWidgets('shows empty state only for valid empty response', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DonationScreen(supportersService: _service(200, '{"total":0,"supporters":[]}'))));
    await tester.pumpAndSettle();
    expect(find.text('No pizza heroes yet!'), findsNothing);
    expect(find.byKey(const Key('latest-supporters-panel')), findsNothing);
  });


  testWidgets('CTA still opens Buy Me a Coffee', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    String? launched;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launched = call.arguments['url'] as String?;
      return true;
    });
    await tester.pumpWidget(MaterialApp(home: DonationScreen(supportersService: _service(503, '{}'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy a Pizzaa for Us!🍕'));
    await tester.pumpAndSettle();
    expect(launched, 'https://buymeacoffee.com/realmerrmist');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}