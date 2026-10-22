import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';

import '../navigator.dart';
import 'image_widget.dart';

class ContentListItem extends StatefulWidget {
  const ContentListItem(
      {super.key, required this.content, this.isLibraryItem = false});

  final dynamic content;
  final bool isLibraryItem;

  @override
  State<ContentListItem> createState() => _ContentListItemState();
}

class _ContentListItemState extends State<ContentListItem> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final isLibraryItem = widget.isLibraryItem;
    final isAlbum = content.runtimeType.toString() == "Album";
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 180.0;
        final imageSize = cardWidth;
        return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onFocusChange: (focused) {
        setState(() {
          _hasFocus = focused;
        });
      },
      onTap: () {
        // Recently Played is account-scoped. Keep the existing tile, but
        // require YouTube Music sign-in before opening its playlist screen.
        if (!isAlbum &&
            widget.content.playlistId == 'LIBRP' &&
            Hive.box('AppPrefs').get('yt_logged_in', defaultValue: false) !=
                true) {
          // Use the tile's ScaffoldMessenger so the message works with the
          // app's nested Library navigator as well.
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Please log in to YouTube Music first to view Recently Played.',
                ),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
          return;
        }
        if (isAlbum) {
          Get.toNamed(ScreenNavigationSetup.albumScreen,
              id: ScreenNavigationSetup.id, arguments:(widget.content, widget.content.browseId));
          return;
        }
        Get.toNamed(ScreenNavigationSetup.playlistScreen,
            id: ScreenNavigationSetup.id,
            arguments: [widget.content, widget.content.playlistId]);
      },
      child: Container(
        width: double.infinity,
        height: cardWidth + 80,
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          border: _hasFocus
              ? Border.all(color: Theme.of(context).primaryColor, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isAlbum
                ? ImageWidget(
                    size: imageSize,
                    album: content,
                  )
                : content.isCloudPlaylist ||
                        !(content.playlistId == 'LIBRP' ||
                            content.playlistId == 'LIBFAV' ||
                            content.playlistId == 'SongsCache' ||
                            content.playlistId == 'SongDownloads')
                    ? SizedBox.square(
                        dimension: imageSize,
                        child: Stack(
                          children: [
                            ImageWidget(
                              size: imageSize,
                              playlist: content,
                            ),
                            if (content.isPipedPlaylist)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Container(
                                    height: 18,
                                    width: 18,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                    child: Center(
                                        child: Text(
                                      "P",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium!
                                          .copyWith(fontSize: 14),
                                    )),
                                  ),
                                ),
                              ),
                            if (!content.isCloudPlaylist)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Container(
                                    height: 18,
                                    width: 18,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                    child: Center(
                                        child: Text(
                                      "L",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium!
                                          .copyWith(fontSize: 14),
                                    )),
                                  ),
                                ),
                              )
                          ],
                        ),
                      )
                    : Container(
                        height: imageSize,
                        width: imageSize,
                        decoration: BoxDecoration(
                            color: Theme.of(context).primaryColorLight,
                            borderRadius: BorderRadius.circular(10)),
                        child: Center(
                            child: Icon(
                          content.playlistId == 'LIBRP'
                              ? Icons.history
                              : content.playlistId == 'LIBFAV'
                                  ? Icons.favorite
                                  : content.playlistId == 'SongsCache'
                                      ? Icons.flight
                                      : Icons.download,
                          color: Colors.white,
                          size: 40,
                        ))),
            const SizedBox(height: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content.title,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    isAlbum
                        ? isLibraryItem
                            ? ""
                            : "${content.artists[0]['name'] ?? ""} | ${content.year ?? ""}"
                        : isLibraryItem
                            ? ""
                            : content.description ?? "",
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
        );
      },
    );
  }
}
