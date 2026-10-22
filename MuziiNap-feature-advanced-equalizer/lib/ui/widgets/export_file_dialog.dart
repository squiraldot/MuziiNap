import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../screens/Settings/settings_screen_controller.dart';
import './loader.dart';

import 'common_dialog_widget.dart';

class ExportFileDialog extends StatelessWidget {
  const ExportFileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final exportFileDialogController = Get.put(ExportFileDialogController());
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
                  "exportDowloadedFiles".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SizedBox(
                height: 150,
                child: Center(
                  child: Obx(() => exportFileDialogController.errorMessage.isNotEmpty
                      ? Text(exportFileDialogController.errorMessage.value,
                          textAlign: TextAlign.center)
                      : exportFileDialogController.exportProgress.toInt() >= 0 &&
                              exportFileDialogController.exportProgress.toInt() ==
                                  exportFileDialogController.filesToExport.length
                      ? Text("exportMsg".tr)
                      : exportFileDialogController.exportRunning.isTrue
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                    "${exportFileDialogController.exportProgress.toInt()}/${exportFileDialogController.filesToExport.length}",
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(
                                  height: 10,
                                ),
                                Text("exporting".tr)
                              ],
                            )
                          : exportFileDialogController.ready.isTrue
                              ? Text(
                                  "${exportFileDialogController.filesToExport.length} ${"downFilesFound".tr}")
                              : exportFileDialogController.scanning.isTrue
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const LoadingIndicator(),
                                        const SizedBox(
                                          height: 10,
                                        ),
                                        Text("scanning".tr)
                                      ],
                                    )
                                  : const SizedBox()),
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
                        if (exportFileDialogController.exportProgress.toInt() >= 0 &&
                            exportFileDialogController.exportProgress.toInt() ==
                                exportFileDialogController.filesToExport.length) {
                          Navigator.of(context).pop();
                        } else {
                          exportFileDialogController.export();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15.0, vertical: 10),
                        child: Obx(
                          () => Text(
                            exportFileDialogController.exportProgress.toInt() ==
                                    exportFileDialogController
                                        .filesToExport.length
                                ? "close".tr
                                : "export".tr,
                            style:
                                TextStyle(color: Theme.of(context).canvasColor),
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

class ExportFileDialogController extends GetxController {
  final scanning = true.obs;
  final ready = false.obs;
  final exportRunning = false.obs;
  final exportProgress = (-1).obs;
  final errorMessage = ''.obs;
  List<String> filesToExport = [];

  @override
  void onInit() {
    scanFilesToExport();
    super.onInit();
  }

  Future<void> scanFilesToExport() async {
    scanning.value = true;
    errorMessage.value = '';
    try {
      final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;
      final musicDir = Directory('${supportDirPath}/Music');
      filesToExport = await musicDir.exists()
          ? (await musicDir.list(followLinks: false).toList())
              .whereType<File>()
              .map((file) => file.path)
              .toList()
          : <String>[];
      ready.value = true;
    } catch (e) {
      errorMessage.value = 'Could not scan downloaded files: $e';
      print(errorMessage.value);
    } finally {
      scanning.value = false;
    }
  }

  Future<void> export() async {
    if (exportRunning.value) return;
    errorMessage.value = '';
    if (filesToExport.isEmpty) {
      errorMessage.value = 'No downloaded files were found.';
      return;
    }
    exportRunning.value = true;
    exportProgress.value = 0;
    try {
      final controller = Get.find<SettingsScreenController>();
      final exportDir = Directory(controller.exportLocationPath.value);
      await exportDir.create(recursive: true);
      for (final filePath in filesToExport) {
        final source = File(filePath);
        if (!await source.exists()) {
          exportProgress.value++;
          continue;
        }
        final fileName = filePath.split(Platform.pathSeparator).last;
        var destination = File('${exportDir.path}/$fileName');
        if (await destination.exists()) {
          final dot = fileName.lastIndexOf('.');
          final base = dot > 0 ? fileName.substring(0, dot) : fileName;
          final extension = dot > 0 ? fileName.substring(dot) : '';
          var suffix = 1;
          do {
            destination = File('${exportDir.path}/$base ($suffix)$extension');
            suffix++;
          } while (await destination.exists());
        }
        await source.copy(destination.path);
        exportProgress.value++;
      }
    } catch (e) {
      errorMessage.value = 'Export failed: $e';
      print(errorMessage.value);
    } finally {
      exportRunning.value = false;
    }
  }
}
