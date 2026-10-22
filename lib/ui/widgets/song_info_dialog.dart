import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../services/constant.dart';
import './common_dialog_widget.dart';

class SongInfoDialog extends StatelessWidget {
  final MediaItem song;
  const SongInfoDialog({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    final height =
        (MediaQuery.sizeOf(context).height * .7).clamp(280.0, 600.0).toDouble();

    return CommonDialog(
      child: SizedBox(
        height: height,
        child: SongInfoContent(song: song),
      ),
    );
  }
}

class SongInfoContent extends StatelessWidget {
  final MediaItem song;

  const SongInfoContent({
    super.key,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    final streamInfo = _getStreamInfo(song.id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          child: Text(
            "songInfo".tr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              InfoItem(title: "id".tr, value: song.id),
              InfoItem(title: "title".tr, value: song.title),
              InfoItem(title: "album".tr, value: song.album ?? "NA"),
              InfoItem(title: "artists".tr, value: song.artist ?? "NA"),
              InfoItem(
                title: "duration".tr,
                value: _displayValue(
                  streamInfo["approxDurationMs"] ?? song.duration?.inMilliseconds,
                  suffix: " ms",
                ),
              ),
              InfoItem(
                title: "audioCodec".tr,
                value: _displayValue(streamInfo["audioCodec"]),
              ),
              InfoItem(
                title: "bitrate".tr,
                value: _displayValue(streamInfo["bitrate"]),
              ),
              InfoItem(
                title: "loudnessDb".tr,
                value: _displayValue(streamInfo["loudnessDb"]),
              ),
            ],
          ),
        ),
        const Divider(),
        SizedBox(
          height: 50,
          child: Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 25,
                ),
                child: Text("close".tr),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _displayValue(dynamic value, {String suffix = ""}) {
    if (value == null) return "NA";
    final text = value.toString().trim();
    return text.isEmpty ? "NA" : "$text$suffix";
  }

  Map<String, dynamic> _getStreamInfo(String id) {
    const empty = <String, dynamic>{};

    try {
      final downloads = Hive.box("SongDownloads");
      if (downloads.containsKey(id)) {
        final songData = downloads.get(id);
        final raw = songData is Map ? songData["streamInfo"] : null;

        if (raw is List && raw.length > 1 && raw[1] is Map) {
          return Map<String, dynamic>.from(raw[1] as Map);
        }
        if (raw is Map) {
          return Map<String, dynamic>.from(raw);
        }
        return empty;
      }

      final cache = Hive.box("SongsUrlCache").get(id);
      if (cache is! Map) return empty;

      final qualityKey =
          Hive.box(appPrefsBoxName).get("streamingQuality") == 0
              ? "lowQualityAudio"
              : "highQualityAudio";
      final selected = cache[qualityKey];
      if (selected is Map) {
        return Map<String, dynamic>.from(selected);
      }
    } catch (_) {
      // Cached stream metadata is optional. The song info UI must still render.
    }

    return empty;
  }
}

class InfoItem extends StatelessWidget {
  final String title;
  final String value;

  const InfoItem({
    super.key,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, textAlign: TextAlign.start),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
