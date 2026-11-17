class Supporter {
  const Supporter({required this.name, this.message, this.amount, this.currency, this.supportedAt});
  final String name;
  final String? message;
  final num? amount;
  final String? currency;
  final DateTime? supportedAt;

  factory Supporter.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException('Invalid supporter record.');
    final rawName = value['name'];
    final rawMessage = value['message'];
    final rawAmount = value['amount'];
    final rawCurrency = value['currency'];
    if (rawName != null && rawName is! String) throw const FormatException('Invalid supporter name.');
    if (rawMessage != null && rawMessage is! String) throw const FormatException('Invalid supporter message.');
    if (rawAmount != null && rawAmount is! num) throw const FormatException('Invalid supporter amount.');
    if (rawCurrency != null && rawCurrency is! String) throw const FormatException('Invalid supporter currency.');
    final name = (rawName as String?)?.trim();
    final message = (rawMessage as String?)?.trim();
    final currency = (rawCurrency as String?)?.trim();
    return Supporter(
      name: name == null || name.isEmpty ? 'Anonymous supporter' : name,
      message: message == null || message.isEmpty ? null : message,
      amount: rawAmount as num?,
      currency: currency == null || currency.isEmpty ? null : currency,
      supportedAt: _parseTimestamp(value['supported_at']),
    );
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const FormatException('Invalid supporter timestamp.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException('Invalid supporter timestamp.');
    return parsed;
  }
}

class SupportersResponse {
  const SupportersResponse({required this.updatedAt, required this.total, required this.supporters});
  final DateTime? updatedAt;
  final int total;
  final List<Supporter> supporters;

  factory SupportersResponse.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException('Invalid supporters response.');
    final total = value['total'];
    final rawSupporters = value['supporters'];
    if (total is! int || total < 0 || rawSupporters is! List) {
      throw const FormatException('Invalid supporters response structure.');
    }
    DateTime? updatedAt;
    final rawUpdatedAt = value['updated_at'];
    if (rawUpdatedAt != null) {
      if (rawUpdatedAt is! String) throw const FormatException('Invalid update timestamp.');
      updatedAt = DateTime.tryParse(rawUpdatedAt);
      if (updatedAt == null) throw const FormatException('Invalid update timestamp.');
    }
    final parsed = rawSupporters.map(Supporter.fromJson).toList(growable: false);
    return SupportersResponse(
      updatedAt: updatedAt,
      total: total,
      supporters: List<Supporter>.unmodifiable(parsed.take(10)),
    );
  }
}