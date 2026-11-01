import 'po_token_request.dart';

/// Interprets explicit upstream requirements only; it is deliberately not a
/// client-name policy table. HTTP 403 by itself is never proof of a PO failure.
class PoTokenPolicy {
  const PoTokenPolicy();

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
