import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/song_sharing_config.dart';

/// Testable boundary around Android's raw-intent event channel.
abstract interface class AppLinkSource {
  Stream<String> get linkStream;
}

class PluginAppLinkSource implements AppLinkSource {
  static const EventChannel _channel = EventChannel('muziinap/raw_deep_links');

  @override
  Stream<String> get linkStream => _channel
      .receiveBroadcastStream()
      .where((event) => event is String)
      .cast<String>();
}

class SongLinkRequest {
  const SongLinkRequest({required this.videoId, required this.uri});

  final String videoId;
  final Uri uri;
}

class DeepLinkService {
  DeepLinkService({
    AppLinkSource? source,
    DateTime Function()? clock,
    this.duplicateWindow = const Duration(seconds: 2),
  })  : _source = source ?? PluginAppLinkSource(),
        _clock = clock ?? DateTime.now;

  final AppLinkSource _source;
  final DateTime Function() _clock;
  final Duration duplicateWindow;
  final StreamController<SongLinkRequest> _songRequests =
      StreamController<SongLinkRequest>.broadcast();
  final StreamController<Uri> _legacyLinks =
      StreamController<Uri>.broadcast();
  final Map<String, DateTime> _recentEvents = <String, DateTime>{};

  StreamSubscription<String>? _linkSubscription;
  Future<void>? _startFuture;
  bool _disposed = false;

  Stream<SongLinkRequest> get songRequests => _songRequests.stream;
  Stream<Uri> get legacyLinks => _legacyLinks.stream;
  bool get isStarted => _startFuture != null;

  /// Installs the listener before Android drains queued cold-start intents.
  Future<void> start() => _startFuture ??= _startInternal();

  Future<void> _startInternal() async {
    if (_disposed) return;
    _linkSubscription = _source.linkStream.listen(
      _handleRawUrl,
      onError: (Object error, StackTrace stackTrace) {
        // ignore: avoid_print
        print('MuziiNap deep-link stream error: $error');
      },
    );
  }

  void _handleRawUrl(String rawUrl) {
    if (_disposed) return;
    final videoId = SongSharingConfig.parseVideoId(rawUrl);
    if (videoId != null) {
      if (_isDuplicate('song:$videoId')) return;
      _songRequests.add(SongLinkRequest(
        videoId: videoId,
        uri: Uri.parse(SongSharingConfig.canonicalUrl(videoId)),
      ));
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || _isDuplicate('uri:$rawUrl')) return;
    _legacyLinks.add(uri);
  }

  bool _isDuplicate(String key) {
    final now = _clock();
    _recentEvents.removeWhere(
      (_, seenAt) => now.difference(seenAt) > duplicateWindow,
    );
    final previous = _recentEvents[key];
    if (previous != null && now.difference(previous) <= duplicateWindow) {
      return true;
    }
    _recentEvents[key] = now;
    return false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _linkSubscription?.cancel();
    await _songRequests.close();
    await _legacyLinks.close();
    _recentEvents.clear();
  }
}
