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
                    position: playerController
                        .progressBarStatus.value.current.inMilliseconds,
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
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black.withOpacity(0.45),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Lyrics appearance',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.text_fields, color: Colors.white),
              onPressed: () => _showLyricsAppearance(context, playerController),
            ),
          ),
        ),
      ],
    );
  }

  void _showLyricsAppearance(BuildContext context, PlayerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.82),
            child: Obx(() {
              final selectedFont = controller.lyricFontFamily.value;
              final activeSize = controller.activeLyricSize.value;
              final isBold = controller.boldActiveLyric.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.text_fields),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Lyrics appearance', style: Theme.of(sheetContext).textTheme.titleLarge)),
                    IconButton(tooltip: 'Close', onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close)),
                  ]),
                  Row(children: [
                    const Expanded(child: Text('Active lyric size')),
                    Text('${activeSize.round()} px'),
                  ]),
                  Slider(
                    min: 16, max: 36, divisions: 20, value: activeSize,
                    label: '${activeSize.round()} px',
                    onChanged: controller.setActiveLyricSize,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bold active lyric'),
                    value: isBold,
                    onChanged: controller.setBoldActiveLyric,
                  ),
                  const SizedBox(height: 6),
                  Text('Choose a font', style: Theme.of(sheetContext).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: PlayerController.lyricFontFamilies.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final font = PlayerController.lyricFontFamilies[index];
                        final selected = font == selectedFont;
                        return Material(
                          color: selected
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => controller.setLyricFontFamily(font),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(font, style: Theme.of(context).textTheme.labelMedium),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Sitting in the music, feel every word',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _fontPreviewStyle(font, size: 19, weight: isBold ? FontWeight.bold : FontWeight.normal),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                                  color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  TextStyle _fontPreviewStyle(String font, {required double size, required FontWeight weight}) {
    if (font == 'Poppins') return GoogleFonts.poppins(fontSize: size, fontWeight: weight);
    return TextStyle(fontFamily: font == 'System' ? null : font, fontSize: size, fontWeight: weight);
  }
}
