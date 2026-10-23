import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import './music_service.dart';
import '../utils/helper.dart';

class SyncedLyricsService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec, {bool forceReload = false}) async {
    final lyricsBox = await Hive.openBox("lyrics");
    // Check if lyrics available in local database cache
    if (!forceReload && lyricsBox.containsKey(song.id)) {
      final cached = Map<String, dynamic>.from(await lyricsBox.get(song.id));
      if (lyricsBox.isOpen) await lyricsBox.close();
      return cached;
    }

    final cleanTitle = song.title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final cleanArtist = song.artist?.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim() ?? '';
    final dur = song.duration?.inSeconds ?? durInSec;

    Map<String, dynamic>? result;

    // Provider 1: LRCLib API (Exact match)
    result = await _fetchFromLrclibExact(song, cleanTitle, cleanArtist, dur);
    if (result != null) {
      await _cacheAndClose(lyricsBox, song.id, result);
      return result;
    }

    // Provider 2: LRCLib API (Fuzzy search)
    result = await _fetchFromLrclibSearch(cleanTitle, cleanArtist);
    if (result != null) {
      await _cacheAndClose(lyricsBox, song.id, result);
      return result;
    }

    // Provider 3: NetEase Cloud Music API
    result = await _fetchFromNetEase(cleanTitle, cleanArtist);
    if (result != null) {
      await _cacheAndClose(lyricsBox, song.id, result);
      return result;
    }

    // Provider 4: YouTube Music Fallback
    result = await _fetchFromYouTubeMusic(song.id);
    if (result != null) {
      await _cacheAndClose(lyricsBox, song.id, result);
      return result;
    }

    if (lyricsBox.isOpen) await lyricsBox.close();
    return null;
  }

  static Future<void> _cacheAndClose(Box box, String songId, Map<String, dynamic> data) async {
    try {
      await box.put(songId, data);
    } catch (_) {}
    if (box.isOpen) await box.close();
  }

  static Future<Map<String, dynamic>?> _fetchFromLrclibExact(
      MediaItem song, String title, String artist, int dur) async {
    if (dur <= 0 || dur > 3600) return null;
    final getUrl =
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(artist)}&track_name=${Uri.encodeComponent(title)}&album_name=${Uri.encodeComponent(song.album ?? '')}&duration=$dur';
    try {
      final response = (await _dio.get(getUrl)).data;
      if (response != null && (response["syncedLyrics"] != null || response["plainLyrics"] != null)) {
        printINFO("Lyrics Found (LRCLib Exact)");
        return {
          "synced": response["syncedLyrics"] ?? "",
          "plainLyrics": response["plainLyrics"] ?? ""
        };
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromLrclibSearch(
      String title, String artist) async {
    final searchUrl =
        'https://lrclib.net/api/search?q=${Uri.encodeComponent("$title $artist".trim())}';
    try {
      final response = (await _dio.get(searchUrl)).data as List?;
      if (response != null && response.isNotEmpty) {
        final firstMatch = response.first;
        if (firstMatch["syncedLyrics"] != null || firstMatch["plainLyrics"] != null) {
          printINFO("Lyrics Found (LRCLib Search)");
          return {
            "synced": firstMatch["syncedLyrics"] ?? "",
            "plainLyrics": firstMatch["plainLyrics"] ?? ""
          };
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromNetEase(
      String title, String artist) async {
    try {
      final query = "$title $artist".trim();
      final searchUrl =
          'https://music.163.com/api/search/get/web?csrf_token=&hl=m&s=${Uri.encodeComponent(query)}&type=1&offset=0&total=true&limit=1';
      final searchRes = (await _dio.get(searchUrl)).data;
      if (searchRes != null &&
          searchRes["result"] != null &&
          searchRes["result"]["songs"] != null &&
          (searchRes["result"]["songs"] as List).isNotEmpty) {
        final songId = searchRes["result"]["songs"][0]["id"];
        final lyricUrl = 'https://music.163.com/api/song/lyric?id=$songId&lv=-1&kv=-1&tv=-1';
        final lyricRes = (await _dio.get(lyricUrl)).data;
        if (lyricRes != null && lyricRes["lrc"] != null && lyricRes["lrc"]["lyric"] != null) {
          final String lyricStr = lyricRes["lrc"]["lyric"];
          if (lyricStr.trim().isNotEmpty) {
            final isSynced = lyricStr.contains(RegExp(r'\[\d+:\d+\.\d+\]'));
            printINFO("Lyrics Found (NetEase)");
            return {
              "synced": isSynced ? lyricStr : "",
              "plainLyrics": isSynced ? "" : lyricStr
            };
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromYouTubeMusic(String songId) async {
    try {
      if (!Get.isRegistered<MusicServices>()) return null;
      final musicServices = Get.find<MusicServices>();
      final related = await musicServices.getWatchPlaylist(videoId: songId, onlyRelated: true);
      final relatedLyricsId = related['lyrics'];
      if (relatedLyricsId != null) {
        final lyricsText = await musicServices.getLyrics(relatedLyricsId);
        if (lyricsText != null && lyricsText.toString().trim().isNotEmpty) {
          printINFO("Lyrics Found (YouTube Music)");
          return {
            "synced": "",
            "plainLyrics": lyricsText.toString()
          };
        }
      }
    } catch (_) {}
    return null;
  }
}
