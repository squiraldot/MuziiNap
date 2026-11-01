import 'dart:async';
import 'dart:ui' as ui;
import 'services/constant.dart';
import 'utils/update_check_flag_file.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import './ui/screens/Search/search_screen_controller.dart';
import './utils/get_localization.dart';
import './services/downloader.dart';
import './services/piped_service.dart';
import 'utils/app_link_controller.dart';
import './services/audio_handler.dart';
import './services/audio_playback_service.dart';
import './services/isar_database_service.dart';
import './services/innertube_auth_interceptor.dart';
import './ui/screens/Settings/youtube_login_screen.dart';
import './services/music_service.dart';
import './ui/intro_video_splash.dart';
import './ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import './ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/song_info_diagnostics.dart';
import 'services/local_proxy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    SongInfoDiagnostics.reportFlutterError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    final handled = SongInfoDiagnostics.reportPlatformError(error, stack);
    if (!handled) {
      debugPrint('PlatformError: $error');
      debugPrintStack(stackTrace: stack);
    }
    return handled;
  };
  await initHive();
  _setAppInitPrefs();
  await LocalProxy.start();
  await startApplicationServices();
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());

}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    Get.put(AppLinksController());
    return GetMaterialApp(
        title: 'MuziiNap',
        home: const IntroVideoSplash(),
        debugShowCheckedModeBanner: false,
        translations: Languages(),
        locale:
            Locale(Hive.box(appPrefsBoxName).get('currentAppLanguageCode') ?? "en"),
        fallbackLocale: const Locale("en"),
        builder: (context, child) {
          final mQuery = MediaQuery.of(context);
          final scale =
              mQuery.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.1);
          return _YouTubeSessionExpiryListener(
            child: Stack(
              children: [
                GetX<ThemeController>(
                  builder: (controller) => MediaQuery(
                    data: mQuery.copyWith(textScaler: scale),
                    child: AnimatedTheme(
                        duration: const Duration(milliseconds: 700),
                        data: controller.themedata.value!,
                        child: child!),
                  ),
                ),
                GestureDetector(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      color: Colors.transparent,
                      height: mQuery.padding.bottom,
                      width: mQuery.size.width,
                    ),
                  ),
                )
              ],
            ),
          );
        });
  }
}

class _YouTubeSessionExpiryListener extends StatefulWidget {
  const _YouTubeSessionExpiryListener({required this.child});

  final Widget child;

  @override
  State<_YouTubeSessionExpiryListener> createState() =>
      _YouTubeSessionExpiryListenerState();
}

class _YouTubeSessionExpiryListenerState
    extends State<_YouTubeSessionExpiryListener> {
  StreamSubscription<InnerTubeSessionExpiredEvent>? _subscription;
  bool _openingLogin = false;

  @override
  void initState() {
    super.initState();
    _subscription =
        InnerTubeAuthInterceptor.sessionExpiredEvents.listen((_) {
      unawaited(_redirectToYouTubeLogin());
    });
  }

  Future<void> _redirectToYouTubeLogin() async {
    if (!mounted || _openingLogin ||
        Get.currentRoute.toLowerCase().contains('youtubelogin')) {
      return;
    }
    _openingLogin = true;

    Get.snackbar(
      'YouTube session expired',
      'Your YouTube sign-in has expired. Please sign in again to restore your personalized music feed.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
      margin: const EdgeInsets.all(12),
    );

    try {
      await Get.to(
        () => const YoutubeLoginScreen(),
        preventDuplicates: true,
      );
    } finally {
      _openingLogin = false;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> startApplicationServices() async {
  // Keep Isar lazy until a library feature opts into the Hive migration.
  Get.lazyPut<IsarDatabaseService>(() => IsarDatabaseService());
  Get.lazyPut(() => PipedServices(), fenix: true);
  Get.lazyPut(() => MusicServices(), fenix: true);
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
  Get.lazyPut(() => HomeScreenController(), fenix: true);
  Get.lazyPut(() => LibrarySongsController(), fenix: true);
  Get.lazyPut(() => LibraryPlaylistsController(), fenix: true);
  Get.lazyPut(() => LibraryAlbumsController(), fenix: true);
  Get.lazyPut(() => LibraryArtistsController(), fenix: true);
  Get.lazyPut(() => SettingsScreenController(), fenix: true);
  // Persistent download work must outlive route/controller disposal.
  await Get.putAsync<DownloadCacheService>(
    () async => DownloadCacheService(),
    permanent: true,
  );
  // Keep the platform AudioHandler registered for the whole app process.
  await Get.putAsync<AudioPlaybackService>(() async {
    final handler = await initAudioService();
    Get.put<AudioHandler>(handler, permanent: true);
    return AudioPlaybackService.create(handler);
  }, permanent: true);
  Get.lazyPut(() => SearchScreenController(), fenix: true);
}

initHive() async {
  String applicationDataDirectoryPath;
  applicationDataDirectoryPath =
      (await getApplicationDocumentsDirectory()).path;
  await Hive.initFlutter(applicationDataDirectoryPath);
  await Hive.openBox("SongsCache");
  await Hive.openBox("SongDownloads");
  await Hive.openBox('SongsUrlCache');
  await Hive.openBox(appPrefsBoxName);
}

void _setAppInitPrefs() {
  final appPrefs = Hive.box(appPrefsBoxName);
  if (appPrefs.get('cacheCleared_v2') != true) {
    Hive.box('SongsUrlCache').clear();
    appPrefs.put('cacheCleared_v2', true);
  }
  
  if (appPrefs.isEmpty) {
    appPrefs.putAll({
      'themeModeType': 0,
      "cacheSongs": false,
      "skipSilenceEnabled": false,
      'streamingQuality': 1,
      'themePrimaryColor': 4278199603,
      'discoverContentType': "QP",
      'newVersionVisibility': updateCheckFlag,
      "cacheHomeScreenData": true
    });
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final handler = Get.find<AudioHandler>();
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }

    if (state == AppLifecycleState.detached) {
      await handler.customAction("saveSession");
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // MyAudioHandler checks playing/processing state before unloading. Active
      // background music is never interrupted by a lifecycle transition.
      await handler.customAction("releasePausedResources");
    }
  }
}
