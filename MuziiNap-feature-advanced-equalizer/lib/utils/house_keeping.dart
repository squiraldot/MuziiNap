import 'dart:io';

import 'package:get/get.dart';
import '../models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../services/utils.dart';
import 'helper.dart';

void startHouseKeeping() {
  removeExpiredSongsUrlFromDb();
}

/// Returns true for malformed or expired cached stream entries.
///
/// A cache record is expected to be a list whose second element contains a
/// URL map. Treat incomplete records as stale so one corrupt Hive entry does
/// not abort cleanup for every other entry.
bool shouldRemoveSongUrlCacheEntry(dynamic cacheEntry) {
  if (cacheEntry is! List || cacheEntry.length < 2) return true;

  final streamData = cacheEntry[1];
  if (streamData == null || streamData is String || streamData is! Map) {
    return true;
  }

  final url = streamData['url'];
  if (url is! String || url.isEmpty) return true;
  return isExpired(url: url);
}

Future<void> removeExpiredSongsUrlFromDb() async {
  try {
    final songsUrlCacheBox = Hive.box("SongsUrlCache");
    final songsUrlCacheKeysList =
        songsUrlCacheBox.keys.whereType<String>().toList();
    for (final songUrlKey in songsUrlCacheKeysList) {
      try {
        final cacheEntry = songsUrlCacheBox.get(songUrlKey);
        if (shouldRemoveSongUrlCacheEntry(cacheEntry)) {
          await songsUrlCacheBox.delete(songUrlKey);
        }
      } catch (e) {
        // A malformed entry should be removed without blocking other entries.
        await songsUrlCacheBox.delete(songUrlKey);
        printERROR("Removed invalid song URL cache entry: $e");
      }
    }
  } catch (e) {
    printERROR("Error in removeExpiredSongsUrlFromDb: $e");
  } finally {
    await removeDeletedOfflineSongsFromDb();
  }
}

Future<void> removeDeletedOfflineSongsFromDb() async {
  final supportDir = (await getApplicationSupportDirectory()).path;
  try {
    final songDownloadsBox = Hive.box("SongDownloads");
    final downloadedSongs = songDownloadsBox.values.toList();
    final LibrarySongsController librarySongsController =
        Get.find<LibrarySongsController>();
    for (final downloadedSong in downloadedSongs) {
      if (downloadedSong is! Map) continue;

      final songKey = downloadedSong['videoId'];
      final songUrl = downloadedSong['url'];
      if (songKey is! String || songKey.isEmpty ||
          songUrl is! String || songUrl.isEmpty) {
        if (songKey is String && songKey.isNotEmpty) {
          await songDownloadsBox.delete(songKey);
        }
        continue;
      }

      if (!await File(songUrl).exists()) {
        await songDownloadsBox.delete(songKey);
        final mediaItem = MediaItemBuilder.fromJson(downloadedSong);
        await librarySongsController.removeSong(mediaItem, true);
        final thumbNailPath = "$supportDir/thumbnails/$songKey.png";
        final thumbNailFile = File(thumbNailPath);
        if (await thumbNailFile.exists()) {
          await thumbNailFile.delete();
        }
      }
    }
  } catch (e) {
    printERROR("Error in removeDeletedOfflineSongsFromDb: $e");
  }
}
