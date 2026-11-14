import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/quick_picks.dart';
import '../lib/ui/widgets/quickpickswidget.dart';

void main() {
  testWidgets('shows a visible fallback while a Home wide-shelf image loads',
      (tester) async {
    final content = QuickPicks(
      [
        MediaItem(
          id: 'loading-video',
          title: 'Loading video',
          artUri: Uri.parse('https://example.com/loading-video.jpg'),
        ),
      ],
      title: 'Forgotten favorites',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: QuickPicksWidget(content: content),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });
}
