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
    // Canonical links use literal ASCII only. Reject escapes before Uri can
    // normalize encoded authorities, separators, or dot segments.
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
    final authorityStart = schemeSeparator + 3;
    final pathStart = rawUrl.indexOf('/', authorityStart);
    if (pathStart < 0) return null;

    // Validate the original authority, not only Uri.host. This prevents
    // parser normalization from accepting encoded hosts, non-canonical port
    // spellings, or authority syntax that resolves to the expected host.
    final authority = rawUrl.substring(authorityStart, pathStart);
    final normalizedAuthority = authority.toLowerCase();
    if (authority.contains('@') ||
        (normalizedAuthority != domain &&
            normalizedAuthority != '$domain:443')) {
      return null;
    }

    final rawPath = rawUrl.substring(pathStart);
    final match = RegExp(
      '^' + RegExp.escape(routePrefix) + r'([A-Za-z0-9_-]{11})/?$',
    ).firstMatch(rawPath);
    if (match == null) return null;

    final videoId = match.group(1)!;
    return isValidVideoId(videoId) ? videoId : null;
  }
}
