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
  final Map<String, int> _epochs = {};

  String get providerId => _provider.id;

  bool supports(PoTokenRequest request) =>
      request.bindingValue != null && _provider.supports(request);

  Future<PoTokenResult?> getToken(PoTokenRequest request) async {
    if (!supports(request)) return null;

    final cached = _cache.get(request);
    if (cached != null) return cached;

    final key = '${_provider.id}|${request.cacheKey}';
    final existing = _pending[key];
    if (existing != null) return existing;

    final epoch = _epochs[key] ?? 0;
    final future = _generate(request, key, epoch);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<PoTokenResult?> _generate(
    PoTokenRequest request,
    String key,
    int epoch,
  ) async {
    try {
      final result = await _provider.getToken(request);
      if (result == null) return null;
      if (result.providerId != _provider.id ||
          !result.isValidFor(request)) return null;
      if ((_epochs[key] ?? 0) == epoch) _cache.put(request, result);
      return result;
    } catch (_) {
      // Do not leak provider responses or token material into application logs.
      return null;
    }
  }

  void invalidate(PoTokenRequest request) {
    final key = '${_provider.id}|${request.cacheKey}';
    _epochs[key] = (_epochs[key] ?? 0) + 1;
    _pending.remove(key);
    _cache.invalidate(request);
  }

  void clear() {
    for (final key in _pending.keys) {
      _epochs[key] = (_epochs[key] ?? 0) + 1;
    }
    _pending.clear();
    _cache.clear();
  }
}
