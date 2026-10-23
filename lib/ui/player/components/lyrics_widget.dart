import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/loader.dart';
import '../player_controller.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(() {
            playerController.lyricsStyleRevision.value;
            return playerController.isLyricsLoading.isTrue
          ? const Center(
              child: LoadingIndicator(),
            )
          : playerController.lyricsMode.toInt() == 1
              ? Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: padding,
                    child: Obx(
                      () => TextSelectionTheme(
                        data: Theme.of(context).textSelectionTheme,
                        child: SelectableText(
                          playerController.lyrics["plainLyrics"] == "NA"
                              ? "lyricsNotAvailable".tr
                              : playerController.lyrics["plainLyrics"],
                          textAlign: TextAlign.center,
                          style: (playerController.lyricFontFamily.value == 'Poppins'
                                  ? GoogleFonts.poppins(textStyle: Theme.of(context).textTheme.titleMedium)
                                  : Theme.of(context).textTheme.titleMedium!.copyWith(
                                      fontFamily: playerController.lyricFontFamily.value == 'System'
                                          ? null
                                          : playerController.lyricFontFamily.value,
                                    )).copyWith(
                              color: playerController.isLyricsDialogOpen
                                  ? Theme.of(context).textTheme.titleMedium!.color
                                  : Colors.white,
                              fontSize: playerController.activeLyricSize.value,
                            ),
                        ),
                      ),
                    ),
                  ),
                )
              : IgnorePointer(
                  child: LyricsReader(
                    padding: const EdgeInsets.only(left: 5, right: 5),
                    lyricUi: playerController.lyricUi,
                    position: playerController.effectiveLyricsPositionMs,
                    model: LyricsModelBuilder.create()
                        .bindLyricToMain(
                            playerController.lyrics['synced'].toString())
                        .getModel(),
                    emptyBuilder: () => Center(
                      child: Text(
                        "syncedLyricsNotAvailable".tr,
                        style: playerController.isLyricsDialogOpen
                              ? Theme.of(context).textTheme.titleMedium!
                              : Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                );
          }),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 4,
          child: Obx(() {
            final offset = playerController.lyricsSyncOffsetMs.value;
            final isSynced = playerController.lyricsMode.value == 0 &&
                playerController.lyrics['synced'].toString().trim().isNotEmpty;
            return Material(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.sync, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      isSynced ? 'Sync offset: ${offset} ms' : 'Sync adjustment works with synced lyrics',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    )),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Reset sync offset',
                      onPressed: isSynced ? playerController.resetLyricsSyncOffset : null,
                      icon: const Icon(Icons.restart_alt, color: Colors.white, size: 20),
                    ),
                  ]),
                  Row(children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Delay lyrics by 0.5 seconds',
                      onPressed: isSynced ? () => playerController.setLyricsSyncOffset(offset + 500) : null,
                      icon: const Icon(Icons.remove, color: Colors.white),
                    ),
                    Expanded(child: Slider(
                      min: -10000, max: 10000, divisions: 40,
                      value: offset.toDouble(),
                      onChanged: isSynced ? (value) => playerController.setLyricsSyncOffset(value.round()) : null,
                    )),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Advance lyrics by 0.5 seconds',
                      onPressed: isSynced ? () => playerController.setLyricsSyncOffset(offset - 500) : null,
                      icon: const Icon(Icons.add, color: Colors.white),
                    ),
                  ]),
                  const Text('Positive = lyrics later • Negative = lyrics earlier',
                    style: TextStyle(color: Colors.white70, fontSize: 10)),
                ]),
              ),
            );
          }),
        ),
      ],
    );
  }

}
