import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Builds and dispatches canonical MuziiNap links for individual songs.
class SongSharingService {
  const SongSharingService();

  static const String _host = 'muziinap-site.vercel.app';
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Returns the canonical song URL, or null when [song] has an invalid ID.
  ///
  /// YouTube video IDs are validated before being inserted into the URL path,
  /// so URL-like strings and path separators can never become share targets.
  String? generateSongLink(MediaItem? song) {
    if (song == null) return null;
    final videoId = song.id;
    if (!_videoIdPattern.hasMatch(videoId)) return null;

    return Uri.https(_host, '/song/$videoId').toString();
  }

  /// Shares the canonical MuziiNap URL. Returns false for invalid songs or
  /// when the platform share operation fails.
  Future<bool> shareSong(MediaItem? song) async {
    final link = generateSongLink(song);
    if (link == null) return false;

    try {
      await Share.share(link);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Copies the canonical MuziiNap URL. Returns false for invalid songs or
  /// when the platform clipboard operation fails.
  Future<bool> copySongLink(MediaItem? song) async {
    final link = generateSongLink(song);
    if (link == null) return false;

    try {
      await Clipboard.setData(ClipboardData(text: link));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the exact canonical URL that should be encoded in the song QR.
  String? generateSongQr(MediaItem? song) => generateSongLink(song);
}
