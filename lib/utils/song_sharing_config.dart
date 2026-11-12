/// Canonical URL contract for sharing individual MuziiNap songs.
class SongSharingConfig {
  SongSharingConfig._();

  /// Public website origin used by canonical song-sharing links.
  static const String domain = 'muziinap-site.vercel.app';

  /// Canonical route prefix for a shared song.
  static const String routePrefix = '/song/';

  /// A YouTube video ID is exactly 11 ASCII characters from this alphabet.
  /// The ID is case-sensitive and must never be normalized.
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isValidVideoId(String videoId) =>
      _videoIdPattern.hasMatch(videoId);

  /// Builds a canonical URL, rejecting invalid identifiers.
  static String canonicalUrl(String videoId) {
    if (!isValidVideoId(videoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
    }
    return 'https://$domain$routePrefix$videoId';
  }

  /// Extracts a song ID only from URLs matching the shared-link contract.
  /// Returns null for every unsupported or malformed URL.
  static String? parseVideoId(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != domain ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }

    // Only literal ASCII path characters are allowed; never decode path IDs.
    if (uri.toString().contains('%')) return null;

    final segments = uri.path.split('/');
    if (segments.length == 4 &&
        segments[0].isEmpty &&
        segments[1] == 'song' &&
        segments[2].isNotEmpty &&
        segments[3].isEmpty) {
      final videoId = segments[2];
      return isValidVideoId(videoId) ? videoId : null;
    }

    if (segments.length != 3 ||
        segments[0].isNotEmpty ||
        segments[1] != 'song') {
      return null;
    }

    final videoId = segments[2];
    return isValidVideoId(videoId) ? videoId : null;
  }
}
