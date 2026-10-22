import 'package:flutter/foundation.dart';

/// Temporary, narrowly scoped diagnostics for the Song Info modal.
///
/// This flag is enabled only while the Song Info dialog is being presented.
/// It lets release logcat distinguish an ErrorWidget/PlatformDispatcher error
/// caused by this route from unrelated app errors.
class SongInfoDiagnostics {
  static bool active = false;

  static void enter() => active = true;

  static void exit() => active = false;

  static void reportFlutterError(FlutterErrorDetails details) {
    if (!active) return;
    debugPrint('SONG_INFO_DIAGNOSTIC FlutterError: ${details.exception}');
    debugPrintStack(stackTrace: details.stack);
  }

  static bool reportPlatformError(Object error, StackTrace stack) {
    if (!active) return false;
    debugPrint('SONG_INFO_DIAGNOSTIC PlatformError: $error');
    debugPrintStack(stackTrace: stack);
    return false;
  }
}
