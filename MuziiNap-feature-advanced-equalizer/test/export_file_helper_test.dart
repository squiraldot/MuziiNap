import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/export_file_helper.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('export_file_helper_');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  group('findAvailableExportFile', () {
    test('returns the base filename when it is unused', () async {
      final file =
          await findAvailableExportFile(tempDirectory, 'My Playlist', 'json');

      expect(file.path, '${tempDirectory.path}/My Playlist.json');
      expect(await file.exists(), isFalse);
    });

    test('uses the next numeric suffix without overwriting existing files',
        () async {
      await File('${tempDirectory.path}/My Playlist.csv')
          .writeAsString('existing');
      await File('${tempDirectory.path}/My Playlist_1.csv')
          .writeAsString('existing');

      final file =
          await findAvailableExportFile(tempDirectory, 'My Playlist', 'csv');

      expect(file.path, '${tempDirectory.path}/My Playlist_2.csv');
      expect(
        await File('${tempDirectory.path}/My Playlist.csv').readAsString(),
        'existing',
      );
      expect(
        await File('${tempDirectory.path}/My Playlist_1.csv').readAsString(),
        'existing',
      );
    });
  });
}
