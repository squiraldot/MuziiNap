import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import 'constant.dart';

/// Builds authenticated headers for YouTube Music WEB_REMIX requests.
///
/// Cookies are stored in the app's existing Hive preferences box to preserve
/// compatibility with the current multi-account login flow. Hive boxes opened
/// without an encryption cipher are not encrypted at rest; applications that
/// require OS-keystore-backed encryption should inject a secure storage
/// adapter rather than treating this local persistence as encrypted.
class InnerTubeSessionManager {
  InnerTubeSessionManager({Box<dynamic>? box})
      : _box = box ?? Hive.box(appPrefsBoxName);

  static const String _cookieKey = 'yt_cookies';
  static const String _expiryKey = 'yt_cookie_expires_at';
  static const String _clientVersion = '1.20260707.12.00';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';
  static const Set<String> _allowedHosts = {
    'music.youtube.com',
    'youtube.com',
    'www.youtube.com',
  };

  final Box<dynamic> _box;

  /// Saves a normalized Cookie header. [expiresAt] is optional because
  /// WebView's Cookie objects do not expose the original Set-Cookie expiry.
  Future<void> storeCookies(
    String cookies, {
    DateTime? expiresAt,
  }) async {
    final normalized = cookies.trim();
    if (normalized.isEmpty) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.emptyCookie,
        'Cookie header is empty.',
      );
    }
    if (normalized.contains('\r') || normalized.contains('\n')) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.invalidCookie,
        'Cookie header contains invalid line breaks.',
      );
    }

    final parsed = _parseCookies(normalized);
    if (parsed.isEmpty) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.invalidCookie,
        'Cookie header does not contain valid cookie pairs.',
      );
    }
    if (_findSapisid(parsed) == null) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.missingSapisid,
        'The YouTube session is missing a SAPISID cookie.',
      );
    }
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.expired,
        'The supplied YouTube session expiry is in the past.',
      );
    }

    await _box.put(_cookieKey, normalized);
    if (expiresAt == null) {
      await _box.delete(_expiryKey);
    } else {
      await _box.put(_expiryKey, expiresAt.millisecondsSinceEpoch);
    }
  }

  /// Replaces the stored Cookie header. Kept as an explicit alias for callers
  /// that describe session refreshes as updates.
  Future<void> updateCookies(
    String cookies, {
    DateTime? expiresAt,
  }) =>
      storeCookies(cookies, expiresAt: expiresAt);

  Future<void> clearCookies() async {
    await _box.delete(_cookieKey);
    await _box.delete(_expiryKey);
  }

  /// Returns WEB_REMIX headers and a fresh SAPISIDHASH for [url].
  ///
  /// Only HTTPS YouTube origins are accepted, preventing a caller from
  /// forwarding the account cookie or authorization hash to an arbitrary host.
  Map<String, String> getAuthenticatedHeaders(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        !_allowedHosts.contains(uri.host.toLowerCase()) ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.untrustedOrigin,
        'Authenticated headers are restricted to HTTPS YouTube origins.',
      );
    }

    final expiry = _box.get(_expiryKey);
    if (expiry is int &&
        expiry <= DateTime.now().millisecondsSinceEpoch) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.expired,
        'The stored YouTube session has expired.',
      );
    }

    final cookies = _box.get(_cookieKey);
    if (cookies is! String || cookies.trim().isEmpty) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.missingCookie,
        'No YouTube session cookie is stored.',
      );
    }

    final parsed = _parseCookies(cookies);
    final sapisid = _findSapisid(parsed);
    if (sapisid == null || sapisid.isEmpty) {
      throw const InnerTubeSessionException(
        InnerTubeSessionError.missingSapisid,
        'The stored YouTube session has no SAPISID cookie.',
      );
    }

    final origin = uri.origin;
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final authorizationParts = <String>[
      _hashAuthorization('SAPISIDHASH', timestamp, sapisid, origin),
    ];

    final secureCookieHashes = <String, String>{
      'SAPISID1PHASH': '__Secure-1PAPISID',
      'SAPISID3PHASH': '__Secure-3PAPISID',
    };
    for (final entry in secureCookieHashes.entries) {
      final value = parsed[entry.value];
      if (value != null && value.isNotEmpty) {
        authorizationParts.add(
          _hashAuthorization(entry.key, timestamp, value, origin),
        );
      }
    }

    return {
      'content-type': 'application/json',
      'user-agent': _userAgent,
      'origin': origin,
      'x-origin': origin,
      'x-youtube-client-name': '67',
      'x-youtube-client-version': _clientVersion,
      'accept': '*/*',
      'accept-encoding': 'gzip, deflate',
      'cookie': cookies,
      'authorization': authorizationParts.join(' '),
    };
  }

  static String _hashAuthorization(
    String scheme,
    int timestamp,
    String secret,
    String origin,
  ) {
    final digest = sha1
        .convert(utf8.encode('$timestamp $secret $origin'))
        .toString();
    return '$scheme ${timestamp}_$digest';
  }

  static Map<String, String> _parseCookies(String rawCookies) {
    final result = <String, String>{};
    for (final part in rawCookies.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      result[name] = value;
    }
    return result;
  }

  static String? _findSapisid(Map<String, String> cookies) {
    for (final name in const [
      'SAPISID',
      '__Secure-3PAPISID',
      '__Secure-1PAPISID',
    ]) {
      final value = cookies[name];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

enum InnerTubeSessionError {
  emptyCookie,
  invalidCookie,
  missingCookie,
  missingSapisid,
  expired,
  untrustedOrigin,
}

class InnerTubeSessionException implements Exception {
  const InnerTubeSessionException(this.code, this.message);

  final InnerTubeSessionError code;
  final String message;

  @override
  String toString() => 'InnerTubeSessionException(${code.name}): $message';
}
