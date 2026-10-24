import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../utils/theme_controller.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../player_controller.dart';
import 'package:google_fonts/google_fonts.dart';

void _showLyricsSyncAdjustment(BuildContext context, PlayerController controller) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(dialogContext).colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Obx(() {
          final offset = controller.lyricsSyncOffsetMs.value;
          final isSynced = controller.lyricsMode.value == 0 &&
              controller.lyrics['synced'].toString().trim().isNotEmpty;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Icons.sync),
                const SizedBox(width: 10),
                Expanded(child: Text('Lyrics Sync Adjustment',
                    style: Theme.of(dialogContext).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              Text(
                isSynced
                    ? 'Sync offset: $offset ms'
                    : 'Sync adjustment works with synced lyrics only.',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Row(children: [
                IconButton(
                  tooltip: 'Delay lyrics by 500 ms',
                  onPressed: isSynced
                      ? () => controller.setLyricsSyncOffset(offset + 500)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(child: Slider(
                  min: -10000,
                  max: 10000,
                  divisions: 40,
                  value: offset.toDouble(),
                  label: '$offset ms',
                  onChanged: isSynced
                      ? (value) => controller.setLyricsSyncOffset(value.round())
                      : null,
                )),
                IconButton(
                  tooltip: 'Advance lyrics by 500 ms',
                  onPressed: isSynced
                      ? () => controller.setLyricsSyncOffset(offset - 500)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
              const Text(
                'Positive = lyrics later  •  Negative = lyrics earlier',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: isSynced ? controller.resetLyricsSyncOffset : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
              ),
            ],
          );
        }),
      ),
    ),
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
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.72),
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
                  Expanded(child: Text('Lyrics appearance', style: Theme.of(sheetContext).textTheme.titleMedium)),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close)),
                ]),
                Row(children: [
                  Expanded(child: Text('Active lyric size', style: Theme.of(sheetContext).textTheme.bodyMedium)),
                  Text('${activeSize.round()} px', style: Theme.of(sheetContext).textTheme.bodyMedium),
                ]),
                Slider(
                  min: 16, max: 36, divisions: 20, value: activeSize,
                  label: '${activeSize.round()} px',
                  onChanged: controller.setActiveLyricSize,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Bold active lyric', style: Theme.of(sheetContext).textTheme.bodyMedium),
                  value: isBold,
                  onChanged: controller.setBoldActiveLyric,
                ),
                const SizedBox(height: 6),
                Text('Choose a font', style: Theme.of(sheetContext).textTheme.titleSmall),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(font, style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Sitting in the music, feel every word',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _fontPreviewStyle(font, size: Theme.of(context).textTheme.bodyMedium!.fontSize!, weight: isBold ? FontWeight.bold : FontWeight.normal),
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

class LyricsSwitch extends StatelessWidget {
  const LyricsSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Obx(
      () => playerController.showLyricsflag.value
          ? Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ToggleSwitch(
                    minWidth: 66.0,
                    minHeight: 34.0,
                    fontSize: 12.0,
                    cornerRadius: 18.0,
                    activeBgColors: [
                      [Theme.of(context).primaryColor.withLightness(0.4)],
                      [Theme.of(context).primaryColor.withLightness(0.4)]
                    ],
                    activeFgColor: Colors.white,
                    inactiveBgColor: Theme.of(context).colorScheme.secondary,
                    inactiveFgColor: Colors.white,
                    initialLabelIndex: playerController.lyricsMode.value,
                    totalSwitches: 2,
                    labels: ['synced'.tr, 'plain'.tr],
                    radiusStyle: true,
                    onToggle: (value) {
                      if (value == null) return;
                      if (value == playerController.lyricsMode.value) {
                        playerController.showLyricsflag.value = false;
                      } else {
                        playerController.changeLyricsMode(value);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () => playerController.reloadLyrics(),
                    icon: const Icon(Icons.refresh),
                    color: Colors.white,
                    tooltip: "Reload Lyrics",
                  ),
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                    padding: EdgeInsets.zero,
                    onPressed: () => _showLyricsAppearance(context, playerController),
                    icon: const Icon(Icons.text_fields, size: 25),
                    color: Colors.white,
                    tooltip: "Lyrics appearance",
                  ),
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                    padding: EdgeInsets.zero,
                    onPressed: () => _showLyricsSyncAdjustment(context, playerController),
                    icon: const Icon(Icons.sync, size: 25),
                    color: Colors.white,
                    tooltip: "Lyrics sync adjustment",
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Lyrics display mode',
                    icon: const Icon(Icons.translate, color: Colors.white),
                    onSelected: playerController.setLyricsDisplayMode,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'original', child: Text('Original lyrics')),
                      PopupMenuItem(value: 'romanized', child: Text('Romanized Hindi')),
                      PopupMenuItem(value: 'both', child: Text('Original + Romanized')),
                      PopupMenuItem(value: 'translated', child: Text('Translated lyrics')),
                    ],
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
