import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

/// Explains Android's battery-exemption setting and opens its app-specific
/// system request screen when background playback may be restricted.
class BatteryOptimizationService extends GetxService {
  /// Must match android/app/build.gradle's defaultConfig.applicationId.
  static const String applicationId = 'com.merrmist.muziinapmusic';

  bool _hasCheckedThisLaunch = false;

  Future<void> checkAndPrompt(BuildContext context) async {
    if (!Platform.isAndroid || _hasCheckedThisLaunch || !context.mounted) {
      return;
    }

    // Mark before awaiting the platform channel so repeated widget rebuilds
    // cannot open multiple battery dialogs concurrently.
    _hasCheckedThisLaunch = true;
    final currentStatus =
        await Permission.ignoreBatteryOptimizations.status;
    if (currentStatus.isGranted || !context.mounted) return;
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow uninterrupted background playback?'),
        content: const Text(
          'Android and some device manufacturers may restrict background '
          'activity to save battery. Allowing MuziiNap to be unrestricted '
          'can help keep your music playing when the screen is off. '
          'You can change this setting at any time in system settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open battery settings'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings != true || !context.mounted) return;

    // permission_handler launches ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
    // with this app's package: URI. Android resolves that URI from the installed
    // applicationId (com.merrmist.muziinapmusic), opening this app's exemption
    // screen rather than the generic battery-optimization list.
    final requestedStatus =
        await Permission.ignoreBatteryOptimizations.request();

    if (!requestedStatus.isGranted) {
      debugPrint(
        'MuziiNap battery optimization exemption was not granted: '
        '${requestedStatus.name}',
      );
    }
  }
}
