import 'package:dio/dio.dart';

import 'po_token_provider.dart';
import 'po_token_request.dart';
import 'po_token_result.dart';

/// Adapter for a BgUtils HTTP server, either loopback-hosted or remote HTTPS.
///
/// BgUtils performs Web/BotGuard attestation. It is not an Android DroidGuard
/// or iOSGuard implementation, so this adapter only accepts the app's
/// WEB_REMIX (YouTube Music Web) identity. SABR's protobuf token transport is
/// intentionally unsupported by this HTTP adapter.
class BgutilHttpPoTokenProvider implements PoTokenProvider {
  BgutilHttpPoTokenProvider({
    required String baseUrl,
    Dio? dio,
    this.timeout = const Duration(seconds: 15),
  })  : _baseUri = _validateBaseUrl(baseUrl),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: timeout,
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ));

  final Uri _baseUri;
  final Dio _dio;
  final Duration timeout;

  static Uri _validateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final localHttp = uri != null &&
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1');
    if (uri == null ||
        (uri.scheme != 'https' && !localHttp) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'Expected HTTPS provider URL');
    }
    return uri;
  }

  @override
  String get id => 'bgutil-web-botguard';

  @override
  bool supports(PoTokenRequest request) {
    if (request.clientName != 'WEB_REMIX' ||
        (request.purpose != PoTokenPurpose.player &&
            request.purpose != PoTokenPurpose.gvs)) {
      return false;
    }
    // Web GVS tokens are session-bound (visitor ID or account session ID).
    // A video-ID binding is valid for some Player contexts, not GVS.
    if (request.purpose == PoTokenPurpose.gvs &&
        request.binding == PoTokenBinding.video) {
      return false;
    }
    return request.bindingValue != null;
  }

  @override
  Future<PoTokenResult?> getToken(PoTokenRequest request) async {
    if (!supports(request)) return null;
    final response = await _dio.postUri<Map<String, dynamic>>(
      _baseUri.replace(
        path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}/get_pot',
      ),
      data: {
        'content_binding': request.bindingValue,
        'innertube_context': request.innertubeContext,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );
    final data = response.data;
    if (data == null) return null;

    final token = data['poToken'];
    final returnedBinding = data['contentBinding'];
    final expiryValue = data['expiresAt'];
    final expiry = expiryValue is String
        ? DateTime.tryParse(expiryValue)
        : expiryValue is num
            ? DateTime.fromMillisecondsSinceEpoch(
                expiryValue.toInt(),
                isUtc: true,
              )
            : null;
    if (token is! String ||
        token.isEmpty ||
        returnedBinding != request.bindingValue ||
        expiry == null) {
      return null;
    }

    return PoTokenResult(
      token: token,
      providerId: id,
      clientName: request.clientName,
      clientVersion: request.clientVersion,
      videoId: request.videoId,
      visitorData: request.visitorData,
      sessionId: request.sessionId,
      binding: request.binding,
      bindingValue: request.bindingValue!,
      purpose: request.purpose,
      expiresAt: expiry,
    );
  }
}
