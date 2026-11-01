import 'po_token_request.dart';
import 'po_token_result.dart';

class PoTokenCache {
  final Map<String, PoTokenResult> _entries = {};

  PoTokenResult? get(PoTokenRequest request, {DateTime? now}) {
    final result = _entries[request.cacheKey];
    if (result == null) return null;
    if (!result.isValidFor(request, now: now)) {
      _entries.remove(request.cacheKey);
      return null;
    }
    return result;
  }

  void put(PoTokenRequest request, PoTokenResult result) {
    if (result.isValidFor(request)) _entries[request.cacheKey] = result;
  }

  void invalidate(PoTokenRequest request) => _entries.remove(request.cacheKey);

  void clear() => _entries.clear();

  int get length => _entries.length;
}
