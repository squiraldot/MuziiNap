import 'package:hive/hive.dart';
import '../../../services/constant.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/animated_screen_transition.dart';
import '../Library/library_combined.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Search/search_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '../../player/player_controller.dart';
import '../../widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../widgets/content_list_widget.dart';
import '../../../models/album.dart';
import '../../../models/playlist.dart';
import '../../../models/quick_picks.dart';
import '../../widgets/quickpickswidget.dart';
import '../../../models/home_mood.dart';
import 'mood_browse_screen.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import 'home_screen_controller.dart';
import '../Settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final HomeScreenController homeScreenController =
        Get.find<HomeScreenController>();
    final SettingsScreenController settingsScreenController =
        Get.find<SettingsScreenController>();

    return Scaffold(
        floatingActionButton: Obx(
          () => ((homeScreenController.tabIndex.value == 0) ||
                      homeScreenController.tabIndex.value == 2) &&
                  settingsScreenController.isBottomNavBarEnabled.isFalse
              ? Obx(
                  () => Padding(
                    padding: EdgeInsets.only(
                        bottom: playerController.playerPanelMinHeight.value >
                                Get.mediaQuery.padding.bottom
                            ? playerController.playerPanelMinHeight.value -
                                Get.mediaQuery.padding.bottom
                            : playerController.playerPanelMinHeight.value),
                    child: SizedBox(
                      height: 60,
                      width: 60,
                      child: FittedBox(
                        child: FloatingActionButton(
                            focusElevation: 0,
                            shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(14))),
                            elevation: 0,
                            onPressed: () async {
                              if (homeScreenController.tabIndex.value == 2) {
                                showDialog(
                                    context: context,
                                    builder: (context) =>
                                        const CreateNRenamePlaylistPopup());
                              } else {
                                Get.toNamed(ScreenNavigationSetup.searchScreen,
                                    id: ScreenNavigationSetup.id);
                              }
                              // file:///data/user/0/com.merrmist.muziinapmusic/cache/libCachedImageData/
                              // file:///data/user/0/com.merrmist.muziinapmusic/cache/just_audio_cache/
                            },
                            child: Icon(homeScreenController.tabIndex.value == 2
                                ? Icons.add
                                : Icons.search)),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        body: Obx(
          () => Row(
            children: <Widget>[
              // create a navigation rail
              settingsScreenController.isBottomNavBarEnabled.isFalse
                  ? FocusScope(
                      node: playerController.sidePanelFocus,
                      child: const SideNavBar(),
                    )
                  : const SizedBox(
                      width: 0,
                    ),
              Expanded(
                child: FocusScope(
                  node: playerController.centerPanelFocus,
                  child: Obx(
                    () => AnimatedScreenTransition(
                      enabled: settingsScreenController
                          .isTransitionAnimationDisabled.isFalse,
                      resverse: homeScreenController.reverseAnimationtransiton,
                      horizontalTransition:
                          settingsScreenController.isBottomNavBarEnabled.isTrue,
                      child: SizedBox.expand(
                        key: ValueKey<int>(homeScreenController.tabIndex.value),
                        child: const Body(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour <= 12) return 'Good Morning';
    if (hour >= 13 && hour <= 17) return 'Good Afternoon';
    if (hour >= 18 && hour <= 23) return 'Good Evening';
    return 'Good Night';
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MuziNap',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _greeting(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
            onPressed: () => home.onBottonBarTabSelected(3),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _HomeMoodChips extends StatelessWidget {
  const _HomeMoodChips({required this.moods});

  final List<HomeMood> moods;

  @override
  Widget build(BuildContext context) {
    final visibleMoods = moods.take(8).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: visibleMoods.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final selected = index == 0;
            final label = selected ? 'All' : visibleMoods[index - 1].title;
            return FilterChip(
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              showCheckmark: false,
              selected: selected,
              onSelected: (_) {
                if (selected) return;
                final mood = visibleMoods[index - 1];
                Get.to(() => MoodBrowseScreen(mood: mood));
              },
              side: BorderSide(
                color: selected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Theme.of(context).colorScheme.outline,
              ),
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeBackHeader extends StatelessWidget {
  const _WelcomeBackHeader();

  @override
  Widget build(BuildContext context) {
    final homeController = Get.find<HomeScreenController>();

    return Obx(() {
      final account = Map<String, dynamic>.from(
        homeController.youtubeAccount,
      );
      final name =
          (account['accountName']?.toString().trim().isNotEmpty == true)
              ? account['accountName'].toString().trim()
              : 'YouTube Music';
      final photo = account['accountPhotoUrl']?.toString().trim();

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Keep this greeting in the widget tree for a future opt-in,
            // but hide it for the current Home layout.
            Visibility(
              visible: false,
              maintainState: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: photo != null && photo.isNotEmpty
                        ? Image.network(
                            photo,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _AccountFallbackAvatar(),
                          )
                        : const _AccountFallbackAvatar(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _AccountFallbackAvatar extends StatelessWidget {
  const _AccountFallbackAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: const Icon(Icons.person, size: 24),
    );
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final topPadding =
        MediaQuery.paddingOf(context).top + (context.isLandscape ? 4.0 : 8.0);

    if (homeScreenController.tabIndex.value == 0) {
      return Stack(
          children: [
            GestureDetector(
              onTap: () {

              },
              child: Obx(
                () => homeScreenController.networkError.isTrue
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height - 180,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                "home".tr,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "networkError1".tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(
                                        height: 10,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 15, vertical: 10),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .textTheme
                                                .titleLarge!
                                                .color,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: InkWell(
                                          onTap: () {
                                            homeScreenController
                                                .loadContentFromNetwork();
                                          },
                                          child: Text(
                                            "retry".tr,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .canvasColor),
                                          ),
                                        ),
                                      ),
                                    ]),
                              ),
                            )
                          ],
                        ),
                      )
                    : Obx(() {
                        // dispose all detachached scroll controllers
                        homeScreenController.disposeDetachedScrollControllers();
                        final items = homeScreenController.isContentFetched.value
                            ? [
                                const _HomeHeader(),
                                if (homeScreenController.homeMoods.isNotEmpty)
                                  _HomeMoodChips(
                                    moods: homeScreenController.homeMoods,
                                  ),
                                if (Hive.box(appPrefsBoxName).get(
                                      'yt_logged_in',
                                      defaultValue: false,
                                    ) ==
                                    true)
                                  const _WelcomeBackHeader(),
                                Obx(() {
                                  if (homeScreenController
                                      .quickPicks.value.songList.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  final scrollController = ScrollController();
                                  homeScreenController.contentScrollControllers
                                      .add(scrollController);
                                  return QuickPicksWidget(
                                    content: homeScreenController.quickPicks.value,
                                    scrollController: scrollController,
                                  );
                                }),
                                ...getWidgetList(
                                  homeScreenController.middleContent,
                                  homeScreenController,
                                ),
                                ...getWidgetList(
                                  homeScreenController.fixedContent,
                                  homeScreenController,
                                ),
                              ]
                            : [const HomeShimmer()];
                        return RefreshIndicator(
                          onRefresh: homeScreenController.refreshHome,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              15,
                              topPadding,
                              15,
                              180,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) => items[index],
                          ),
                        );
                      }),
              ),
            ),
          ],
      );
    } else if (homeScreenController.tabIndex.value == 1) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SearchScreen()
          : const SongsLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 2) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const CombinedLibrary()
          : const PlaylistNAlbumLibraryWidget(isAlbumContent: false);
    } else if (homeScreenController.tabIndex.value == 3) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SettingsScreen(isBottomNavActive: true)
          : const PlaylistNAlbumLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 4) {
      return const LibraryArtistWidget();
    } else if (homeScreenController.tabIndex.value == 5) {
      return const SettingsScreen();
    } else {
      return Center(
        child: Text("${homeScreenController.tabIndex.value}"),
      );
    }
  }

  List<Widget> getWidgetList(
      dynamic list, HomeScreenController homeScreenController) {
    return list
        .map((content) {
          final scrollController = ScrollController();
          homeScreenController.contentScrollControllers.add(scrollController);

          if (content is QuickPicks) {
            return QuickPicksWidget(
              content: content,
              scrollController: scrollController,
            );
          }

          if (content is PlaylistContent || content is AlbumContent) {
            return ContentListWidget(
              content: content,
              scrollController: scrollController,
            );
          }

          return null;
        })
        .whereType<Widget>()
        .toList();
  }
}
