import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/audio_cache_manager.dart';

void main() {
  late Directory cacheDirectory;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('muziinap_audio_cache_');
    cacheDirectory = Directory('${root.path}/cachedSongs');
    await cacheDirectory.create(recursive: true);
  });

  tearDown(() async {
    final root = cacheDirectory.parent;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('trims oldest non-queue cache entries until under the byte budget',
      () async {
    final old = File('${cacheDirectory.path}/old-song.mp3');
    final recent = File('${cacheDirectory.path}/recent-song.mp3');
    final queued = File('${cacheDirectory.path}/queued-song.mp3');
    await old.writeAsBytes(List<int>.filled(60, 1));
    await recent.writeAsBytes(List<int>.filled(60, 2));
    await queued.writeAsBytes(List<int>.filled(60, 3));
    final oldTime = DateTime(2024, 1, 1);
    await old.setLastModified(oldTime);
    await recent.setLastModified(DateTime(2025, 1, 1));
    await queued.setLastModified(DateTime(2026, 1, 1));

    final result = await AudioCacheManager.trimDirectory(
      cacheDirectory,
      protectedSongIds: {'queued-song'},
      maxBytes: 120,
    );

    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isTrue);
    expect(await queued.exists(), isTrue);
    expect(result.totalBytes, 120);
    expect(result.withinLimit, isTrue);
  });

  test('removes partial and MIME sidecar files as one cache entry', () async {
    final partial = File('${cacheDirectory.path}/abandoned.mp3.part');
    final mime = File('${cacheDirectory.path}/abandoned.mp3.mime');
    await partial.writeAsBytes(List<int>.filled(80, 1));
    await mime.writeAsBytes(List<int>.filled(20, 2));

    final result = await AudioCacheManager.trimDirectory(
      cacheDirectory,
      protectedSongIds: const {},
      maxBytes: 50,
    );

    expect(await partial.exists(), isFalse);
    expect(await mime.exists(), isFalse);
    expect(result.totalBytes, 0);
  });

  test('reports over-budget when protected queue files alone exceed the cap',
      () async {
    final queued = File('${cacheDirectory.path}/queued.mp3');
    await queued.writeAsBytes(List<int>.filled(150, 1));

    final result = await AudioCacheManager.trimDirectory(
      cacheDirectory,
      protectedSongIds: {'queued'},
      maxBytes: 100,
    );

    expect(await queued.exists(), isTrue);
    expect(result.withinLimit, isFalse);
    expect(result.totalBytes, 150);
  });

  test('does not delete any cache files when already within budget', () async {
    final file = File('${cacheDirectory.path}/song.mp3');
    await file.writeAsBytes(List<int>.filled(20, 1));

    final result = await AudioCacheManager.trimDirectory(
      cacheDirectory,
      protectedSongIds: const {},
      maxBytes: 100,
    );

    expect(await file.exists(), isTrue);
    expect(result.deletedFiles, 0);
    expect(result.withinLimit, isTrue);
  });
}
