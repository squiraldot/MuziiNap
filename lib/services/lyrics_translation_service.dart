import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

/// Line-preserving lyrics translation backed by MyMemory's public endpoint.
/// Original lyric records are never modified by this service.
class LyricsTranslationService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    headers: const {'Accept': 'application/json'},
  ));

  static const timestampPattern = r'\[(?:\d{1,3}:\d{2})(?:\.\d{1,3})?\]';

  static Future<String?> translateLyrics({
    required String songId,
    required String lyrics,
    required String targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    final source = lyrics.trim();
    if (songId.isEmpty || source.isEmpty || source == 'NA' ||
        targetLanguage.isEmpty || targetLanguage == sourceLanguage) return null;

    final cache = await Hive.openBox('lyricsTranslation');
    final cacheKey = '$songId|$sourceLanguage|$targetLanguage';
    try {
      final cached = cache.get(cacheKey);
      if (cached is String && cached.isNotEmpty) return cached;

      final lines = source.split(RegExp(r'\r?\n'));
      final translatedLines = <String>[];
      for (final line in lines) {
        final match = RegExp('^((?:$timestampPattern)+)(.*)\$').firstMatch(line);
        final prefix = match?.group(1) ?? '';
        final text = (match?.group(2) ?? line).trim();
        if (text.isEmpty || text == 'NA') {
          translatedLines.add(line);
          continue;
        }
        final translated = await _translateLine(text, sourceLanguage, targetLanguage);
        if (translated == null || translated.trim().isEmpty) return null;
        translatedLines.add('$prefix$translated');
      }
      final result = translatedLines.join('\n');
      await cache.put(cacheKey, result);
      return result;
    } catch (_) {
      return null;
    } finally {
      if (cache.isOpen) await cache.close();
    }
  }

  static Future<String?> _translateLine(String text, String source, String target) async {
    // MyMemory accepts a maximum of 500 characters per query.
    if (text.length > 480) {
      final pieces = _splitLongLine(text, 450);
      final output = <String>[];
      for (final piece in pieces) {
        final translated = await _translateLine(piece, source, target);
        if (translated == null) return null;
        output.add(translated);
      }
      return output.join(' ');
    }
    try {
      final response = await _dio.get(
        'https://api.mymemory.translated.net/get',
        queryParameters: {'q': text, 'langpair': '$source|$target'},
      );
      if (response.statusCode != 200 || response.data is! Map) return null;
      final data = Map<String, dynamic>.from(response.data as Map);
      final status = data['responseStatus'];
      if (status is num && status != 200) return null;
      final translated = data['responseData'] is Map
          ? (data['responseData']['translatedText']?.toString() ?? '')
          : '';
      if (translated.isEmpty || translated.toLowerCase() == text.toLowerCase()) {
        // Identical output can be a valid translation for names/short words.
        return translated.isEmpty ? null : translated;
      }
      return const HtmlEscape().convert(translated) == translated
          ? translated
          : _decodeBasicEntities(translated);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _splitLongLine(String text, int maxLength) {
    final words = text.split(RegExp(r'\s+'));
    final chunks = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isNotEmpty && current.length + word.length + 1 > maxLength) {
        chunks.add(current);
        current = word;
      } else {
        current = current.isEmpty ? word : '$current $word';
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  static String _decodeBasicEntities(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
