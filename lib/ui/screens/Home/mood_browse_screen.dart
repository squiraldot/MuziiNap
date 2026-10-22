import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/album.dart';
import '../../../models/home_mood.dart';
import '../../../models/playlist.dart';
import '../../../models/quick_picks.dart';
import '../../../services/music_service.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/quickpickswidget.dart';

class MoodBrowseScreen extends StatefulWidget {
  const MoodBrowseScreen({super.key, required this.mood});

  final HomeMood mood;

  @override
  State<MoodBrowseScreen> createState() => _MoodBrowseScreenState();
}

class _MoodBrowseScreenState extends State<MoodBrowseScreen> {
  late Future<List<dynamic>> _sectionsFuture;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  void _loadSections() {
    _sectionsFuture = Get.find<MusicServices>().getMoodBrowse(
      widget.mood.browseId,
      params: widget.mood.params,
    );
  }

  void _retry() {
    setState(_loadSections);
  }

  List<dynamic> _normalizeSections(List<dynamic> sections) {
    final result = <dynamic>[];
    for (final section in sections) {
      if (section is QuickPicks ||
          section is PlaylistContent ||
          section is AlbumContent) {
        result.add(section);
        continue;
      }
      if (section is! Map || section['contents'] is! List) continue;

      final contents = section['contents'] as List;
      final title = section['title']?.toString().trim();
      final sectionTitle = title == null || title.isEmpty
          ? widget.mood.title
          : title;
      final songs = contents.whereType<MediaItem>().toList();
      final playlists = contents.whereType<Playlist>().toList();
      final albums = contents.whereType<Album>().toList();

      if (playlists.isNotEmpty) {
        result.add(
          PlaylistContent(title: sectionTitle, playlistList: playlists),
        );
      } else if (albums.isNotEmpty) {
        result.add(
          AlbumContent(title: sectionTitle, albumList: albums),
        );
      } else if (songs.isNotEmpty) {
        result.add(QuickPicks(songs, title: sectionTitle));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.mood.title)),
      body: FutureBuilder<List<dynamic>>(
        future: _sectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MoodLoadMessage(
              message: 'Unable to load this mood. Check your connection and retry.',
              onRetry: _retry,
            );
          }

          final sections = _normalizeSections(snapshot.data ?? const []);
          if (sections.isEmpty) {
            return _MoodLoadMessage(
              message: 'No content was returned for this mood. Try again.',
              onRetry: _retry,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 20, bottom: 120),
            itemCount: sections.length,
            itemBuilder: (_, index) {
              final section = sections[index];
              if (section is QuickPicks) {
                return QuickPicksWidget(content: section);
              }
              if (section is PlaylistContent || section is AlbumContent) {
                return ContentListWidget(content: section);
              }
              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}

class _MoodLoadMessage extends StatelessWidget {
  const _MoodLoadMessage({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
