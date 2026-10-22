import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:muziinap/ui/widgets/song_info_dialog.dart';
import 'package:muziinap/ui/widgets/standalone_song_info_dialog.dart';

void main() {
  testWidgets('song info dialog renders without cached stream metadata',
      (tester) async {
    final song = MediaItem(
      id: 'test-song',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      duration: const Duration(minutes: 3),
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => SongInfoDialog(song: song),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('song info content renders inside a modal bottom sheet',
      (tester) async {
    final song = MediaItem(
      id: 'test-song',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => Material(
                    child: SizedBox(
                      height: 500,
                      child: SongInfoContent(song: song),
                    ),
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone info view renders metadata without actions',
      (tester) async {
    final song = MediaItem(
      id: 'standalone-song',
      title: 'Standalone Song',
      artist: 'Standalone Artist',
      album: 'Standalone Album',
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
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

    expect(find.text('Standalone Song'), findsOneWidget);
    expect(find.text('Standalone Artist'), findsWidgets);
    expect(find.text('Standalone Album'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone More view renders all song actions', (tester) async {
    final song = MediaItem(
      id: 'standalone-song',
      title: 'Standalone Song',
      artist: 'Standalone Artist',
      extras: const {
        'artists': [
          {'id': 'artist-id', 'name': 'Standalone Artist'},
        ],
      },
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    child: StandaloneSongInfoDialog(
                      song: song,
                      view: SongInfoDialogView.more,
                    ),
                  ),
                );
              },
              child: const Text('Open More'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open More'));
    await tester.pumpAndSettle();

    // Scroll through the lazy ListView so off-screen action tiles are built
    // before asserting that the standalone More view exposes them.
    final scrollable = find.byType(Scrollable).first;
    for (final label in [
      'Download',
      'Start radio',
      'Add to playlist',
      'Share this song',
      'Copy Link',
      'QR Code',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        250,
        scrollable: scrollable,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Standalone Album'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
