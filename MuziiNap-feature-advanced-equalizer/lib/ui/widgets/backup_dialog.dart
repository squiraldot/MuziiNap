import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../services/constant.dart';

import '../screens/Settings/settings_screen_controller.dart';
import './loader.dart';
import '../../utils/helper.dart';
import 'common_dialog_widget.dart';

class BackupDialog extends StatelessWidget {
  const BackupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final backupDialogController = Get.put(BackupDialogController());
    return CommonDialog(
      child: Container(
        height: GetPlatform.isAndroid ? 350 : 300,
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                child: Text(
                  "backupAppData".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 100,
                  child: Center(
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Obx(() => (backupDialogController.scanning.isTrue ||
                              backupDialogController.backupRunning.isTrue)
                          ? const LoadingIndicator()
                          : const SizedBox.shrink()),
                      const SizedBox(
                        height: 10,
                      ),
                      Column(
                        children: [
                          Obx(() => Text(
                                backupDialogController.errorMessage.isNotEmpty
                                    ? backupDialogController.errorMessage.value
                                    : backupDialogController.scanning.isTrue
                                        ? "scanning".tr
                                    : backupDialogController
                                            .backupRunning.isTrue
                                        ? "backupInProgress".tr
                                        : backupDialogController
                                                .isbackupCompleted.isTrue
                                            ? "backupMsg".tr
                                            : "letsStrart".tr,
                                textAlign: TextAlign.center,
                              )),
                        ],
                      )
                    ],
                  )),
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
                        if (backupDialogController.isbackupCompleted.isTrue) {
                          Navigator.of(context).pop();
                        } else {
                          backupDialogController.backup();
                        }
                      },
                      child: Obx(
                        () => Visibility(
                          visible:
                              !(backupDialogController.backupRunning.isTrue ||
                                  backupDialogController.scanning.isTrue),
                          replacement: const SizedBox(
                            height: 40,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15.0, vertical: 10),
                            child: Obx(
                              () => Text(
                                backupDialogController.isbackupCompleted.isTrue
                                    ? "close".tr
                                    : "backup".tr,
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

class BackupDialogController extends GetxController {
  final scanning = false.obs;
  final isbackupCompleted = false.obs;
  final backupRunning = false.obs;
  final isDownloadedfilesSeclected = true.obs;
  final errorMessage = ''.obs;
  List<String> filesToExport = [];
  final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;

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

  Map<String, dynamic> _jsonSafeMap(Box box) {
    final result = <String, dynamic>{};
    for (final key in box.keys) {
      if (key is! String || _isSensitivePreference(key)) continue;
      final value = box.get(key);
      try {
        jsonEncode(value);
        result[key] = value;
      } catch (_) {
        // Skip values that cannot be represented in the backup JSON format.
      }
    }
    return result;
  }

  Future<Map<String, List<int>>> _collectBackupEntries() async {
    final entries = <String, List<int>>{};
    final prefs = Hive.box(appPrefsBoxName);
    entries['data/settings.json'] =
        utf8.encode(jsonEncode(_jsonSafeMap(prefs)));

    final favoritesBox = await Hive.openBox('LIBFAV');
    entries['data/favorites.json'] =
        utf8.encode(jsonEncode(favoritesBox.values.toList()));
    await favoritesBox.close();

    final downloadsBox = await Hive.openBox('SongDownloads');
    final downloads = <Map<String, dynamic>>[];
    for (final raw in downloadsBox.values) {
      if (raw is! Map) continue;
      final song = Map<String, dynamic>.from(raw);
      final originalPath = song['url'];
      if (originalPath is String &&
          originalPath.isNotEmpty) {
        final songFile = File(originalPath);
        if (await songFile.exists()) {
          final name = originalPath.split(Platform.pathSeparator).last;
          final archivePath = 'files/Music/$name';
          entries[archivePath] = await songFile.readAsBytes();
          song['url'] = archivePath;
          final streamInfo = song['streamInfo'];
          if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
            streamInfo[1]['url'] = archivePath;
          }
        }
      }
      downloads.add(song);
    }
    entries['data/downloads.json'] = utf8.encode(jsonEncode(downloads));
    await downloadsBox.close();

    final playlistsBox = await Hive.openBox('LibraryPlaylists');
    final localPlaylists = <Map<String, dynamic>>[];
    for (final raw in playlistsBox.values) {
      if (raw is! Map) continue;
      final playlist = Map<String, dynamic>.from(raw);
      final id = playlist['playlistId']?.toString() ?? '';
      if (!id.startsWith('LIB') ||
          id == 'LIBFAV' ||
          id == 'LIBRP' ||
          id == 'LIB' ||
          playlist['isCloudPlaylist'] == true ||
          playlist['isPipedPlaylist'] == true) {
        continue;
      }
      localPlaylists.add(playlist);
      final playlistBox = await Hive.openBox(id);
      entries['data/playlist_songs/$id.json'] =
          utf8.encode(jsonEncode(playlistBox.values.toList()));
      await playlistBox.close();
    }
    entries['data/playlists.json'] = utf8.encode(jsonEncode(localPlaylists));
    await playlistsBox.close();

    entries['manifest.json'] = utf8.encode(jsonEncode({
      'format': 'muziinap',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'contents': [
        'settings',
        'favorites',
        'downloads',
        'playlists',
      ],
    }));
    return entries;
  }

  Future<void> backup() async {
    if (scanning.value || backupRunning.value) return;
    errorMessage.value = '';
    Directory? temporaryDirectory;
    try {
      scanning.value = true;
      final entries = await _collectBackupEntries();
      backupRunning.value = true;
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final fileName = 'muziinap-backup-$date.muziinap';
      final archive = Archive();
      for (final entry in entries.entries) {
        archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
      }
      final archiveBytes = ZipEncoder().encode(archive);
      if (archiveBytes == null || archiveBytes.isEmpty) {
        throw Exception('Backup archive could not be created.');
      }

      if (GetPlatform.isAndroid) {
        temporaryDirectory = await Directory.systemTemp.createTemp('muziinap-backup-');
        final temporaryArchive = File('${temporaryDirectory.path}/$fileName');
        await temporaryArchive.writeAsBytes(archiveBytes, flush: true);
        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save backup file',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['muziinap'],
          bytes: Uint8List.fromList(archiveBytes),
        );
        if (savedPath == null || savedPath.isEmpty) {
          errorMessage.value = 'Backup cancelled; no file was saved.';
          return;
        }
      } else {
        final pickedFolderPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select backup file folder',
        );
        if (pickedFolderPath == null || pickedFolderPath.isEmpty) return;
        final output = File('$pickedFolderPath/$fileName');
        await output.writeAsBytes(archiveBytes, flush: true);
        if (!await output.exists() || await output.length() == 0) {
          throw Exception('Backup file was not created.');
        }
      }
      isbackupCompleted.value = true;
    } catch (e) {
      errorMessage.value = 'Backup failed: $e';
      printERROR(errorMessage.value);
    } finally {
      scanning.value = false;
      backupRunning.value = false;
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (e) {
          printERROR('Could not clean temporary backup files: $e');
        }
      }
    }
  }
}

// Function to convert file paths to base64-encoded file data
List<String> filePathsToBase64(List<String> filePaths) {
  List<String> base64Data = [];

  for (String path in filePaths) {
    try {
      // Read the file data as bytes
      File file = File(path);
      List<int> fileData = file.readAsBytesSync();
      // Convert bytes to base64
      String base64String = base64Encode(fileData);
      base64Data.add(base64String);
    } catch (e) {
      printERROR('Error reading file $path: $e');
    }
  }

  return base64Data;
}

// Function to convert file paths to file data (List<int>)
List<List<int>> filePathsToFileData(List<String> filePaths) {
  List<List<int>> filesData = [];

  for (String path in filePaths) {
    try {
      // Read the file data as bytes
      File file = File(path);
      List<int> fileData = file.readAsBytesSync();
      filesData.add(fileData);
    } catch (e) {
      printERROR('Error reading file $path: $e');
    }
  }

  return filesData;
}

// Function to compress files (to be used with compute or isolate)
void _compressFiles(Map<String, dynamic> params) {
  final List<List<int>> filesData = params['filesData'];
  final List<String> fileNames = params['fileNames'];
  final String zipFilePath = params['zipFilePath'];

  final archive = Archive();

  for (int i = 0; i < filesData.length; i++) {
    final fileData = filesData[i];
    final fileName = fileNames[i];
    final file = ArchiveFile(fileName, fileData.length, fileData);
    archive.addFile(file);
  }

  final encoder = ZipEncoder();
  final zipFile = File(zipFilePath);
  zipFile.writeAsBytesSync(encoder.encode(archive)!);
}

// Example usage
Future<void> compressFilesInBackground(
    List<String> filePaths, String zipFilePath) async {
  // Convert file paths to file data
  final List<List<int>> filesData = filePathsToFileData(filePaths);
  final List<String> fileNames = filePaths
      .map((path) => path.split(Platform.pathSeparator).last)
      .toList();

  printINFO(fileNames);
  // Use compute to run the compression in the background
  await compute(_compressFiles, {
    'filesData': filesData,
    'fileNames': fileNames,
    'zipFilePath': zipFilePath,
  });
}

Future<List<String>> processDirectoryInIsolate(String dbDir,
    {String extensionFilter = ".hive"}) async {
  // Use Isolate.run to execute the function in a new isolate
  return await Isolate.run(() async {
    // List files in the directory
    final filesEntityList =
        await Directory(dbDir).list(recursive: false).toList();

    // Filter out .hive files
    final filesPath = filesEntityList
        .whereType<File>() // Ensure we only work with files
        .map((entity) {
          if (entity.path.endsWith(extensionFilter)) return entity.path;
        })
        .whereType<String>()
        .toList();

    return filesPath;
  });
}
