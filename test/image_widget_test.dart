import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/ui/widgets/image_widget.dart';

void main() {
  testWidgets('shows an artwork fallback while remote song art is loading',
      (tester) async {
    final song = MediaItem(
      id: 'loading-song',
      title: 'Loading song',
      artUri: Uri.parse('https://example.com/loading-song.jpg'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageWidget(song: song, size: 180),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });
}
