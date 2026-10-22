import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../lib/ui/widgets/standalone_song_info_dialog.dart';

void main() {
  testWidgets('standalone song info dialog renders required metadata',
      (tester) async {
    final song = MediaItem(
      id: 'song-id-123',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      duration: const Duration(minutes: 3),
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    child: StandaloneSongInfoDialog(song: song),
                  ),
                );
              },
              child: const Text('Open Info'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Info'));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsWidgets);
    expect(find.text('Test Album'), findsOneWidget);
    expect(find.text('song-id-123'), findsOneWidget);
    expect(find.text('NA'), findsWidgets);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('close'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone song info dialog tolerates missing optional metadata',
      (tester) async {
    final song = MediaItem(
      id: 'song-without-cache',
      title: 'Song Without Cache',
      artist: null,
      album: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    child: StandaloneSongInfoDialog(song: song),
                  ),
                );
              },
              child: const Text('Open Info'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Info'));
    await tester.pumpAndSettle();

    expect(find.text('Song Without Cache'), findsOneWidget);
    expect(find.text('song-without-cache'), findsOneWidget);
    expect(find.text('NA'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
