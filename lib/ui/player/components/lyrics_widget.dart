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
                          style: (playerController.lyricFontFamily.value == 'System'
                                  ? Theme.of(context).textTheme.titleMedium!
                                  : GoogleFonts.getFont(
                                      playerController.lyricFontFamily.value,
                                      textStyle: Theme.of(context).textTheme.titleMedium,
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
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lyrics appearance', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: controller.lyricFontFamily.value,
                decoration: const InputDecoration(labelText: 'Font family'),
                items: PlayerController.lyricFontFamilies.map((font) => DropdownMenuItem(
                  value: font,
                  child: Text(font, style: TextStyle(fontFamily: font == 'System' ? null : font)),
                )).toList(),
                onChanged: (value) { if (value != null) controller.setLyricFontFamily(value); },
              ),
              const SizedBox(height: 18),
              Row(children: [
                const Expanded(child: Text('Active lyric size')),
                Text('${controller.activeLyricSize.value.round()} px'),
              ]),
              Slider(
                min: 16, max: 36, divisions: 20,
                value: controller.activeLyricSize.value,
                label: '${controller.activeLyricSize.value.round()} px',
                onChanged: controller.setActiveLyricSize,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bold active lyric'),
                value: controller.boldActiveLyric.value,
                onChanged: controller.setBoldActiveLyric,
              ),
              const SizedBox(height: 8),
              Center(child: Text(
                'Preview · MuziiNap lyrics',
                textAlign: TextAlign.center,
                style: (controller.lyricFontFamily.value == 'System'
                    ? const TextStyle()
                    : GoogleFonts.getFont(controller.lyricFontFamily.value)).copyWith(
                  fontSize: controller.activeLyricSize.value,
                  fontWeight: controller.boldActiveLyric.value ? FontWeight.bold : FontWeight.normal,
                ),
              )),
            ],
          )),
        ),
      ),
    );
  }
}
