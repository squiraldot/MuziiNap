import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import './music_service.dart';
import '../utils/helper.dart';

class SyncedLyricsService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    sendTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {
      'Accept': 'application/json',
      'User-Agent': 'MuziiNap (https://github.com/squiraldot/MuziiNap)',
    },
  ));

  static final RegExp _timestampPattern =
      RegExp(r'\[\d{1,3}:\d{2}(?:\.\d{1,3})?\]');

  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec, {bool forceReload = false}) async {
    final lyricsBox = await Hive.openBox("lyrics");
    try {
      Map<String, dynamic>? cached;
      if (lyricsBox.containsKey(song.id)) {
        final value = lyricsBox.get(song.id);
        if (value is Map) {
          final cachedSynced = _clean(value["synced"]);
          final cachedPlain = _clean(value["plainLyrics"]);
          cached = {
            "synced": cachedSynced,
            // Older cache entries may have synced lyrics but no separate
            // plainLyrics field. Derive plain text so Plain mode still works.
            "plainLyrics": cachedPlain.isNotEmpty
                ? cachedPlain
                : _stripTimestamps(cachedSynced),
          };
        }
      }

      // Plain-only cache must not hide synced lyrics that are now available.
      if (!forceReload && cached != null && _hasSynced(cached["synced"])) {
        return cached;
      }

      final title = _cleanMetadata(song.title);
      final artist = _cleanMetadata(song.artist ?? "");
      final album = _cleanMetadata(song.album ?? "");
      final duration = _resolveDuration(song, durInSec);
      if (title.isEmpty) return cached;

      // Keep a plain exact match temporarily while searching for timed lyrics.
      Map<String, dynamic>? plainCandidate;
      final exact = await _fetchFromLrclibExact(
        title: title, artist: artist, album: album, duration: duration,
      );
      if (exact != null) {
        if (_hasSynced(exact["synced"])) {
          return await _cacheAndClose(lyricsBox, song.id, exact);
        }
        plainCandidate = exact;
      }

      final searched = await _fetchFromLrclibSearch(
        title: title, artist: artist, album: album, duration: duration,
      );
      if (searched != null) {
        if (_hasSynced(searched["synced"])) {
          return await _cacheAndClose(lyricsBox, song.id, searched);
        }
        plainCandidate ??= searched;
      }

      // A plain-text LRCLIB result is only a last resort. Keep checking
      // providers that can supply time-aligned lyrics before accepting it.
      final netEase = await _fetchFromNetEase(title, artist);
      if (netEase != null && _hasSynced(netEase["synced"])) {
        return await _cacheAndClose(lyricsBox, song.id, netEase);
      }
      final youtube = await _fetchFromYouTubeMusic(song.id);
      if (youtube != null && _hasSynced(youtube["synced"])) {
        return await _cacheAndClose(lyricsBox, song.id, youtube);
      }

      // Never downgrade a previously cached timed transcript to plain-only
      // results just because a provider temporarily returned a weaker match.
      if (cached != null && _hasSynced(cached["synced"])) {
        final refreshedPlain = _clean(plainCandidate?["plainLyrics"]).isNotEmpty
            ? _clean(plainCandidate?["plainLyrics"])
            : _clean(netEase?["plainLyrics"]).isNotEmpty
                ? _clean(netEase?["plainLyrics"])
                : _clean(youtube?["plainLyrics"]);
        final preserved = <String, dynamic>{
          "synced": cached["synced"],
          "plainLyrics": refreshedPlain.isNotEmpty
              ? refreshedPlain
              : cached["plainLyrics"],
        };
        return await _cacheAndClose(lyricsBox, song.id, preserved);
      }

      if (plainCandidate != null) {
        return await _cacheAndClose(lyricsBox, song.id, plainCandidate);
      }
      if (netEase != null) return await _cacheAndClose(lyricsBox, song.id, netEase);
      if (youtube != null) return await _cacheAndClose(lyricsBox, song.id, youtube);
      return cached;
    } catch (error) {
      printINFO("Lyrics lookup failed: " + error.toString());
      return null;
    } finally {
      if (lyricsBox.isOpen) await lyricsBox.close();
    }
  }

  static Future<Map<String, dynamic>> _cacheAndClose(
      Box box, String songId, Map<String, dynamic> data) async {
    final normalized = <String, dynamic>{
      "synced": _clean(data["synced"]),
      "plainLyrics": _clean(data["plainLyrics"]),
    };
    if (normalized["plainLyrics"].toString().isEmpty &&
        _hasSynced(normalized["synced"])) {
      normalized["plainLyrics"] = _stripTimestamps(normalized["synced"]);
    }
    try {
      await box.put(songId, normalized);
    } catch (_) {}
    return normalized;
  }

  static Future<Map<String, dynamic>?> _fetchFromLrclibExact({
    required String title,
    required String artist,
    required String album,
    required int duration,
  }) async {
    if (artist.isEmpty || duration <= 0 || duration > 3600) return null;
    try {
      final response = await _dio.get(
        "https://lrclib.net/api/get",
        queryParameters: {
          "track_name": title,
          "artist_name": artist,
          if (album.isNotEmpty) "album_name": album,
          "duration": duration,
        },
      );
      if (response.statusCode != 200 || response.data is! Map) return null;
      final result = _normalizeLrclibRecord(response.data);
      if (result != null) printINFO("Lyrics found (LRCLIB exact)");
      return result;
    } on DioException catch (error) {
      printINFO("LRCLIB exact lookup failed: " + error.toString());
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchFromLrclibSearch({
    required String title,
    required String artist,
    required String album,
    required int duration,
  }) async {
    // Do not require exact artist/album filters for discovery: metadata from
    // media providers often differs from LRCLIB even for the same recording.
    // Search progressively broader queries and rank all results locally.
    final queries = <Map<String, String>>[
      {"track_name": title},
      if (artist.isNotEmpty) {"q": "$title $artist"},
      {"q": title},
    ];
    final seen = <String>{};
    final candidates = <Map<String, dynamic>>[];

    for (final query in queries) {
      try {
        final response = await _dio.get(
          "https://lrclib.net/api/search",
          queryParameters: query,
        );
        if (response.statusCode != 200 || response.data is! List) continue;
        for (final record in (response.data as List).whereType<Map>()) {
          final candidate = Map<String, dynamic>.from(record);
          final id = candidate["id"]?.toString();
          final key = id ?? [
            candidate["trackName"], candidate["artistName"],
            candidate["albumName"], candidate["duration"],
          ].join("|");
          if (seen.add(key) && _normalizeLrclibRecord(candidate) != null) {
            candidates.add(candidate);
          }
        }
      } on DioException catch (error) {
        printINFO("LRCLIB search failed for $query: $error");
      } catch (error) {
        printINFO("LRCLIB search response failed: $error");
      }
      // If this query already returned a strong synced match, avoid further
      // requests and respect LRCLIB's sequential-request guidance.
      final strongSynced = candidates.any((candidate) =>
          _hasSynced(candidate["syncedLyrics"]) &&
          _lrclibScore(candidate, title: title, artist: artist,
              album: album, duration: duration) >= 80);
      if (strongSynced) break;
    }

    candidates.sort((a, b) => _lrclibScore(
      b, title: title, artist: artist, album: album, duration: duration,
    ).compareTo(_lrclibScore(
      a, title: title, artist: artist, album: album, duration: duration,
    )));

    Map<String, dynamic>? plainCandidate;
    for (final candidate in candidates) {
      if (_lrclibScore(
        candidate, title: title, artist: artist, album: album, duration: duration,
      ) < 80) continue;
      final normalized = _normalizeLrclibRecord(candidate);
      if (normalized == null) continue;
      if (_hasSynced(normalized["synced"])) {
        printINFO("Synced lyrics found (LRCLIB search)");
        return normalized;
      }
      plainCandidate ??= normalized;
    }
    if (plainCandidate != null) {
      printINFO("Plain lyrics found (LRCLIB search; no synced candidate matched)");
      return plainCandidate;
    }
    return null;
  }

  static Map<String, dynamic>? _normalizeLrclibRecord(dynamic record) {
    if (record is! Map || record["instrumental"] == true) return null;
    final synced = _clean(record["syncedLyrics"]);
    final plain = _clean(record["plainLyrics"]);
    if (synced.isEmpty && plain.isEmpty) return null;
    return <String, dynamic>{
      "synced": synced,
      "plainLyrics": plain.isNotEmpty ? plain : _stripTimestamps(synced),
    };
  }

  static int _lrclibScore(
    Map<String, dynamic> record, {
    required String title,
    required String artist,
    required String album,
    required int duration,
  }) {
    final targetTitle = _normalizeForMatch(title);
    final targetArtist = _normalizeForMatch(artist);
    final targetAlbum = _normalizeForMatch(album);
    final candidateTitle = _normalizeForMatch(
      record["trackName"]?.toString() ?? record["name"]?.toString() ?? "",
    );
    final candidateArtist = _normalizeForMatch(record["artistName"]?.toString() ?? "");
    final candidateAlbum = _normalizeForMatch(record["albumName"]?.toString() ?? "");
    var score = 0;
    if (candidateTitle == targetTitle) score += 100;
    else if (candidateTitle.isNotEmpty &&
        (candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle))) score += 55;
    if (targetArtist.isNotEmpty && candidateArtist == targetArtist) score += 80;
    else if (targetArtist.isNotEmpty && candidateArtist.isNotEmpty &&
        (candidateArtist.contains(targetArtist) || targetArtist.contains(candidateArtist))) score += 45;
    if (targetAlbum.isNotEmpty && candidateAlbum == targetAlbum) score += 20;

    final candidateDuration = (record["duration"] as num?)?.round() ?? 0;
    if (duration > 0 && candidateDuration > 0) {
      final difference = (candidateDuration - duration).abs();
      if (difference <= 2) score += 40;
      else if (difference <= 5) score += 20;
      else if (difference > 15) score -= 50;
    }
    if (_hasSynced(record["syncedLyrics"])) score += 10;
    return score;
  }

  static String _clean(dynamic value) {
    if (value == null) return "";
    final text = value.toString().trim();
    return text.toLowerCase() == "null" ? "" : text;
  }

  static bool _hasSynced(dynamic value) {
    final lyrics = _clean(value);
    return lyrics.isNotEmpty && _timestampPattern.hasMatch(lyrics);
  }

  static int _resolveDuration(MediaItem song, int fallbackSeconds) {
    final mediaSeconds = song.duration?.inSeconds ?? 0;
    final seconds = mediaSeconds > 0 ? mediaSeconds : fallbackSeconds;
    return seconds > 0 && seconds <= 3600 ? seconds : 0;
  }

  static String _cleanMetadata(String value) => value
      .replaceAll(RegExp(r"\s*\([^)]*\)|\s*\[[^\]]*\]|\s*\{[^}]*\}"), " ")
      .replaceAll(RegExp(r"\b(feat\.?|ft\.?)\b.*$", caseSensitive: false), "")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();

  static String _normalizeForMatch(String value) => _cleanMetadata(value)
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();

  static String _stripTimestamps(String lyrics) => lyrics
      .replaceAll(_timestampPattern, "")
      .replaceAll(RegExp(r"\[(ar|ti|al|by|re|ve|length|offset):[^\]]*\]", caseSensitive: false), "")
      .split("\n")
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join("\n")
      .trim();

  static Future<Map<String, dynamic>?> _fetchFromNetEase(
      String title, String artist) async {
    try {
      final query = "$title $artist".trim();
      final searchUrl =
          'https://music.163.com/api/search/get/web?csrf_token=&hl=m&s=${Uri.encodeComponent(query)}&type=1&offset=0&total=true&limit=10';
      final searchRes = (await _dio.get(searchUrl)).data;
      final searchResult = searchRes is Map ? searchRes["result"] : null;
      final songs = searchResult is Map ? searchResult["songs"] : null;
      if (songs is List) {
        Map<String, dynamic>? plainCandidate;
        for (final song in songs) {
          if (song is! Map || song["id"] == null) continue;
          final songId = song["id"];
          final lyricUrl =
              'https://music.163.com/api/song/lyric?id=$songId&lv=-1&kv=-1&tv=-1';
          final lyricRes = (await _dio.get(lyricUrl)).data;
          final lrc = lyricRes is Map ? lyricRes["lrc"] : null;
          final lyricValue = lrc is Map ? lrc["lyric"] : null;
          final lyricStr = lyricValue?.toString() ?? "";
          if (lyricStr.trim().isEmpty) continue;

          // LRC permits timestamps with or without fractional seconds.
          final isSynced = _hasSynced(lyricStr);
          final candidate = <String, dynamic>{
            "synced": isSynced ? lyricStr : "",
            "plainLyrics": isSynced ? _stripTimestamps(lyricStr) : lyricStr,
          };
          if (isSynced) {
            printINFO("Synced lyrics found (NetEase)");
            return candidate;
          }
          plainCandidate ??= candidate;
        }
        if (plainCandidate != null) {
          printINFO("Plain lyrics found (NetEase)");
          return plainCandidate;
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
