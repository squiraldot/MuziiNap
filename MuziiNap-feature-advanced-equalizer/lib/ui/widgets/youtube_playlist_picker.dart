import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/playlist.dart';
import '../../services/music_service.dart';
import 'common_dialog_widget.dart';

class YoutubePlaylistPicker extends StatefulWidget {
  const YoutubePlaylistPicker({super.key, required this.song});

  final MediaItem song;

  @override
  State<YoutubePlaylistPicker> createState() => _YoutubePlaylistPickerState();
}

class _YoutubePlaylistPickerState extends State<YoutubePlaylistPicker> {
  bool _loading = true;
  String? _error;
  List<Playlist> _playlists = [];
  String? _addingPlaylistId;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    try {
      final prefs = Hive.box('AppPrefs');
      if (prefs.get('yt_logged_in', defaultValue: false) != true) {
        setState(() {
          _loading = false;
          _error = 'Connect your YouTube account first.';
        });
        return;
      }

      final service = Get.find<MusicServices>();
      if (!await service.validateYouTubeSession()) {
        await prefs.put('yt_logged_in', false);
        setState(() {
          _loading = false;
          _error = 'Your YouTube session has expired. Please sign in again.';
        });
        return;
      }

      final playlists = await service.getAccountPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = playlists.where((p) => p.playlistId != 'LM').toList();
        _loading = false;
        if (_playlists.isEmpty) {
          _error = 'No YouTube playlists were found on this account.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your YouTube playlists.';
      });
    }
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    setState(() => _addingPlaylistId = playlist.playlistId);
    final service = Get.find<MusicServices>();
    final success =
        await service.addSongToPlaylist(playlist.playlistId, widget.song.id);
    if (!mounted) return;

    setState(() => _addingPlaylistId = null);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${playlist.title}')),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add this song to the YouTube playlist.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add to YouTube playlist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SizedBox(
              width: 420,
              height: 420,
              child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: _playlists.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final playlist = _playlists[index];
                      final isAdding =
                          _addingPlaylistId == playlist.playlistId;
                      return ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: playlist.description == null
                            ? null
                            : Text(
                                playlist.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: isAdding
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add),
                        onTap: _addingPlaylistId == null
                            ? () => _addToPlaylist(playlist)
                            : null,
                      );
                    },
                  ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _addingPlaylistId == null
                    ? () => Navigator.of(context).pop()
                    : null,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
