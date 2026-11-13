/// Canonical URL contract for sharing individual MuziiNap songs.
class SongSharingConfig {
  SongSharingConfig._();

  static const String domain = 'muziinap-site.vercel.app';
  static const String routePrefix = '/song/';
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isValidVideoId(String videoId) =>
      _videoIdPattern.hasMatch(videoId);

  static String canonicalUrl(String videoId) {
    if (!isValidVideoId(videoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
    }
    return 'https://$domain$routePrefix$videoId';
  }

  /// Parses original Android Intent.dataString text before Uri normalization.
  static String? parseVideoId(String rawUrl) {
    if (rawUrl.contains('%') || rawUrl.contains('?') || rawUrl.contains('#')) {
      return null;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != domain ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }

    final schemeSeparator = rawUrl.indexOf('://');
    if (schemeSeparator < 0) return null;
    final pathStart = rawUrl.indexOf('/', schemeSeparator + 3);
    if (pathStart < 0) return null;
    final authority = rawUrl.substring(schemeSeparator + 3, pathStart);
    if (authority.contains('@')) return null;
    final rawPath = rawUrl.substring(pathStart);
    final match = RegExp(r'^/song/([A-Za-z0-9_-]{11})/?$')
        .firstMatch(rawPath);
    if (match == null) return null;

    final videoId = match.group(1)!;
    return isValidVideoId(videoId) ? videoId : null;
  }
}
