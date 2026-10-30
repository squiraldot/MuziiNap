import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../native_bindings/andrid_utils.dart' show SDKInt;
class PermissionService {
  static bool _batteryOptimizationPromptShown = false;

  /// Offers Android users the app-specific battery-optimization exemption.
  /// This can improve background playback reliability on restrictive devices.
  static Future<void> checkBatteryOptimization(BuildContext context) async {
    if (!Platform.isAndroid ||
        _batteryOptimizationPromptShown ||
        !context.mounted) {
      return;
    }

    // Set before awaiting the platform channel to prevent duplicate dialogs.
    _batteryOptimizationPromptShown = true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted || !context.mounted) return;

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow uninterrupted background playback?'),
        content: const Text(
          'Android and some device manufacturers may restrict background '
          'activity to save battery. Allowing MuziiNap to run unrestricted '
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

    if (openSettings != true || !context.mounted) return;

    // permission_handler opens ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
    // for this installed app's package, not the generic app-settings screen.
    final requestedStatus =
        await Permission.ignoreBatteryOptimizations.request();
    if (!requestedStatus.isGranted) {
      debugPrint(
        'MuziiNap battery optimization exemption was not granted: '
        '${requestedStatus.name}',
      );
    }
  }

  static Future<bool> getExtStoragePermission() async {
    if ((SDKInt.Companion.getSDKInt()) < 30) {
      var status = await Permission.storage.status;
      if (status.isDenied) {
        await [
          Permission.storage,
          Permission.accessMediaLocation,
          Permission.mediaLibrary,
        ].request();
      }

      if (await Permission.storage.isPermanentlyDenied) {
        await openAppSettings();
      }

      return (await Permission.storage.status).isGranted;
    } else {
      if (!await Permission.manageExternalStorage.isGranted) {
        final permission = await Permission.manageExternalStorage.request();
        return permission.isGranted;
      }
      return true;
    }
  }
}
