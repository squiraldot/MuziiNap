import 'dart:async';

import 'package:app_links/app_links.dart';

import '../utils/song_sharing_config.dart';

/// Testable boundary around the app_links plugin.
abstract interface class AppLinkSource {
  Future<Uri?> getInitialLink();

  Stream<Uri> get uriLinkStream;
}

class PluginAppLinkSource implements AppLinkSource {
  PluginAppLinkSource() : _appLinks = AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialLink() => _appLinks.getInitialAppLink();

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;
}

/// A validated canonical song-link request. This is a routing event only;
/// playback is intentionally owned by a later application-layer phase.
class SongLinkRequest {
  const SongLinkRequest({
    required this.videoId,
    required this.uri,
  });

  final String videoId;
  final Uri uri;
}

/// Owns the app_links plugin's single incoming-link listener and separates
/// canonical MuziiNap song requests from legacy URLs (including YouTube imports).
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

  StreamSubscription<Uri>? _linkSubscription;
  Future<void>? _startFuture;
  bool _disposed = false;

  /// Valid canonical song requests for the application routing layer.
  Stream<SongLinkRequest> get songRequests => _songRequests.stream;

  /// Non-canonical links delegated to the existing YouTube/import handler.
  Stream<Uri> get legacyLinks => _legacyLinks.stream;

  bool get isStarted => _startFuture != null;

  /// Starts the runtime listener before awaiting the initial URI. This avoids
  /// a gap in which an incoming link could be lost during cold-start setup.
  Future<void> start() => _startFuture ??= _startInternal();

  Future<void> _startInternal() async {
    if (_disposed) return;

    _linkSubscription = _source.uriLinkStream.listen(
      _handleUri,
      onError: (Object error, StackTrace stackTrace) {
        // A malformed platform event must not terminate future link delivery.
        // ignore: avoid_print
        print('MuziiNap deep-link stream error: $error');
      },
    );

    try {
      final initialUri = await _source.getInitialLink();
      if (!_disposed && initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (error) {
      // Initial-link retrieval can fail independently of the runtime stream.
      // Keep the stream active so later incoming links still work.
      // ignore: avoid_print
      print('MuziiNap initial deep-link retrieval failed: $error');
    }
  }

  void _handleUri(Uri uri) {
    if (_disposed) return;

    final videoId = SongSharingConfig.parseVideoId(uri);
    if (videoId != null) {
      if (_isDuplicate('song:$videoId')) return;
      _songRequests.add(SongLinkRequest(videoId: videoId, uri: uri));
      return;
    }

    if (_isDuplicate('uri:${uri.toString()}')) return;
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
