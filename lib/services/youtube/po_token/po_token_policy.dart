import 'po_token_request.dart';

/// Interprets explicit upstream requirements only; it is deliberately not a
/// client-name policy table. HTTP 403 by itself is never proof of a PO failure.
class PoTokenPolicy {
  const PoTokenPolicy();

  /// Attaches a Player token only at YouTube's documented request-body field.
  Map<String, dynamic> attachPlayerToken(
    Map<String, dynamic> body,
    String? token,
  ) {
    if (token == null || token.isEmpty) return body;
    return {
      ...body,
      'serviceIntegrityDimensions': {'poToken': token},
    };
  }

  /// Adds a GVS token only to direct Google Video Server media URLs.
  /// SABR carries attestation in its protobuf payload and is not rewritten here.
  String attachGvsTokenToUrl(String rawUrl, String? token) {
    if (token == null || token.isEmpty) return rawUrl;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !(uri.host == 'googlevideo.com' ||
            uri.host.endsWith('.googlevideo.com')) ||
        uri.queryParameters['sabr'] == '1') {
      return rawUrl;
    }
    final query = <String, dynamic>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: entry.value,
      'pot': token,
    };
    return uri.replace(queryParameters: query).toString();
  }

  List<dynamic> attachGvsTokenToFormats(
    List<dynamic> formats,
    String? token,
  ) {
    if (token == null || token.isEmpty) return formats;
    return formats.map((item) {
      if (item is! Map) return item;
      final rawUrl = item['url']?.toString();
      if (rawUrl == null) return item;
      final tokenizedUrl = attachGvsTokenToUrl(rawUrl, token);
      return tokenizedUrl == rawUrl
          ? item
          : <String, dynamic>{...item, 'url': tokenizedUrl};
    }).toList(growable: false);
  }

  /// GVS Web PO Tokens are bound to the visitor when logged out, or to the
  /// account session when signed in. They are never video-ID-bound.
  PoTokenBinding? gvsBindingForSession({
    required String visitorData,
    String? sessionId,
  }) {
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      return PoTokenBinding.session;
    }
    return visitorData.trim().isNotEmpty ? PoTokenBinding.visitor : null;
  }

  /// Extracts the account-bound session identifier documented by yt-dlp.
  String? extractSessionId(Map response) {
    final responseContext = response['responseContext'];
    if (responseContext is! Map) return null;
    final appContext = responseContext['mainAppWebResponseContext'];
    if (appContext is! Map) return null;
    final dataSyncId = appContext['dataSyncId']?.toString().trim();
    if (dataSyncId == null || dataSyncId.isEmpty) return null;
    final sessionId = dataSyncId.split('||').first.trim();
    return sessionId.isEmpty ? null : sessionId;
  }

  PoTokenPurpose? purposeRequiredByPlayerReason(Object? reason) {
    if (reason is! String) return null;
    // Upstream errors appear in both human-readable and enum-like forms.
    // Normalize separators before matching, but keep the match explicit so
    // generic forbidden responses never trigger token generation.
    final normalized = reason
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.contains('po token') ||
        normalized.contains('potoken') ||
        normalized.contains('proof of origin')) {
      return PoTokenPurpose.player;
    }
    return null;
  }

  bool isGenericHttpForbidden(int? statusCode) =>
      statusCode == 403;
}
