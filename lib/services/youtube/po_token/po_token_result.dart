import 'po_token_request.dart';

class PoTokenResult {
  const PoTokenResult({
    required this.token,
    required this.providerId,
    required this.clientName,
    required this.videoId,
    required this.binding,
    required this.bindingValue,
    required this.purpose,
    required this.expiresAt,
  });

  final String token;
  final String providerId;
  final String clientName;
  final String videoId;
  final PoTokenBinding binding;
  final String bindingValue;
  final PoTokenPurpose purpose;
  final DateTime expiresAt;

  bool isValidFor(PoTokenRequest request, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return token.isNotEmpty &&
        providerId.isNotEmpty &&
        expiresAt.isAfter(currentTime) &&
        clientName == request.clientName &&
        videoId == request.videoId &&
        binding == request.binding &&
        bindingValue == request.bindingValue &&
        purpose == request.purpose;
  }
}

enum PoTokenFailure {
  unavailable,
  unsupported,
  generationFailed,
  invalidBinding,
  expired,
}
