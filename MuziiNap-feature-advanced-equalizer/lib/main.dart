import 'dart:ui' as ui;
import 'services/constant.dart';
import 'services/update_checker.dart';
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
import './services/music_service.dart';
import './ui/home.dart';
import './ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import './ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/update_check_flag_file.dart';
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
  startApplicationServices();
  await LocalProxy.start();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());
  if (updateCheckFlag) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = Get.context;
      if (context == null) return;
      UpdateChecker.check().then((result) {
        final release = result.update;
        final currentContext = Get.context;
        if (release != null &&
            currentContext != null &&
            currentContext.mounted) {
          UpdateChecker.showUpdateDialog(
            currentContext,
            installedVersion: result.installedVersion,
            release: release,
          );
        }
      }).catchError((Object error) {
        debugPrint('Startup version check failed: $error');
      });
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    Get.put(AppLinksController());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return GetMaterialApp(
        title: 'MuziiNap',
        home: const Home(),
        debugShowCheckedModeBanner: false,
        translations: Languages(),
        locale:
            Locale(Hive.box(appPrefsBoxName).get('currentAppLanguageCode') ?? "en"),
        fallbackLocale: const Locale("en"),
        builder: (context, child) {
          final mQuery = MediaQuery.of(context);
          final scale =
              mQuery.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.1);
          return Stack(
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
          );
        });
  }
}

Future<void> startApplicationServices() async {
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
  Get.lazyPut(() => Downloader(), fenix: true);
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
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
