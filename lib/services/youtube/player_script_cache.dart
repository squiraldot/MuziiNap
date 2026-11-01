import 'dart:collection';

import 'package:dio/dio.dart';

class CachedPlayerScript {
  final String playerId;
  final Uri url;
  final String source;

  const CachedPlayerScript({
    required this.playerId,
    required this.url,
    required this.source,
  });
}

/// Bounded, version-aware player script cache with in-flight request sharing.
class PlayerScriptCache {
  PlayerScriptCache({
    Dio? dio,
    Future<String> Function(Uri url)? fetcher,
    this.maxEntries = 4,
    this.timeout = const Duration(seconds: 8),
  })  : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        )),
        _fetcher = fetcher;

  final Dio _dio;
  final Future<String> Function(Uri url)? _fetcher;
  final int maxEntries;
  final Duration timeout;

  final LinkedHashMap<String, CachedPlayerScript> _cache =
      LinkedHashMap<String, CachedPlayerScript>();
  final Map<String, Future<CachedPlayerScript>> _pending = {};

  static String playerIdFor(Uri url) {
    final match = RegExp(r'/s/player/([^/]+)/').firstMatch(url.path);
    if (match != null) return match.group(1)!;
    return url.pathSegments.isEmpty ? url.host : url.pathSegments.last;
  }

  Future<CachedPlayerScript> get(Uri url) async {
    if (url.scheme != 'https' ||
        (url.host != 'youtube.com' &&
            url.host != 'www.youtube.com' &&
            url.host != 'youtube-nocookie.com' &&
            url.host != 'www.youtube-nocookie.com')) {
      throw const FormatException('Untrusted YouTube player script URL');
    }

    final playerId = playerIdFor(url);
    final key = '$playerId|' + url.toString();
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final existing = _pending[key];
    if (existing != null) return existing;

    final request = _download(url, playerId);
    _pending[key] = request;
    try {
      final result = await request;
      _cache[key] = result;
      while (_cache.length > maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  Future<CachedPlayerScript> _download(Uri url, String playerId) async {
    final source = await (_fetcher?.call(url) ?? _fetchWithDio(url))
        .timeout(timeout);
    final trimmed = source.trim();
    if (trimmed.length < 32 ||
        (!trimmed.contains('function') && !trimmed.contains('=>'))) {
      throw const FormatException('Invalid YouTube player JavaScript');
    }
    return CachedPlayerScript(playerId: playerId, url: url, source: source);
  }

  Future<String> _fetchWithDio(Uri url) async {
    final response = await _dio.get<String>(
      url.toString(),
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        headers: const {'Accept': '*/*'},
      ),
    );
    if (response.statusCode != 200 || response.data == null) {
      throw const FormatException('Unable to download YouTube player script');
    }
    return response.data!;
  }

  void clear() => _cache.clear();

  int get cachedScriptCount => _cache.length;
}
