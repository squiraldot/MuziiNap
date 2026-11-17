/// Locates the section list that contains YouTube Music Home shelves.
///
/// YouTube may return Home in the legacy single-column tab renderer or wrap
/// it in a two-column browse renderer. Prefer the visible tab content and
/// ignore response metadata so an unrelated section list is never selected.
Map<String, dynamic>? findHomeSectionList(dynamic value) {
  if (value is Map) {
    final renderer = value['sectionListRenderer'];
    if (renderer is Map && renderer['contents'] is List) {
      return Map<String, dynamic>.from(renderer);
    }

    const preferredKeys = [
      'tabs',
      'tabRenderer',
      'content',
      'singleColumnBrowseResultsRenderer',
      'twoColumnBrowseResultsRenderer',
      'primaryContents',
      'secondaryContents',
      'contents',
    ];

    for (final key in preferredKeys) {
      final child = value[key];
      if (child is Map || child is List) {
        final found = findHomeSectionList(child);
        if (found != null) return found;
      }
    }

    for (final entry in value.entries) {
      if (const {
        'responseContext',
        'trackingParams',
        'frameworkUpdates',
      }.contains(entry.key)) {
        continue;
      }
      final child = entry.value;
      if (child is Map || child is List) {
        final found = findHomeSectionList(child);
        if (found != null) return found;
      }
    }
  } else if (value is List) {
    for (final child in value) {
      final found = findHomeSectionList(child);
      if (found != null) return found;
    }
  }
  return null;
}
