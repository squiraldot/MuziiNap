import 'dart:async';

import 'po_token_cache.dart';
import 'po_token_provider.dart';
import 'po_token_request.dart';
import 'po_token_result.dart';

class PoTokenManager {
  PoTokenManager({
    required PoTokenProvider provider,
    PoTokenCache? cache,
  })  : _provider = provider,
        _cache = cache ?? PoTokenCache();

  final PoTokenProvider _provider;
  final PoTokenCache _cache;
  final Map<String, Future<PoTokenResult?>> _pending = {};

  String get providerId => _provider.id;

  Future<PoTokenResult?> getToken(PoTokenRequest request) async {
    final bindingValue = request.bindingValue;
    if (bindingValue == null || !_provider.supports(request)) return null;

    final cached = _cache.get(request);
    if (cached != null) return cached;

    final key = '${_provider.id}|${request.cacheKey}';
    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _generate(request);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<PoTokenResult?> _generate(PoTokenRequest request) async {
    try {
      final result = await _provider.getToken(request);
      if (result == null) return null;
      if (result.providerId != _provider.id ||
          !result.isValidFor(request)) return null;
      _cache.put(request, result);
      return result;
    } catch (_) {
      // Do not leak provider responses or token material into application logs.
      return null;
    }
  }

  void invalidate(PoTokenRequest request) => _cache.invalidate(request);

  void clear() {
    _cache.clear();
    // In-flight requests are allowed to finish; their result is not reused
    // after the cache has been cleared.
  }
}
