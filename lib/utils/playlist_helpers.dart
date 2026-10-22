/// Finds a song's positional index in a Hive playlist values iterable.
///
/// Returns -1 when the song is no longer present. Callers must check the
/// result before using it with positional deletion APIs such as Hive.deleteAt.
int findStoredSongIndexById(Iterable<dynamic> storedSongs, String songId) {
  var index = 0;
  for (final entry in storedSongs) {
    if (entry is Map && entry['videoId'] == songId) {
      return index;
    }
    index++;
  }
  return -1;
}
