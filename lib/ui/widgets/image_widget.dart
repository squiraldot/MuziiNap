import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

class ImageWidget extends StatelessWidget {
  const ImageWidget({
    super.key,
    this.song,
    this.playlist,
    this.album,
    this.artist,
    required this.size,
    this.isPlayerArtImage = false,
  });
  final MediaItem? song;
  final Playlist? playlist;
  final Album? album;
  final bool isPlayerArtImage;
  final Artist? artist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageUrl = song != null
        ? song!.artUri.toString()
        : playlist != null
            ? playlist!.thumbnailUrl
            : album != null
                ? album!.thumbnailUrl
                : artist != null
                    ? artist!.thumbnailUrl
                    : '';
    final shape = artist != null ? BoxShape.circle : BoxShape.rectangle;
    final radius = artist != null ? null : BorderRadius.circular(10);
    final placeholderIcon = song != null
        ? Icons.music_note
        : artist != null
            ? Icons.person_outline
            : Icons.album_outlined;

    /// Only valid for offline songs.
    final offlineAvailable =
        song != null && (song?.extras?['url'] ?? '').contains('file');

    if (offlineAvailable) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.file(
          File(
            '${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png',
          ),
          height: size,
          width: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _ArtworkPlaceholder(
            size: size,
            icon: placeholderIcon,
            shape: shape,
            borderRadius: radius,
          ),
        ),
      );
    }

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
      ),
      child: CachedNetworkImage(
        height: size,
        width: size,
        memCacheHeight: (song != null && !isPlayerArtImage) ? 140 : null,
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => _ArtworkPlaceholder(
          size: size,
          icon: placeholderIcon,
          shape: shape,
          borderRadius: radius,
        ),
        errorWidget: (_, __, ___) => _ArtworkPlaceholder(
          size: size,
          icon: placeholderIcon,
          shape: shape,
          borderRadius: radius,
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({
    required this.size,
    required this.icon,
    required this.shape,
    required this.borderRadius,
  });

  final double size;
  final IconData icon;
  final BoxShape shape;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: shape,
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: (size * 0.28).clamp(20.0, 48.0),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
