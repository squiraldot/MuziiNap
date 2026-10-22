import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/quick_picks.dart';
import '../player/player_controller.dart';
import 'image_widget.dart';
import 'songinfo_bottom_sheet.dart';

class QuickPicksWidget extends StatelessWidget {
  const QuickPicksWidget({
    super.key,
    required this.content,
    this.scrollController,
  });

  final QuickPicks content;
  final ScrollController? scrollController;

  bool _isQuickPicks(String title) =>
      title.trim().toLowerCase() == 'quick picks' ||
      title.trim().toLowerCase() == 'quick pick';

  bool _isWideShelf(String title) {
    final normalized = title.trim().toLowerCase();
    final titleHint = normalized.contains('listen again') ||
        normalized.contains('forgotten') ||
        normalized.contains('long listens') ||
        normalized.contains('music video') ||
        normalized.contains('music videos');
    final videoCount = content.songList.where((song) {
      final type = song.extras?['videoType']?.toString() ?? '';
      return type.isNotEmpty && type != 'MUSIC_VIDEO_TYPE_ATV';
    }).length;
    return titleHint ||
        (content.songList.isNotEmpty &&
            videoCount * 2 >= content.songList.length);
  }

  void _play(BuildContext context, int index) {
    Get.find<PlayerController>().pushSongToQueue(content.songList[index]);
  }

  void _showSongMenu(BuildContext context, MediaItem song) {
    final player = Get.find<PlayerController>();
    showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      context: player.homeScaffoldkey.currentState!.context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: Theme.of(sheetContext).bottomSheetTheme.backgroundColor?.withValues(alpha: 0.78),
            child: SongInfoBottomSheet(song),
          ),
        ),
      ),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }

  Widget _heading(BuildContext context, {double bottom = 10}) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(
        content.title.trim().isEmpty ? 'YouTube Music' : content.title.trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.35,
            ),
      ),
    );
  }

  Widget _quickPicksList(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isLandscape = availableWidth >= 760;
        // SimpMusic uses a 4-row, 256dp-high horizontal grid. Each item is
        // widthDp - 30dp, and landscape rows are capped at 400dp so they do
        // not stretch across a wide window.
        final itemWidth = ((isLandscape
                    ? availableWidth.clamp(0.0, 430.0)
                    : availableWidth) -
                30.0)
            .toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(context),
            SizedBox(
              height: 256,
              child: Scrollbar(
                thickness: 0,
                controller: scrollController,
                child: GridView.builder(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: content.songList.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisExtent: itemWidth,
                    crossAxisSpacing: 0,
                    mainAxisSpacing: 0,
                  ),
                  itemBuilder: (_, index) {
                    final song = content.songList[index];
                    return Listener(
                      onPointerDown: (event) {
                        if (event.buttons == kSecondaryMouseButton) {
                          _showSongMenu(context, song);
                        }
                      },
                      child: InkWell(
                        onTap: () => _play(context, index),
                        onLongPress: () => _showSongMenu(context, song),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: ImageWidget(song: song, size: 44),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if ((song.artist ?? '').trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          song.artist ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cardShelf(BuildContext context, {required bool wideCards}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // SimpMusic uses fixed home card widths: 160dp for square
        // playlist/album cards and 284.5dp for 16:9 video cards.
        final cardWidth = wideCards ? 304.5 : 180.0;
        final imageWidth = wideCards ? 284.5 : 160.0;
        final imageHeight = wideCards ? 160.0 : 160.0;
        const imageRadius = 10.0;
        const sectionHeight = 270.0;

        return SizedBox(
          height: sectionHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(context, bottom: 0),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: content.songList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 0),
                  itemBuilder: (_, index) {
                    final song = content.songList[index];
                    return SizedBox(
                      width: cardWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(imageRadius),
                          onTap: () => _play(context, index),
                          onLongPress: () => _showSongMenu(context, song),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(imageRadius),
                                child: SizedBox(
                                  width: imageWidth,
                                  height: imageHeight,
                                  child: Image.network(
                                    song.artUri.toString(),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Image.asset(
                                      'assets/icons/song.png',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                song.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              if ((song.artist ?? '').trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    song.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (content.songList.isEmpty) return const SizedBox.shrink();
    final title = content.title;
    if (_isQuickPicks(title)) {
      return _quickPicksList(context);
    }
    return _cardShelf(context, wideCards: _isWideShelf(title));
  }
}
