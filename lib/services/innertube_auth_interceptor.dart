import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'innertube_session_manager.dart';

typedef InnerTubeSessionExpiredCallback = Future<bool> Function(
  String? failedCookie,
);

/// Attaches the current YouTube session to InnerTube requests and detects
/// server-side session invalidation.
///
/// The interceptor deliberately handles only HTTPS YouTube InnerTube API
/// requests. It never forwards cookies to arbitrary hosts or unrelated URLs.
class InnerTubeAuthInterceptor extends Interceptor {
  InnerTubeAuthInterceptor({
    required InnerTubeSessionManager sessionManager,
    required Map<String, String> Function() headersProvider,
    required InnerTubeSessionExpiredCallback onSessionExpired,
  })  : _sessionManager = sessionManager,
        _headersProvider = headersProvider,
        _onSessionExpired = onSessionExpired;

  static const String _cookieSnapshotKey = 'innerTubeCookieSnapshot';

  static final StreamController<InnerTubeSessionExpiredEvent>
      _sessionExpiredController =
      StreamController<InnerTubeSessionExpiredEvent>.broadcast();

  static Stream<InnerTubeSessionExpiredEvent> get sessionExpiredEvents =>
      _sessionExpiredController.stream;

  final InnerTubeSessionManager _sessionManager;
  final Map<String, String> Function() _headersProvider;
  final InnerTubeSessionExpiredCallback _onSessionExpired;

  Future<void>? _expiryHandling;
  bool _sessionInvalidated = false;

  /// Call after a successful WebView login to allow a future expiry event.
  void reset() {
    _sessionInvalidated = false;
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (!_isInnerTubeRequest(options.uri)) {
      handler.next(options);
      return;
    }

    final headers = <String, dynamic>{
      ..._headersProvider(),
      ...options.headers,
    };

    try {
      // The session manager reads the latest Hive cookie on every request and
      // creates a fresh SAPISIDHASH rather than reusing a stale authorization.
      final authHeaders =
          _sessionManager.getAuthenticatedHeaders(options.uri.toString());
      headers.addAll(authHeaders);
      options.extra[_cookieSnapshotKey] = authHeaders['cookie'];
    } on InnerTubeSessionException {
      // A missing/expired local session must not leave old in-memory cookies
      // attached to the request. Anonymous InnerTube calls remain supported.
      headers.removeWhere(
        (key, _) => key.toLowerCase() == 'authorization',
      );
      headers['cookie'] = 'CONSENT=YES+1';
      options.extra[_cookieSnapshotKey] = null;
    }

    options.headers
      ..clear()
      ..addAll(headers);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final status = response.statusCode;
    final expiredStatus = status == 401 || status == 403;
    final expiredPayload = _hasExpiredSessionPayload(response.data);

    if (_isInnerTubeRequest(response.requestOptions.uri) &&
        (expiredStatus || expiredPayload)) {
      _invalidateSession(response.requestOptions);
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: expiredStatus
              ? 'YouTube session is no longer authorized.'
              : 'YouTube requires the account to sign in again.',
        ),
      );
      return;
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    final status = err.response?.statusCode;
    if (_isInnerTubeRequest(err.requestOptions.uri) &&
        (status == 401 || status == 403 ||
            _hasExpiredSessionPayload(err.response?.data))) {
      _invalidateSession(err.requestOptions);
    }
    handler.next(err);
  }

  void _invalidateSession(RequestOptions request) {
    final failedCookie = request.extra[_cookieSnapshotKey] as String?;
    // Fire-and-forget here: the response must still be rejected immediately.
    // _invalidateOnce coalesces concurrent failures into one Hive cleanup and
    // one global event.
    unawaited(_invalidateOnce(failedCookie));
  }

  Future<void> _invalidateOnce(String? failedCookie) async {
    // An anonymous 401/403 is not evidence that a stored account session died.
    if (failedCookie == null || failedCookie.isEmpty || _sessionInvalidated) {
      return;
    }
    final active = _expiryHandling;
    if (active != null) {
      await active;
      return;
    }

    _sessionInvalidated = true;
    final handling = () async {
      var invalidated = false;
      try {
        invalidated = await _onSessionExpired(failedCookie);
      } catch (_) {
        // The original Dio failure remains available to its caller. A storage
        // cleanup error must not become an unhandled background exception.
      } finally {
        if (invalidated) {
          _sessionExpiredController.add(
            InnerTubeSessionExpiredEvent(DateTime.now()),
          );
        } else {
          // A late response from a previous account must not log out the
          // currently active account. Permit a later, current-session retry.
          _sessionInvalidated = false;
        }
      }
    }();
    _expiryHandling = handling;
    try {
      await handling;
    } finally {
      _expiryHandling = null;
    }
  }

  static bool _isInnerTubeRequest(Uri uri) {
    const hosts = {
      'music.youtube.com',
      'youtube.com',
      'www.youtube.com',
    };
    return uri.scheme == 'https' &&
        hosts.contains(uri.host.toLowerCase()) &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith('/youtubei/v1/');
  }

  static bool _hasExpiredSessionPayload(dynamic payload) {
    const markers = {'LOGIN_REQUIRED', 'AUTHENTICATION_ERROR'};

    bool inspect(dynamic value) {
      if (value is String) {
        final normalized = value.toUpperCase();
        return markers.any((marker) => normalized.contains(marker));
      }
      if (value is Map) {
        return value.values.any(inspect);
      }
      if (value is Iterable) {
        return value.any(inspect);
      }
      return false;
    }

    if (payload is String) {
      try {
        return inspect(jsonDecode(payload));
      } on FormatException {
        return inspect(payload);
      }
    }
    return inspect(payload);
  }
}

class InnerTubeSessionExpiredEvent {
  const InnerTubeSessionExpiredEvent(this.occurredAt);

  final DateTime occurredAt;
}
