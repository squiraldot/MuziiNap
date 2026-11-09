import 'po_token_request.dart';
import 'po_token_result.dart';

abstract interface class PoTokenProvider {
  String get id;

  bool supports(PoTokenRequest request);

  Future<PoTokenResult?> getToken(PoTokenRequest request);
}

/// Safe default: absence of a real attestation implementation is explicit.
class UnavailablePoTokenProvider implements PoTokenProvider {
  const UnavailablePoTokenProvider();

  @override
  String get id => 'unavailable';

  @override
  bool supports(PoTokenRequest request) => false;

  @override
  Future<PoTokenResult?> getToken(PoTokenRequest request) async => null;
}
