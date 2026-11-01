import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:youtube_explode_dart/js_challenge.dart';

import 'player_script_cache.dart';

abstract interface class PlayerJavaScriptExecutor {
  Future<String?> solve(Uri playerUrl, JSChallengeType type, String challenge);
}

/// Executes yt-dlp EJS against the current YouTube player source using QuickJS
/// on Android. One runtime is reused and all challenge results are cached.
class PlayerJsService implements PlayerJavaScriptExecutor {
  PlayerJsService({PlayerScriptCache? scriptCache})
      : _scriptCache = scriptCache ?? PlayerScriptCache();

  final PlayerScriptCache _scriptCache;
  JavascriptRuntime? _runtime;
  Future<String>? _modulesFuture;
  final Map<String, String> _preprocessedPlayers = {};
  final Map<(String, JSChallengeType, String), String> _results = {};
  final Map<(String, JSChallengeType, String), Future<String?>> _pending = {};

  JavascriptRuntime get _javascriptRuntime =>
      _runtime ??= getJavascriptRuntime(forceJavascriptCoreOnAndroid: false);

  @override
  Future<String?> solve(
    Uri playerUrl,
    JSChallengeType type,
    String challenge,
  ) async {
    final player = await _scriptCache.get(playerUrl);
    final key = (player.url.toString(), type, challenge);
    final cached = _results[key];
    if (cached != null) return cached;

    final pending = _pending[key];
    if (pending != null) return pending;

    final request = _solveUncached(player, type, challenge);
    _pending[key] = request;
    try {
      final result = await request.timeout(const Duration(seconds: 12));
      if (result != null && result.isNotEmpty) _results[key] = result;
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  Future<String> _loadModules() async {
    try {
      return await (_modulesFuture ??= EJSBuilder.getJSModules())
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Do not permanently cache a transient network/module initialization
      // failure; the next track can retry the EJS bootstrap.
      _modulesFuture = null;
      rethrow;
    }
  }

  Future<String?> _solveUncached(
    CachedPlayerScript player,
    JSChallengeType type,
    String challenge,
  ) async {
    final modules = await _loadModules();
    final playerKey = player.url.toString();
    final preprocessed = _preprocessedPlayers[playerKey];
    final call = EJSBuilder.buildJSCall(
      preprocessed ?? player.source,
      {type: [challenge]},
      isPreprocessed: preprocessed != null,
    );

    final evaluated = _javascriptRuntime.evaluate('$modules\n$call;');
    final output = evaluated.stringResult;
    if (output.isEmpty) {
      throw StateError('YouTube player JavaScript returned an empty result');
    }

    final decoded = jsonDecode(output);
    if (decoded is! Map || decoded['type'] != 'result') {
      throw const FormatException('Invalid EJS decipher response');
    }

    final updatedPlayer = decoded['preprocessed_player'];
    if (updatedPlayer is String && updatedPlayer.isNotEmpty) {
      _preprocessedPlayers[playerKey] = updatedPlayer;
    }

    final responses = decoded['responses'];
    if (responses is! List || responses.isEmpty) {
      throw const FormatException('EJS did not return a challenge result');
    }
    final first = responses.first;
    if (first is! Map || first['type'] != 'result') {
      throw const FormatException('EJS challenge execution failed');
    }
    final data = first['data'];
    final result = data is Map ? data[challenge] : null;
    if (result is! String || result.isEmpty) return null;
    return result;
  }

  int get cachedChallengeCount => _results.length;

  void clearCaches() {
    _results.clear();
    _preprocessedPlayers.clear();
    _scriptCache.clear();
  }
}
