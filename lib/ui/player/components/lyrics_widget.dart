import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/loader.dart';
import '../player_controller.dart';
import '../../../utils/lyrics_timeline.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlayerController>();
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(() {
            controller.lyricsStyleRevision.value;
            if (controller.isLyricsLoading.isTrue) {
              return const Center(child: LoadingIndicator());
            }

            if (controller.lyricsMode.toInt() == 1) {
              return Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: padding,
                  child: Obx(
                    () => TextSelectionTheme(
                      data: Theme.of(context).textSelectionTheme,
                      child: SelectableText(
                        controller.lyrics["plainLyrics"] == "NA"
                            ? "lyricsNotAvailable".tr
                            : controller.lyrics["plainLyrics"],
                        textAlign: TextAlign.center,
                        style: _lyricsTextStyle(context, controller).copyWith(
                          color: controller.isLyricsDialogOpen
                              ? Theme.of(context).textTheme.titleMedium!.color
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final synced = controller.lyrics['synced']?.toString() ?? '';
            final songId = controller.currentSong.value?.id ?? '';
            if (synced.trim().isEmpty || synced == 'NA') {
              return Center(
                child: Text(
                  'syncedLyricsNotAvailable'.tr,
                  style: controller.isLyricsDialogOpen
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.white),
                ),
              );
            }

            return _SyncedLyricsView(
              key: ValueKey('$songId:$synced'),
              controller: controller,
              source: synced,
              padding: padding,
            );
          }),
        ),
      ],
    );
  }
}

TextStyle _lyricsTextStyle(BuildContext context, PlayerController controller) {
  final base = Theme.of(context).textTheme.titleMedium!;
  final style = controller.lyricFontFamily.value == 'Poppins'
      ? GoogleFonts.poppins(textStyle: base)
      : base.copyWith(
          fontFamily: controller.lyricFontFamily.value == 'System'
              ? null
              : controller.lyricFontFamily.value,
        );
  return style.copyWith(
    fontSize: controller.activeLyricSize.value,
    fontWeight: controller.boldActiveLyric.value
        ? FontWeight.bold
        : FontWeight.normal,
  );
}

class _SyncedLyricsView extends StatefulWidget {
  const _SyncedLyricsView({
    super.key,
    required this.controller,
    required this.source,
    required this.padding,
  });

  final PlayerController controller;
  final String source;
  final EdgeInsetsGeometry padding;

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  final ScrollController _scrollController = ScrollController();
  late final List<TimedLyricLine> _lines = LyricsTimeline.parse(widget.source);
  bool _followPlayback = true;
  int _lastActiveIndex = -2;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const double _lineExtent = 88;

  void _scrollToActiveLine(int index, {bool animate = true}) {
    if (!_followPlayback ||
        index < 0 ||
        index >= _lines.length ||
        !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final target = (index * _lineExtent -
            (position.viewportDimension - _lineExtent) / 2)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if (animate) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _resumeFollow(int activeIndex) {
    setState(() => _followPlayback = true);
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActiveLine(activeIndex);
    });
  }

  void _seekToLine(TimedLyricLine line) {
    // The renderer position is audio position minus the saved sync offset.
    // Invert that mapping so tapping a line lands on the matching audio time.
    final totalMs = widget.controller.progressBarStatus.value.total.inMilliseconds;
    final requestedMs =
        line.startMs + widget.controller.lyricsSyncOffsetMs.value;
    final audioPositionMs =
        requestedMs.clamp(0, totalMs > 0 ? totalMs : 1 << 31).toInt();
    widget.controller.seek(Duration(milliseconds: audioPositionMs));
    final activeIndex = LyricsTimeline.activeIndex(_lines, line.startMs);
    _resumeFollow(activeIndex);
  }
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle &&
                _followPlayback) {
              setState(() => _followPlayback = false);
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: widget.padding,
            itemCount: _lines.length,
            itemExtent: _lineExtent,
            itemBuilder: (context, index) {
              return Obx(() {
                final positionMs =
                    widget.controller.effectiveLyricsPositionMs;
                final activeIndex = LyricsTimeline.activeIndex(
                  _lines,
                  positionMs,
                );
                if (activeIndex != _lastActiveIndex) {
                  _lastActiveIndex = activeIndex;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _followPlayback) {
                      _scrollToActiveLine(activeIndex);
                    }
                  });
                }

                final active = index == activeIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _seekToLine(_lines[index]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Center(
                          child: Text(
                          _lines[index].text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: _lyricsTextStyle(context, widget.controller)
                              .copyWith(
                            fontSize: widget.controller.activeLyricSize.value *
                                (active ? 1 : 0.88),
                            fontWeight: active &&
                                    widget.controller.boldActiveLyric.value
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: widget.controller.isLyricsDialogOpen
                                ? (active
                                    ? Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.color
                                    : Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.color
                                        ?.withValues(alpha: 0.55))
                                : (active
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.58)),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              });
            },
          ),
        ),
        if (!_followPlayback)
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.tonalIcon(
              onPressed: () {
                final activeIndex = LyricsTimeline.activeIndex(
                  _lines,
                  widget.controller.effectiveLyricsPositionMs,
                );
                _resumeFollow(activeIndex);
              },
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Resume follow'),
            ),
          ),
      ],
    );
  }
}
