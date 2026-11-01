enum PoTokenPurpose { player, gvs, sabr }

enum PoTokenBinding { video, visitor, session }

/// Describes one narrowly-scoped YouTube attestation request.
class PoTokenRequest {
  const PoTokenRequest({
    required this.clientName,
    required this.clientVersion,
    required this.videoId,
    required this.visitorData,
    required this.purpose,
    required this.binding,
    this.sessionId,
    this.userAgent,
  });

  final String clientName;
  final String clientVersion;
  final String videoId;
  final String visitorData;
  final String? sessionId;
  final PoTokenPurpose purpose;
  final PoTokenBinding binding;
  final String? userAgent;

  String? get bindingValue {
    switch (binding) {
      case PoTokenBinding.video:
        return videoId.isEmpty ? null : videoId;
      case PoTokenBinding.visitor:
        return visitorData.isEmpty ? null : visitorData;
      case PoTokenBinding.session:
        return sessionId?.isNotEmpty == true ? sessionId : null;
    }
  }

  /// Stable, non-secret cache identity. Never includes a token value.
  String get cacheKey => [
        clientName,
        clientVersion,
        purpose.name,
        binding.name,
        bindingValue ?? '',
        visitorData,
        sessionId ?? '',
      ].join('|');

  Map<String, dynamic> get innertubeContext => {
        'client': {
          'clientName': clientName,
          'clientVersion': clientVersion,
          if (userAgent != null) 'userAgent': userAgent,
          if (visitorData.isNotEmpty) 'visitorData': visitorData,
        },
      };
}
