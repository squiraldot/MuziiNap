import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'home.dart';
import 'splash_navigation_guard.dart';

/// Plays the bundled MuziiNap brand intro before entering the existing app.
class IntroVideoSplash extends StatefulWidget {
  const IntroVideoSplash({super.key});

  @override
  State<IntroVideoSplash> createState() => _IntroVideoSplashState();
}

class _IntroVideoSplashState extends State<IntroVideoSplash>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  late final SplashNavigationGuard _navigationGuard;
  bool _hasNavigated = false;
  bool _wasPlayingBeforePause = false;

  @override
  void initState() {
    super.initState();
    _navigationGuard = SplashNavigationGuard(onTimeout: _openApp);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startIntro());
  }

  Future<void> _startIntro() async {
    try {
      // Platform-channel initialization must never hold the app on the intro.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
          .timeout(const Duration(seconds: 3));
      if (!mounted || _hasNavigated) return;

      final controller = VideoPlayerController.asset(
        'assets/videos/muziinap_intro.MP4',
      );
      _controller = controller;
      controller.addListener(_handlePlaybackUpdate);

      // A broken codec, unavailable surface, or stalled platform channel must
      // fall through to Home instead of leaving a permanent black splash.
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || _hasNavigated) return;

      await controller.setLooping(false).timeout(const Duration(seconds: 3));
      await controller.seekTo(Duration.zero).timeout(const Duration(seconds: 3));
      await controller.play().timeout(const Duration(seconds: 5));
      if (!mounted || _hasNavigated) return;

      // VideoPlayer completion callbacks are not guaranteed on every Android
      // cold-start/device lifecycle path. Duration is an independent fallback.
      _navigationGuard.arm(controller.value.duration);
      setState(() {});
    } catch (error, stackTrace) {
      debugPrint('MuziiNap intro video startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _openApp();
    }
  }

  void _handlePlaybackUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      debugPrint(
        'MuziiNap intro playback error: ${controller.value.errorDescription}',
      );
      _openApp();
    } else if (controller.value.isCompleted) {
      _openApp();
    }
  }

  void _openApp() {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    _navigationGuard.complete();
    unawaited(_restoreSystemUi());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const Home()),
    );
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('MuziiNap system UI restoration failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _hasNavigated) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (controller.value.isPlaying) {
        _wasPlayingBeforePause = true;
        unawaited(controller.pause());
      }
    } else if (state == AppLifecycleState.resumed &&
        _wasPlayingBeforePause &&
        !controller.value.isCompleted) {
      _wasPlayingBeforePause = false;
      unawaited(controller.play());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigationGuard.dispose();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_handlePlaybackUpdate);
      unawaited(controller.dispose());
    }
    unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: controller != null && controller.value.isInitialized
              ? ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
