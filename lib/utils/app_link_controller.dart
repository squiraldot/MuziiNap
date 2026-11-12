import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/playling_from.dart';
import '../services/deep_link_service.dart';
import '../services/song_link_playback_coordinator.dart';
import '../ui/widgets/songinfo_bottom_sheet.dart';
import './helper.dart';
import '../ui/widgets/loader.dart';
import '../services/music_service.dart';
import '../ui/player/player_controller.dart';
import '../ui/navigator.dart';
import '../ui/widgets/snackbar.dart';
import '../ui/widgets/common_dialog_widget.dart';

class AppLinksController extends GetxController with ProcessLink {
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<SongLinkRequest>? _songRequestSubscription;
  late final SongLinkPlaybackCoordinator _songPlaybackCoordinator;

  /// In-memory only: canonical song requests are queued for the application
  /// layer while this process is alive. Nothing is persisted for post-install
  /// or deferred retrieval.
  final RxList<SongLinkRequest> incomingSongRequests = <SongLinkRequest>[].obs;

  SongLinkRequest? takeNextSongRequest() {
    if (incomingSongRequests.isEmpty) return null;
    return incomingSongRequests.removeAt(0);
  }

  @override
  void onInit() {
    super.onInit();
    final deepLinkService = Get.find<DeepLinkService>();

    // The service owns the only app_links listener. Keep the existing
    // YouTube/import path intact by forwarding non-canonical URLs here.
    _songPlaybackCoordinator = SongLinkPlaybackCoordinator(
      resolveSong: _resolveSharedSong,
      playSong: (song) => Get.find<PlayerController>().playSharedSong(song),
      onFailure: _handleSongLinkFailure,
    );
    _songRequestSubscription = deepLinkService.songRequests.listen(
      (request) {
        incomingSongRequests.add(request);
        unawaited(_songPlaybackCoordinator.handle(request.videoId));
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('MuziiNap song-link delivery error: $error');
      },
    );
    _linkSubscription = deepLinkService.legacyLinks.listen(
      _handleLegacyLink,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('MuziiNap legacy link handling error: $error');
      },
    );

    // Subscribe before start(): the service installs its runtime listener
    // before awaiting the cold-start URI.
    unawaited(deepLinkService.start());
  }

  Future<MediaItem?> _resolveSharedSong(String videoId) async {
    final result = await Get.find<MusicServices>().getSongWithId(videoId);
    if (result.length < 2 || result[0] != true || result[1] is! List) {
      return null;
    }
    for (final item in (result[1] as List).whereType<MediaItem>()) {
      if (item.id == videoId) return item;
    }
    return null;
  }

  void _handleSongLinkFailure(Object error) {
    debugPrint('MuziiNap shared-song playback failed: $error');
    final context = Get.context;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        "notaSongVideo".tr,
        size: SanckBarSize.MEDIUM,
      ));
    }
  }

  void _handleLegacyLink(Uri uri) {
    // Initial links can arrive before GetMaterialApp has installed its context.
    // Defer UI-dependent legacy handling until the first frame is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.context != null) {
        unawaited(filterLinks(uri));
      } else {
        debugPrint('Skipping legacy link because app navigation is not ready.');
      }
    });
  }

  @override
  void onClose() {
    unawaited(_linkSubscription?.cancel() ?? Future<void>.value());
    unawaited(_songRequestSubscription?.cancel() ?? Future<void>.value());
    _songPlaybackCoordinator.dispose();
    super.onClose();
  }
}

mixin ProcessLink {
  Future<void> filterLinks(Uri uri) async {
    // Android file shares (for example Telegram .mdleq presets) arrive as
    // content:// URIs and are handled by MainActivity's preset-share channel.
    // They are not app/deep links and must never reach the YouTube link
    // validator, which otherwise displays "Not a Valid Link".
    if (uri.scheme != 'http' && uri.scheme != 'https') return;

    final playerController = Get.find<PlayerController>();
    if (playerController.playerPanelController.isPanelOpen) {
      playerController.playerPanelController.close();
    }

    if (Get.isRegistered<SongInfoController>()) {
      Navigator.of(Get.context!).pop();
    }

    // Canonical MuziiNap song links are consumed by the app-scoped playback
    // coordinator. This handler remains responsible for legacy imports.
    if (uri.host == "youtube.com" ||
        uri.host == "music.youtube.com" ||
        uri.host == "youtu.be" ||
        uri.host == "www.youtube.com" ||
        uri.host == "m.youtube.com") {
      printINFO(
          "pathsegmet: ${uri.pathSegments} params:${uri.queryParameters}");
      if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments[0] == "playlist" &&
          uri.queryParameters.containsKey("list")) {
        final browseId = uri.queryParameters['list'];
        if (browseId != null && browseId.isNotEmpty) {
          await openPlaylistOrAlbum(browseId);
        }
      } else if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments[0] == "shorts") {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "notaSongVideo".tr,
            size: SanckBarSize.MEDIUM));
      } else if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments[0] == "watch") {
        final songId = uri.queryParameters['v'];
        if (songId != null && songId.isNotEmpty) {
          await playSong(songId);
        }
      } else if (uri.pathSegments.length > 1 &&
          uri.pathSegments[0] == "channel") {
        await openArtist(uri.pathSegments[1]);
      } else if (uri.pathSegments.isNotEmpty &&
          (uri.queryParameters.isEmpty || uri.query.contains("si=")) &&
          uri.host == "youtu.be") {
        final songId = uri.pathSegments[0];
        if (songId.isNotEmpty) {
          await playSong(songId);
        }
      }
    } else {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "notaValidLink".tr,
          size: SanckBarSize.MEDIUM));
    }
  }

  Future<void> openPlaylistOrAlbum(String browseId) async {
    if (browseId.contains("OLAK5uy")) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (null, browseId));
    } else {
      Get.toNamed(ScreenNavigationSetup.playlistScreen,
          id: ScreenNavigationSetup.id, arguments: [null, browseId]);
    }
  }

  Future<void> openArtist(String channelId) async {
    await Get.toNamed(ScreenNavigationSetup.artistScreen,
        id: ScreenNavigationSetup.id, arguments: [true, channelId]);
  }

  Future<void> playSong(String songId) async {
    showDialog(
        context: Get.context!,
        builder: (context) => const CommonDialog(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Center(
                child: LoadingIndicator(strokeWidth: 5),
              ),
            ),
          ),
        ),
        barrierDismissible: false);
    final result = await Get.find<MusicServices>().getSongWithId(songId);
    Navigator.of(Get.context!).pop();
    if (result[0]) {
      Get.find<PlayerController>().playPlayListSong(List.from(result[1]), 0,
          playfrom: PlaylingFrom(type: PlaylingFromType.SELECTION));
    } else {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "notaSongVideo".tr,
          size: SanckBarSize.MEDIUM));
    }
  }
}
