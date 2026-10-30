import 'dart:io';

import 'package:path/path.dart' as p;

/// Bounds the on-disk LockCachingAudioSource cache without touching files
/// that belong to the active playback queue.
class AudioCacheManager {
  AudioCacheManager._();

  static const int maxCacheBytes = 100 * 1024 * 1024;

  /// Removes the oldest cache entries that are not in [protectedSongIds] until
  /// [maxBytes] is met or only protected entries remain.
  ///
  /// A cache entry includes its completed audio file and any .part/.mime
  /// sidecars. The active queue is protected because LockCachingAudioSource
  /// may still be downloading their partial files.
  static Future<AudioCacheTrimResult> trimDirectory(
    Directory directory, {
    required Set<String> protectedSongIds,
    int maxBytes = maxCacheBytes,
  }) async {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must not be negative');
    }
    if (!await directory.exists()) {
      return const AudioCacheTrimResult(
        totalBytes: 0,
        deletedBytes: 0,
        deletedFiles: 0,
        withinLimit: true,
      );
    }

    final groups = <String, List<File>>{};
    var totalBytes = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final file = entity;
      final size = await file.length();
      totalBytes += size;
      final songId = _songIdFromCacheFile(file.path);
      groups.putIfAbsent(songId, () => <File>[]).add(file);
    }

    if (totalBytes <= maxBytes) {
      return AudioCacheTrimResult(
        totalBytes: totalBytes,
        deletedBytes: 0,
        deletedFiles: 0,
        withinLimit: true,
      );
    }

    final candidates = <_CacheEntry>[];
    for (final entry in groups.entries) {
      if (protectedSongIds.contains(entry.key)) continue;
      var lastModified = DateTime.fromMillisecondsSinceEpoch(0);
      for (final file in entry.value) {
        try {
          final modified = await file.lastModified();
          if (modified.isAfter(lastModified)) lastModified = modified;
        } on FileSystemException {
          // A concurrently removed cache file is ignored during this pass.
        }
      }
      candidates.add(_CacheEntry(entry.value, lastModified));
    }
    candidates.sort(
      (a, b) => a.lastModified.compareTo(b.lastModified),
    );

    var deletedBytes = 0;
    var deletedFiles = 0;
    for (final entry in candidates) {
      for (final file in entry.files) {
        try {
          if (!await file.exists()) continue;
          final size = await file.length();
          await file.delete();
          totalBytes -= size;
          deletedBytes += size;
          deletedFiles++;
        } on FileSystemException {
          // Do not fail playback because another cache operation raced cleanup.
        }
      }
      if (totalBytes <= maxBytes) break;
    }

    return AudioCacheTrimResult(
      totalBytes: totalBytes,
      deletedBytes: deletedBytes,
      deletedFiles: deletedFiles,
      withinLimit: totalBytes <= maxBytes,
    );
  }

  static String _songIdFromCacheFile(String path) {
    var name = p.basename(path);
    if (name.endsWith('.mp3.part')) {
      name = name.substring(0, name.length - '.mp3.part'.length);
    } else if (name.endsWith('.mp3.mime')) {
      name = name.substring(0, name.length - '.mp3.mime'.length);
    } else if (name.endsWith('.mp3')) {
      name = name.substring(0, name.length - '.mp3'.length);
    } else {
      name = p.basenameWithoutExtension(name);
    }
    return name;
  }
}

class AudioCacheTrimResult {
  const AudioCacheTrimResult({
    required this.totalBytes,
    required this.deletedBytes,
    required this.deletedFiles,
    required this.withinLimit,
  });

  final int totalBytes;
  final int deletedBytes;
  final int deletedFiles;
  final bool withinLimit;
}

class _CacheEntry {
  const _CacheEntry(this.files, this.lastModified);

  final List<File> files;
  final DateTime lastModified;
}
