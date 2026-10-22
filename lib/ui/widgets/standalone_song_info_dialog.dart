import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/constant.dart';
import '../../services/downloader.dart';
import '../navigator.dart';
import '../player/player_controller.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/qr_code_dialog.dart';
import '../widgets/sleep_timer_bottom_sheet.dart';
import '../widgets/snackbar.dart';

enum SongInfoDialogView { info, more }

/// Completely standalone Song Info dialog.
///
/// This dialog intentionally does not depend on the legacy
/// SongInfoBottomSheet/SongInfoDialog implementation. It owns both the
/// metadata view and the song actions shown from the player.
class StandaloneSongInfoDialog extends StatelessWidget {
  final MediaItem song;
  final SongInfoDialogView view;

  const StandaloneSongInfoDialog({
    super.key,
    required this.song,
    this.view = SongInfoDialogView.info,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 32).clamp(280.0, 560.0).toDouble();
    final height = (size.height - 48).clamp(280.0, 680.0).toDouble();
    final metadata = _readMetadata(song);
    final artists = _artistEntries(song);

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.13),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _asText(song.artist),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'close'.tr,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        if (view == SongInfoDialogView.info) ...[
                          _SectionTitle(title: 'songInfo'.tr),
                          const SizedBox(height: 8),
                          ...metadata.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _MetadataRow(
                                label: item.label,
                                value: item.value,
                              ),
                            ),
                          ),
                        ],
                        if (view == SongInfoDialogView.more) ...[
                          const _SectionTitle(title: 'More'),
                          _ActionTile(
                            icon: Icons.download,
                            title: 'Download',
                            onTap: () {
                              final downloader = Get.find<Downloader>();
                              downloader.download(song);
                            },
                          ),
                          _ActionTile(
                            icon: Icons.sensors,
                            title: 'Start radio',
                            onTap: () {
                              final controller = Get.find<PlayerController>();
                              Navigator.of(context).pop();
                              controller.startRadio(song);
                            },
                          ),
                          _ActionTile(
                            icon: Icons.playlist_add,
                            title: _translatedOrFallback(
                              'addToPlaylist',
                              'Add to playlist',
                            ),
                            onTap: () {
                              final navigator =
                                  Navigator.of(context, rootNavigator: true);
                              navigator.pop();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!navigator.mounted) return;
                                showDialog<void>(
                                  context: navigator.context,
                                  builder: (_) => AddToPlaylist([song]),
                                ).whenComplete(
                                  () => Get.delete<AddToPlaylistController>(),
                                );
                              });
                            },
                          ),
                          ...artists.map(
                            (artist) => _ActionTile(
                              icon: Icons.person,
                              title: '${'viewArtist'.tr} (${artist.name})',
                              onTap: () async {
                                final controller = Get.find<PlayerController>();
                                Navigator.of(context).pop();
                                controller.playerPanelController.close();
                                if (artist.id.isEmpty) return;
                                await Get.toNamed(
                                  ScreenNavigationSetup.artistScreen,
                                  id: ScreenNavigationSetup.id,
                                  preventDuplicates: true,
                                  arguments: [true, artist.id],
                                );
                              },
                            ),
                          ),
                          _ActionTile(
                            icon: Icons.open_with,
                            title: 'openIn'.tr,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'YouTube',
                                  onPressed: () => _openUrl(
                                    context,
                                    'https://youtube.com/watch?v=${song.id}',
                                  ),
                                  icon: const Icon(Icons.ondemand_video),
                                ),
                                IconButton(
                                  tooltip: 'YouTube Music',
                                  onPressed: () => _openUrl(
                                    context,
                                    'https://music.youtube.com/watch?v=${song.id}',
                                  ),
                                  icon: const Icon(Icons.play_circle),
                                ),
                              ],
                            ),
                          ),
                          _ActionTile(
                            icon: Icons.timer,
                            title: 'sleepTimer'.tr,
                            onTap: () {
                              final controller = Get.find<PlayerController>();
                              final sheetContext = controller
                                  .homeScaffoldkey.currentState?.context;
                              if (sheetContext == null) return;
                              Navigator.of(context).pop();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!sheetContext.mounted) return;
                                showModalBottomSheet<void>(
                                  context: sheetContext,
                                  isScrollControlled: true,
                                  constraints:
                                      const BoxConstraints(maxWidth: 500),
                                  barrierColor: Colors.black54,
                                  builder: (_) => ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 18,
                                        sigmaY: 18,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Theme.of(sheetContext)
                                              .colorScheme
                                              .surface
                                              .withValues(alpha: 0.82),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.10,
                                            ),
                                          ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(24),
                                          ),
                                        ),
                                        child: const SleepTimerBottomSheet(),
                                      ),
                                    ),
                                  ),
                                );
                              });
                            },
                          ),
                          _ActionTile(
                            icon: Icons.share,
                            title: _translatedOrFallback(
                              'shareSong',
                              'Share this song',
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              Share.share(
                                'https://youtube.com/watch?v=${song.id}',
                              );
                            },
                          ),
                          _ActionTile(
                            icon: Icons.copy,
                            title: 'Copy Link',
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: 'https://youtube.com/watch?v=${song.id}',
                                ),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                snackbar(
                                  context,
                                  'Link Copied!',
                                  size: SanckBarSize.MEDIUM,
                                ),
                              );
                            },
                          ),
                          _ActionTile(
                            icon: Icons.qr_code,
                            title: 'QR Code',
                            onTap: () {
                              final navigator =
                                  Navigator.of(context, rootNavigator: true);
                              navigator.pop();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!navigator.mounted) return;
                                showQrCodeDialog(
                                  navigator.context,
                                  'https://youtube.com/watch?v=${song.id}',
                                  song.title,
                                );
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('close'.tr),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _translatedOrFallback(String key, String fallback) {
    final translated = key.tr;
    return translated == key ? fallback : translated;
  }

  static Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri);
    if (!context.mounted || opened) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      snackbar(
        context,
        'Unable to open link',
        size: SanckBarSize.MEDIUM,
      ),
    );
  }

  static List<_ArtistEntry> _artistEntries(MediaItem song) {
    final result = <_ArtistEntry>[];
    final rawArtists = song.extras?['artists'];

    if (rawArtists is Iterable) {
      for (final raw in rawArtists) {
        if (raw is Map) {
          final id = raw['id']?.toString();
          final name = raw['name']?.toString();
          if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
            result.add(_ArtistEntry(id: id, name: name));
          }
        }
      }
    }

    return result;
  }

  static List<_MetadataValue> _readMetadata(MediaItem song) {
    final stream = _readOptionalStreamMetadata(song.id);

    return [
      _MetadataValue('ID', _asText(song.id)),
      _MetadataValue('Album', _asText(song.album)),
      _MetadataValue('Artist', _asText(song.artist)),
      _MetadataValue(
        'Duration',
        _asText(
          stream['approxDurationMs'] ?? song.duration?.inMilliseconds,
          suffix: ' ms',
        ),
      ),
      _MetadataValue('Audio codec', _asText(stream['audioCodec'])),
      _MetadataValue('Bitrate', _asText(stream['bitrate'])),
      _MetadataValue('Loudness (dB)', _asText(stream['loudnessDb'])),
    ];
  }

  static Map<String, dynamic> _readOptionalStreamMetadata(String id) {
    const empty = <String, dynamic>{};

    if (id.isEmpty) return empty;

    final fromDownloads = _readDownloads(id);
    if (fromDownloads.isNotEmpty) return fromDownloads;

    final fromCache = _readUrlCache(id);
    if (fromCache.isNotEmpty) return fromCache;

    return empty;
  }

  static Map<String, dynamic> _readDownloads(String id) {
    if (!Hive.isBoxOpen('SongDownloads')) return const {};

    try {
      final box = Hive.box('SongDownloads');
      final entry = box.get(id);
      if (entry is! Map) return const {};

      final raw = entry['streamInfo'];
      if (raw is Map) return _normalizeMap(raw);
      if (raw is List && raw.length > 1 && raw[1] is Map) {
        return _normalizeMap(raw[1]);
      }
    } catch (_) {
      // Download metadata is optional; rendering must continue with NA values.
    }

    return const {};
  }

  static Map<String, dynamic> _readUrlCache(String id) {
    if (!Hive.isBoxOpen('SongsUrlCache')) return const {};

    try {
      final box = Hive.box('SongsUrlCache');
      final entry = box.get(id);
      if (entry is! Map) return const {};

      final quality = _readStreamingQuality();
      final preferredKey =
          quality == 0 ? 'lowQualityAudio' : 'highQualityAudio';
      final fallbackKey =
          preferredKey == 'highQualityAudio'
              ? 'lowQualityAudio'
              : 'highQualityAudio';

      final preferred = entry[preferredKey];
      if (preferred is Map) return _normalizeMap(preferred);

      final fallback = entry[fallbackKey];
      if (fallback is Map) return _normalizeMap(fallback);
    } catch (_) {
      // Cache metadata is optional; rendering must continue with NA values.
    }

    return const {};
  }

  static int? _readStreamingQuality() {
    if (!Hive.isBoxOpen(appPrefsBoxName)) return null;

    try {
      final raw = Hive.box(appPrefsBoxName).get('streamingQuality');
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _normalizeMap(Map raw) {
    final result = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key != null) {
        result[key.toString()] = value;
      }
    });
    return result;
  }

  static String _asText(
    dynamic value, {
    String suffix = '',
  }) {
    if (value == null) return 'NA';

    final normalized = value.toString().trim();
    if (normalized.isEmpty) return 'NA';

    return '$normalized$suffix';
  }
}

class _ArtistEntry {
  final String id;
  final String name;

  const _ArtistEntry({
    required this.id,
    required this.name,
  });
}

class _MetadataValue {
  final String label;
  final String value;

  const _MetadataValue(this.label, this.value);
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: const VisualDensity(vertical: -1),
      leading: Icon(icon),
      title: Text(title),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
