class YouTubeSessionIdentity {
  const YouTubeSessionIdentity({
    required this.delegatedSessionId,
    required this.userSessionId,
    required this.authUser,
  });

  final String? delegatedSessionId;
  final String? userSessionId;
  final String authUser;

  String get accountKey =>
      authUser + ':' + (delegatedSessionId ?? userSessionId ?? 'primary');

  static YouTubeSessionIdentity fromDataSyncId(
    String? dataSyncId, {
    String? authUser,
  }) {
    final raw = dataSyncId?.trim() ?? '';
    String? delegated;
    String? user;

    if (raw.isNotEmpty) {
      final separator = raw.indexOf('||');
      if (separator >= 0) {
        final first = raw.substring(0, separator).trim();
        final second = raw.substring(separator + 2).trim();
        if (second.isNotEmpty) {
          delegated = first.isEmpty ? null : first;
          user = second;
        } else {
          user = first.isEmpty ? null : first;
        }
      } else {
        user = raw;
      }
    }

    final normalizedAuthUser = authUser?.trim();
    return YouTubeSessionIdentity(
      delegatedSessionId: delegated,
      userSessionId: user,
      authUser: normalizedAuthUser?.isNotEmpty == true
          ? normalizedAuthUser!
          : '0',
    );
  }
}


class YouTubeHomeContextSignature {
  static String build({required String language, required String country}) {
    return language.trim().toLowerCase() + '|' + country.trim().toUpperCase();
  }
}
