import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'home.dart';

/// Plays the bundled MuziiNap brand intro before entering the existing app.
class IntroVideoSplash extends StatefulWidget {
  const IntroVideoSplash({super.key});

  @override
  State<IntroVideoSplash> createState() => _IntroVideoSplashState();
}

class _IntroVideoSplashState extends State<IntroVideoSplash>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _hasNavigated = false;
  bool _wasPlayingBeforePause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startIntro());
  }

  Future<void> _startIntro() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted || _hasNavigated) return;
    final controller = VideoPlayerController.asset(
      'assets/videos/muziinap_intro.mp4',
    );
    _controller = controller;
    controller.addListener(_handlePlaybackUpdate);

    try {
      await controller.initialize();
      if (!mounted || _hasNavigated) return;
      await controller.setLooping(false);
      await controller.seekTo(Duration.zero);
      await controller.play();
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('MuziiNap intro video failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _openApp();
    }
  }

  void _handlePlaybackUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      debugPrint('MuziiNap intro playback error: ${controller.value.errorDescription}');
      _openApp();
    } else if (controller.value.isCompleted) {
      _openApp();
    }
  }

  void _openApp() {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    unawaited(_restoreSystemUi());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const Home()),
    );
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
      _wasPlayingBeforePause = controller.value.isPlaying;
      if (_wasPlayingBeforePause) unawaited(controller.pause());
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