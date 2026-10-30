import 'package:isar_community/isar.dart';

part 'local_library_models.g.dart';

/// A downloaded audio file indexed independently from its on-disk metadata.
///
/// [id] is the stable source ID (for example, a YouTube video ID). [isarId]
/// is Isar's internal integer primary key.
@collection
class DownloadedSong {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String id;

  @Index(type: IndexType.value)
  late String title;

  @Index(type: IndexType.value)
  late String artist;

  late String localFilePath;

  /// Duration in milliseconds, matching just_audio's Duration representation.
  late int duration;

  @Index()
  late DateTime timestamp;

  /// Reverse side of LocalPlaylist.songs (many playlists can contain a song).
  @Backlink(to: 'songs')
  final playlists = IsarLinks<LocalPlaylist>();
}

/// User-created playlist with a many-to-many relation to downloaded songs.
@collection
class LocalPlaylist {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String playlistId;

  @Index(type: IndexType.value)
  late String title;

  /// A song may belong to multiple playlists; a playlist may contain
  /// multiple songs. Persist link changes in the same write transaction.
  final songs = IsarLinks<DownloadedSong>();
}
