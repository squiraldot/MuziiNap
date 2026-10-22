import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';

const String recentlyPlayedKey = 'recently_played_home';
const int recentlyPlayedLimit = 20;

Future<void> saveRecentlyPlayed(MediaItem item) async {
  final box = Hive.box('AppPrefs');
  final current = loadRecentlyPlayed()
      .where((existing) => existing.id != item.id)
      .toList();
  current.insert(0, item);
  final trimmed = current.take(recentlyPlayedLimit).toList();
  await box.put(
    recentlyPlayedKey,
    trimmed.map(MediaItemBuilder.toJson).toList(),
  );
}

List<MediaItem> loadRecentlyPlayed() {
  final box = Hive.box('AppPrefs');
  final raw = box.get(recentlyPlayedKey);
  if (raw is! List) return <MediaItem>[];

  final result = <MediaItem>[];
  final seen = <String>{};
  for (final item in raw) {
    try {
      if (item is! Map) continue;
      final mediaItem = MediaItemBuilder.fromJson(item);
      if (seen.add(mediaItem.id)) {
        result.add(mediaItem);
      }
    } catch (_) {
      // Ignore malformed history entries left by an older app version.
    }
  }
  return result.take(recentlyPlayedLimit).toList();
}

List<MediaItem> mergeRecentlyPlayed(
  List<MediaItem> local,
  List<MediaItem> remote,
) {
  final result = <MediaItem>[];
  final seen = <String>{};

  for (final item in [...local, ...remote]) {
    if (seen.add(item.id)) {
      result.add(item);
    }
    if (result.length >= recentlyPlayedLimit) break;
  }

  return result;
}
