class HomeMood {
  const HomeMood({
    required this.title,
    required this.browseId,
    required this.params,
    this.thumbnailUrl,
  });

  final String title;
  final String browseId;
  final String? params;
  final String? thumbnailUrl;

  static HomeMood? fromRenderer(Map<String, dynamic> renderer) {
    String? readText(dynamic value) {
      if (value is String) return value;
      if (value is Map) {
        final simple = value['simpleText'];
        if (simple is String) return simple;
        final runs = value['runs'];
        if (runs is List) {
          return runs
              .whereType<Map>()
              .map((run) => run['text']?.toString() ?? '')
              .join();
        }
      }
      return null;
    }

    Map? findBrowseEndpoint(dynamic value) {
      if (value is Map) {
        final browse = value['browseEndpoint'];
        if (browse is Map &&
            browse['browseId']?.toString().trim().isNotEmpty == true) {
          return browse;
        }
        for (final child in value.values) {
          final found = findBrowseEndpoint(child);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final child in value) {
          final found = findBrowseEndpoint(child);
          if (found != null) return found;
        }
      }
      return null;
    }

    final title = readText(
      renderer['buttonText'] ?? renderer['title'] ?? renderer['accessibilityText'],
    )?.trim();
    final endpoint = findBrowseEndpoint(
      renderer['clickCommand'] ?? renderer['navigationEndpoint'] ?? renderer,
    );
    final browseId = endpoint?['browseId']?.toString().trim();
    final params = endpoint?['params']?.toString();
    final thumbnails = _thumbnailList(renderer);
    final thumbnailUrl = thumbnails is List && thumbnails.isNotEmpty
        ? (thumbnails.last is Map ? thumbnails.last['url']?.toString() : null)
        : null;

    if (title == null ||
        title.isEmpty ||
        browseId == null ||
        browseId.isEmpty) {
      return null;
    }

    return HomeMood(
      title: title,
      browseId: browseId,
      params: params,
      thumbnailUrl: thumbnailUrl,
    );
  }

  static dynamic _thumbnailList(Map<String, dynamic> renderer) {
    final icon = renderer['icon'];
    if (icon is Map) {
      final musicThumbnail = icon['musicThumbnailRenderer'];
      if (musicThumbnail is Map) {
        final thumbnail = musicThumbnail['thumbnail'];
        if (thumbnail is Map) return thumbnail['thumbnails'];
      }
    }
    final thumbnail = renderer['thumbnail'];
    return thumbnail is Map ? thumbnail['thumbnails'] : null;
  }

}
