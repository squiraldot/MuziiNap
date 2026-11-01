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

  PoTokenPurpose? purposeRequiredByPlayerReason(Object? reason) {
    if (reason is! String) return null;
    final normalized = reason.toLowerCase();
    if (normalized.contains('potoken') ||
        normalized.contains('po token') ||
        normalized.contains('proof-of-origin') ||
        normalized.contains('proof of origin')) {
      return PoTokenPurpose.player;
    }
    return null;
  }

  bool isGenericHttpForbidden(int? statusCode) =>
      statusCode == 403;
}
