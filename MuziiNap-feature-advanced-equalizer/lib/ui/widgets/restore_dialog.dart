import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../services/constant.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '../../utils/helper.dart';
import 'common_dialog_widget.dart';

class RestoreDialog extends StatelessWidget {
  const RestoreDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final restoreDialogController = Get.put(RestoreDialogController());
    return CommonDialog(
      child: Container(
        height: 300,
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                child: Text(
                  "restoreAppData".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SizedBox(
                height: 150,
                child: Center(
                  child: Obx(() => restoreDialogController.errorMessage.isNotEmpty
                      ? Text(restoreDialogController.errorMessage.value, textAlign: TextAlign.center)
                      : restoreDialogController.restoreProgress.toInt() ==
                          restoreDialogController.filesToRestore.toInt() &&
                          restoreDialogController.filesToRestore.value > 0
                      ? Text(
                          "restoreMsg".tr,
                          textAlign: TextAlign.center,
                        )
                      : restoreDialogController.processingFiles.isTrue
                          ? Text("processFiles".tr)
                          : restoreDialogController.restoreRunning.isTrue
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                        "${restoreDialogController.restoreProgress.toInt()}/${restoreDialogController.filesToRestore.toInt()}",
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(
                                      height: 10,
                                    ),
                                    Text("restoring".tr)
                                  ],
                                )
                              : Text("letsStrart".tr)),
                ),
              ),
              SizedBox(
                width: double.maxFinite,
                child: Align(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      onTap: () {
                        if (restoreDialogController.restoreProgress.toInt() ==
                            restoreDialogController.filesToRestore.toInt()) {
                          GetPlatform.isAndroid
                              ? TerminateRestart.instance.restartApp(
                                  options: const TerminateRestartOptions(
                                    terminate: true,
                                  ),
                                )
                              : exit(0);
                        } else {
                          restoreDialogController.restore();
                        }
                      },
                      child: Obx(
                        () => Visibility(
                          visible: restoreDialogController
                                  .processingFiles.isFalse &&
                              restoreDialogController.restoreRunning.isFalse,
                          replacement: const SizedBox(
                            height: 40,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15.0, vertical: 10),
                            child: Obx(
                              () => Text(
                                restoreDialogController.restoreProgress
                                            .toInt() ==
                                        restoreDialogController.filesToRestore
                                            .toInt()
                                    ? "restartApp".tr
                                    : "restore".tr,
                                style: TextStyle(
                                    color: Theme.of(context).canvasColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class RestoreDialogController extends GetxController {
  final restoreRunning = false.obs;
  final restoreProgress = (-1).obs;
  final filesToRestore = (0).obs;
  final processingFiles = false.obs;
  final errorMessage = ''.obs;

  bool _isSensitivePreference(String key) {
    final normalized = key.toLowerCase();
    return normalized.startsWith('yt_') ||
        normalized.contains('youtube') ||
        normalized.contains('cookie') ||
        normalized.contains('auth') ||
        normalized.contains('session') ||
        normalized.contains('identitytoken') ||
        normalized.contains('datasync') ||
        normalized.contains('visitor') ||
        normalized == 'piped';
  }

  Future<void> restore() async {
    if (processingFiles.value || restoreRunning.value) return;
    errorMessage.value = '';
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select MuziiNap backup file',
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final restoreFilePath = result.files.first.path!;
      if (!restoreFilePath.toLowerCase().endsWith('.muziinap')) {
        errorMessage.value = 'Unsupported file. Please select a .muziinap backup.';
        return;
      }

      processingFiles.value = true;
      final bytes = await File(restoreFilePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final files = archive.files.where((file) => file.isFile).toList();
      final entries = <String, List<int>>{
        for (final file in files) file.name: file.content as List<int>,
      };
      if (!entries.containsKey('manifest.json') ||
          !entries.containsKey('data/settings.json') ||
          !entries.containsKey('data/favorites.json') ||
          !entries.containsKey('data/downloads.json') ||
          !entries.containsKey('data/playlists.json')) {
        throw const FormatException('The selected file is not a valid MuziiNap backup.');
      }
      final manifest = jsonDecode(utf8.decode(entries['manifest.json']!));
      if (manifest is! Map ||
          manifest['format'] != 'muziinap' ||
          manifest['version'] != 1) {
        throw const FormatException('Unsupported or invalid MuziiNap backup format.');
      }

      final settings = Get.find<SettingsScreenController>();
      final supportDirPath = settings.supportDirPath;
      final settingsData = jsonDecode(utf8.decode(entries['data/settings.json']!));
      final favoritesData = jsonDecode(utf8.decode(entries['data/favorites.json']!));
      final downloadsData = jsonDecode(utf8.decode(entries['data/downloads.json']!));
      final playlistsData = jsonDecode(utf8.decode(entries['data/playlists.json']!));
      if (settingsData is! Map ||
          favoritesData is! List ||
          downloadsData is! List ||
          playlistsData is! List) {
        throw const FormatException('Backup data is invalid.');
      }

      processingFiles.value = false;
      restoreRunning.value = true;
      restoreProgress.value = 0;
      filesToRestore.value = 4 + playlistsData.length +
          entries.keys.where((key) => key.startsWith('files/Music/')).length;

      // Restore only safe preferences. Never import YouTube authentication,
      // cookies, session tokens, or account-linked settings.
      final prefsBox = Hive.box(appPrefsBoxName);
      for (final entry in settingsData.entries) {
        final key = entry.key.toString();
        if (!_isSensitivePreference(key)) {
          await prefsBox.put(key, entry.value);
        }
      }
      restoreProgress.value++;

      final favoritesBox = await Hive.openBox('LIBFAV');
      await favoritesBox.clear();
      for (var i = 0; i < favoritesData.length; i++) {
        await favoritesBox.put(i, favoritesData[i]);
      }
      await favoritesBox.close();
      restoreProgress.value++;

      final musicDir = Directory('$supportDirPath/Music');
      await musicDir.create(recursive: true);
      final downloadsBox = await Hive.openBox('SongDownloads');
      await downloadsBox.clear();
      for (final raw in downloadsData) {
        if (raw is! Map) continue;
        final song = Map<String, dynamic>.from(raw);
        final storedPath = song['url'];
        if (storedPath is String && storedPath.startsWith('files/Music/')) {
          final archiveName = storedPath;
          final data = entries[archiveName];
          final fileName = archiveName.split('/').last;
          if (data != null && fileName.isNotEmpty) {
            final output = File('$supportDirPath/Music/$fileName');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(data, flush: true);
            song['url'] = output.path;
            final streamInfo = song['streamInfo'];
            if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
              streamInfo[1]['url'] = output.path;
            }
          }
        }
        final id = song['videoId'] ?? song['id'];
        if (id != null) await downloadsBox.put(id, song);
      }
      await downloadsBox.close();
      restoreProgress.value++;

      final playlistsBox = await Hive.openBox('LibraryPlaylists');
      final oldLocalIds = <String>[];
      for (final raw in playlistsBox.values) {
        if (raw is Map) {
          final id = raw['playlistId']?.toString() ?? '';
          if (id.startsWith('LIB') &&
              id != 'LIBFAV' &&
              id != 'LIBRP' &&
              raw['isCloudPlaylist'] != true &&
              raw['isPipedPlaylist'] != true) {
            oldLocalIds.add(id);
          }
        }
      }
      for (final id in oldLocalIds) {
        await playlistsBox.delete(id);
        if (await Hive.boxExists(id)) {
          final oldSongsBox = await Hive.openBox(id);
          await oldSongsBox.clear();
          await oldSongsBox.close();
        }
      }
      for (final raw in playlistsData) {
        if (raw is! Map) continue;
        final playlist = Map<String, dynamic>.from(raw);
        final id = playlist['playlistId']?.toString() ?? '';
        if (!id.startsWith('LIB') ||
            id == 'LIBFAV' ||
            id == 'LIBRP' ||
            playlist['isCloudPlaylist'] == true ||
            playlist['isPipedPlaylist'] == true) {
          continue;
        }
        await playlistsBox.put(id, playlist);
        final songsEntry = entries['data/playlist_songs/$id.json'];
        if (songsEntry != null) {
          final songs = jsonDecode(utf8.decode(songsEntry));
          if (songs is List) {
            final songsBox = await Hive.openBox(id);
            await songsBox.clear();
            for (var i = 0; i < songs.length; i++) {
              await songsBox.put(i, songs[i]);
            }
            await songsBox.close();
          }
        }
        restoreProgress.value++;
      }
      await playlistsBox.close();
      restoreProgress.value++;
      await settings.closeAllDatabases();
      restoreProgress.value = filesToRestore.value;
    } catch (e) {
      errorMessage.value = 'Restore failed: $e';
      printERROR(errorMessage.value);
    } finally {
      processingFiles.value = false;
      restoreRunning.value = false;
    }
  }}
