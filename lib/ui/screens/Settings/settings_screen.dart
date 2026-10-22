import 'package:flutter/material.dart';
import '../../../services/constant.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import '../../../utils/lang_mapping.dart';

import '../../widgets/common_dialog_widget.dart';
import '../../widgets/cust_switch.dart';
import '../../widgets/export_file_dialog.dart';
import '../../widgets/backup_dialog.dart';
import '../../widgets/restore_dialog.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '../Home/home_screen_controller.dart';
import '../../../services/music_service.dart';
import 'advanced_equalizer_screen.dart';
import 'about_screen.dart';
import '../../utils/theme_controller.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';
import '../../player/player_controller.dart';
import 'youtube_login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? EdgeInsets.only(left: 20, top: topPadding, right: 15)
          : EdgeInsets.only(top: topPadding, left: 5, right: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "settings".tr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
              child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 200, top: 20),
            children: [
              Offstage(
                offstage: true,
                child: CustomExpansionTile(
                  title: "personalisation".tr,
                  icon: Icons.palette,
                  children: [
                  Offstage(
                    offstage: true,
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("language".tr),
                      subtitle: Text("languageDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => DropdownButton(
                          menuMaxHeight: Get.height - 250,
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          style: Theme.of(context).textTheme.titleSmall,
                          value: settingsController.currentAppLanguageCode.value,
                          items: langMap.entries.map((lang) => DropdownMenuItem(
                            value: lang.key, child: Text(lang.value),
                          )).whereType<DropdownMenuItem<String>>().toList(),
                          selectedItemBuilder: (context) => langMap.entries.map<Widget>((item) =>
                            Container(
                              alignment: Alignment.centerRight,
                              constraints: const BoxConstraints(minWidth: 50),
                              child: Text(item.value),
                            )).toList(),
                          onChanged: settingsController.setAppLanguage,
                        ),
                      ),
                    ),
                  ),
                  Offstage(
                      offstage: true,
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 5, right: 10),
                        title: Text("playerUi".tr),
                        subtitle: Text("playerUiDes".tr, style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(() => DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.playerUi.value,
                          items: [
                            DropdownMenuItem(value: 0, child: Text("standard".tr)),
                            DropdownMenuItem(value: 1, child: Text("gesture".tr)),
                          ],
                          onChanged: settingsController.setPlayerUi,
                        )),
                      ),
                    ),
                  Offstage(
                      offstage: true,
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 5, right: 10),
                        title: Text("enableBottomNav".tr),
                        subtitle: Text("enableBottomNavDes".tr, style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(() => CustSwitch(
                          value: settingsController.isBottomNavBarEnabled.isTrue,
                          onChanged: settingsController.enableBottomNavBar,
                        )),
                      ),
                    ),
                  Offstage(
                    offstage: true,
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("disableTransitionAnimation".tr),
                      subtitle: Text("disableTransitionAnimationDes".tr, style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(() => CustSwitch(
                        value: settingsController.isTransitionAnimationDisabled.isTrue,
                        onChanged: settingsController.disableTransitionAnimation,
                      )),
                    ),
                  ),
                  Offstage(
                    offstage: true,
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("enableSlidableAction".tr),
                      subtitle: Text("enableSlidableActionDes".tr, style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(() => CustSwitch(
                        value: settingsController.slidableActionEnabled.isTrue,
                        onChanged: settingsController.toggleSlidableAction,
                      )),
                    ),
                  ),
                  ],
                ),
              ),
              CustomExpansionTile(
                  title: "YouTube Account",
                  icon: Icons.account_circle,
                  children: [
                    StatefulBuilder(
                      builder: (context, setState) {
                        final box = Hive.box(appPrefsBoxName);
                        final isLoggedIn =
                            box.get('yt_logged_in', defaultValue: false) == true;
                        final activeKey =
                            box.get('yt_active_account_key')?.toString();
                        final rawAccounts = box.get('yt_accounts');
                        final accounts = rawAccounts is Map
                            ? rawAccounts.map(
                                (key, value) => MapEntry(key.toString(), value),
                              )
                            : <String, dynamic>{};

                        return Column(
                          children: [
                            if (accounts.isNotEmpty)
                              ...accounts.keys.map((key) {
                                final accountNumber =
                                    accounts.keys.toList().indexOf(key) + 1;
                                final isActive = key == activeKey;
                                final accountData = accounts[key] is Map
                                    ? Map<String, dynamic>.from(
                                        accounts[key] as Map,
                                      )
                                    : <String, dynamic>{};
                                final accountName = accountData['accountName']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ==
                                    true
                                    ? accountData['accountName'].toString().trim()
                                    : 'YouTube account $accountNumber';
                                final accountPhotoUrl = accountData[
                                            'accountPhotoUrl']
                                        ?.toString()
                                        .trim() ??
                                    '';
                                return ListTile(
                                  contentPadding: const EdgeInsets.only(
                                      left: 5, right: 10),
                                  leading: Icon(
                                    isActive
                                        ? Icons.check_circle
                                        : Icons.account_circle_outlined,
                                  ),
                                  title: Row(
                                    children: [
                                      ClipOval(
                                        child: accountPhotoUrl.isNotEmpty
                                            ? Image.network(
                                                accountPhotoUrl,
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                  Icons.account_circle,
                                                  size: 40,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.account_circle,
                                                size: 40,
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          accountName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    isActive
                                        ? 'Active account'
                                        : 'Saved account',
                                  ),
                                  trailing: isActive
                                      ? const SizedBox.shrink()
                                      : TextButton(
                                          child: const Text('Switch'),
                                          onPressed: () async {
                                            final service =
                                                Get.find<MusicServices>();
                                            final switched = await service
                                                .activateYouTubeAccount(key);
                                            if (!switched) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  snackbar(
                                                    context,
                                                    'Could not activate this YouTube account',
                                                    size: SanckBarSize.BIG,
                                                  ),
                                                );
                                              }
                                              return;
                                            }
                                            if (Get.isRegistered<
                                                HomeScreenController>()) {
                                              await Get.find<
                                                      HomeScreenController>()
                                                  .refreshHome();
                                            }
                                            if (Get.isRegistered<
                                                LibraryPlaylistsController>()) {
                                              Get.find<
                                                      LibraryPlaylistsController>()
                                                  .refreshLib();
                                            }
                                            setState(() {});
                                          },
                                        ),
                                );
                              }),
                            ListTile(
                              contentPadding:
                                  const EdgeInsets.only(left: 5, right: 10),
                              title: Text(
                                isLoggedIn
                                    ? "Connected to YouTube"
                                    : "Sign in to YouTube",
                              ),
                              subtitle: Text(
                                isLoggedIn
                                    ? "Account sessions are saved for quick switching"
                                    : "Log in to sync account preferences & personalized recommendations",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              trailing: TextButton(
                                child: Text(
                                  isLoggedIn ? "Disconnect" : "Login",
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .copyWith(fontSize: 15),
                                ),
                                onPressed: () async {
                                  if (isLoggedIn) {
                                    await box.delete('yt_accounts');
                                    await box.delete('yt_active_account_key');
                                    await box.delete('yt_cookies');
                                    await box.put('yt_logged_in', false);
                                    if (Get.isRegistered<MusicServices>()) {
                                      Get.find<MusicServices>()
                                          .clearAuthCookies();
                                    }
                                    if (Get.isRegistered<
                                        HomeScreenController>()) {
                                      await Get.find<HomeScreenController>()
                                          .refreshHome();
                                    }
                                    setState(() {});
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        snackbar(
                                          context,
                                          "Disconnected from YouTube",
                                          size: SanckBarSize.BIG,
                                        ),
                                      );
                                    }
                                  } else {
                                    final result = await Get.to(
                                        () => const YoutubeLoginScreen());
                                    if (result == true) {
                                      setState(() {});
                                    }
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ]),
              CustomExpansionTile(
                title: 'Lyrics Preference',
                icon: Icons.lyrics_outlined,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    leading: const Icon(Icons.text_fields),
                    title: const Text('Set Fonts on Lyrics'),
                    subtitle: const Text(
                      'Choose font, preview styles, size and bold active lyrics',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showLyricsAppearanceSettings(context),
                  ),
                ],
              ),
              CustomExpansionTile(
                title: "music&Playback".tr,
                icon: Icons.music_note,
                children: [
                  ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("equalizer".tr),
                      subtitle: Text("equalizerDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      onTap: () {
                        Get.to(() => const AdvancedEqualizerScreen());
                      },
                    ),
                  GetPlatform.isAndroid
                      ? Obx(
                          () => ListTile(
                            contentPadding:
                                const EdgeInsets.only(left: 5, right: 10),
                            title: Text("ignoreBatOpt".tr),
                            onTap: settingsController
                                    .isIgnoringBatteryOptimizations.isFalse
                                ? settingsController
                                    .enableIgnoringBatteryOptimizations
                                : null,
                            subtitle: Obx(() => RichText(
                                  text: TextSpan(
                                    text:
                                        "${"status".tr}: ${settingsController.isIgnoringBatteryOptimizations.isTrue ? "enabled".tr : "disabled".tr}\n",
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .copyWith(fontWeight: FontWeight.bold),
                                    children: <TextSpan>[
                                      TextSpan(
                                          text: "ignoreBatOptDes".tr,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium),
                                    ],
                                  ),
                                )),
                          ),
                        )
                      : const SizedBox.shrink(),
                ],
              ),
              CustomExpansionTile(
                title: "download".tr,
                icon: Icons.download,
                children: [
                  if (GetPlatform.isAndroid)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("exportDowloadedFiles".tr),
                      subtitle: Text(
                        "exportDowloadedFilesDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const ExportFileDialog(),
                      ).whenComplete(
                          () => Get.delete<ExportFileDialogController>()),
                    ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("exportedFileLocation".tr),
                      subtitle: Obx(() => Text(
                          settingsController.exportLocationPath.value,
                          style: Theme.of(context).textTheme.bodyMedium)),
                      onTap: () async {
                        settingsController.setExportedLocation();
                      },
                    ),
                ],
              ),
              CustomExpansionTile(
                  title: "${"backup".tr} & ${"restore".tr}",
                  icon: Icons.restore,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("backupAppData".tr),
                      subtitle: Text(
                        "backupSettingsAndPlaylistsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const BackupDialog(),
                      ).whenComplete(
                          () => Get.delete<BackupDialogController>()),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("restoreAppData".tr),
                      subtitle: Text(
                        "restoreSettingsAndPlaylistsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const RestoreDialog(),
                      ).whenComplete(
                          () => Get.delete<RestoreDialogController>()),
                    ),
                  ]),

              ListTile(
                contentPadding: const EdgeInsets.only(left: 5, right: 10),
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text("About"),
                subtitle: const Text(
                  "About MuziiNap and the project",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.to(() => const AboutScreen()),
              ),
            ],
          )),
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Text(
              "${settingsController.currentVersion} ${"by".tr} Merrmist\n(Forked from squiraldot)",
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 300,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "themeMode".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          radioWidget(
            label: "dynamic".tr,
            controller: settingsController,
            value: ThemeType.dynamic,
          ),
          radioWidget(
              label: "systemDefault".tr,
              controller: settingsController,
              value: ThemeType.system),
          radioWidget(
              label: "dark".tr,
              controller: settingsController,
              value: ThemeType.dark),
          radioWidget(
              label: "light".tr,
              controller: settingsController,
              value: ThemeType.light),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

class DiscoverContentSelectorDialog extends StatelessWidget {
  const DiscoverContentSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 300,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "setDiscoverContent".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  radioWidget(
                      label: "quickpicks".tr,
                      controller: settingsController,
                      value: "QP"),
                  radioWidget(
                      label: "topmusicvideos".tr,
                      controller: settingsController,
                      value: "TMV"),
                  radioWidget(
                      label: "trending".tr,
                      controller: settingsController,
                      value: "TR"),
                  radioWidget(
                      label: "basedOnLast".tr,
                      controller: settingsController,
                      value: "BOLI"),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

Widget radioWidget(
    {required String label,
    required SettingsScreenController controller,
    required value}) {
  return Obx(() => ListTile(
        visualDensity: const VisualDensity(vertical: -4),
        onTap: () {
          if (value.runtimeType == ThemeType) {
            controller.onThemeChange(value);
          } else {
            controller.onContentChange(value);
            Navigator.of(Get.context!).pop();
          }
        },
        leading: RadioGroup(
            groupValue: value.runtimeType == ThemeType
                ? controller.themeModetype.value
                : controller.discoverContentType.value,
            onChanged: value.runtimeType == ThemeType
                ? controller.onThemeChange
                : controller.onContentChange,
            child: Radio(
                value: value),
        ),
        title: Text(label),
      ));
}

Future<void> _showLyricsAppearanceSettings(BuildContext context) async {
  final controller = Get.find<PlayerController>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
          ),
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
                  Expanded(
                    child: Text(
                      'Lyrics appearance',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ]),
                Row(children: [
                  Expanded(child: Text('Active lyric size', style: Theme.of(sheetContext).textTheme.bodyMedium)),
                  Text('${activeSize.round()} px', style: Theme.of(sheetContext).textTheme.bodyMedium),
                ]),
                Slider(
                  min: 16,
                  max: 36,
                  divisions: 20,
                  value: activeSize,
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
                                    Text(font, style: Theme.of(context).textTheme.bodyMedium),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Sitting in the music, feel every word',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _lyricsFontPreviewStyle(
                                        font,
                                        size: Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14,
                                        weight: isBold ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                selected ? Icons.check_circle : Icons.circle_outlined,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).hintColor,
                              ),
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

TextStyle _lyricsFontPreviewStyle(
  String font, {
  required double size,
  required FontWeight weight,
}) {
  if (font == 'Poppins') {
    return GoogleFonts.poppins(fontSize: size, fontWeight: weight);
  }
  return TextStyle(
    fontFamily: font == 'System' ? null : font,
    fontSize: size,
    fontWeight: weight,
  );
}
