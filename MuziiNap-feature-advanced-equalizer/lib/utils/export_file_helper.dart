import 'dart:io';

/// Returns the first unused export filename in [directory].
///
/// Existing files are preserved; numeric suffixes are added when needed.
Future<File> findAvailableExportFile(
  Directory directory,
  String baseName,
  String extension,
) async {
  var file = File('${directory.path}/$baseName.$extension');
  var counter = 1;

  while (await file.exists()) {
    file = File('${directory.path}/${baseName}_$counter.$extension');
    counter++;
  }

  return file;
}
