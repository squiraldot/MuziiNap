import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../../../services/constant.dart';

class BgUtilsProviderSettings extends StatefulWidget {
  const BgUtilsProviderSettings({super.key});

  @override
  State<BgUtilsProviderSettings> createState() => _BgUtilsProviderSettingsState();
}

class _BgUtilsProviderSettingsState extends State<BgUtilsProviderSettings> {
  static const _channel = MethodChannel('muziinap/bgutils');
  Timer? _statusTimer;
  bool _running = false;
  bool _busy = false;
  bool _statusInitialized = false;
  bool _downloadingRuntime = false;
  int _downloadedBytes = 0;
  int _downloadTotalBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      final running = status?['serverReady'] == true && status?['serviceRunning'] == true;
      final downloading = status?['runtimeDownloadInProgress'] == true;
      final downloaded = (status?['runtimeDownloadBytes'] as num?)?.toInt() ?? 0;
      final total = (status?['runtimeDownloadTotalBytes'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      if (!_statusInitialized ||
          running != _running ||
          downloading != _downloadingRuntime ||
          downloaded != _downloadedBytes ||
          total != _downloadTotalBytes) {
        setState(() {
          _running = running;
          _downloadingRuntime = downloading;
          _downloadedBytes = downloaded;
          _downloadTotalBytes = total;
          _statusInitialized = true;
        });
        await Hive.box(appPrefsBoxName).put('bgutilLocalEnabled', running);
      }
    } on PlatformException {
      // Keep the last known UI state; a later poll can recover transient channel errors.
    }
  }

  Future<void> _setup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await _channel.invokeMethod<String>('setup');
      if (!mounted) return;
      if (status == 'server_started') {
        await Hive.box(appPrefsBoxName).put('bgutilLocalEnabled', true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('YouTube PO Token Provider is running successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'allow_install_from_this_source'
              ? 'Allow MuziiNap to install the verified Node.js runtime, then tap again.'
              : 'Node.js runtime download completed. Confirm installation, then tap again.')),
        );
      }
      await _refreshStatus();
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'BgUtils setup failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
      await Hive.box(appPrefsBoxName).put('bgutilLocalEnabled', false);
      if (mounted) {
        setState(() => _running = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Local PO Token Provider stopped.')),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Could not stop BgUtils')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: (_busy || _downloadingRuntime)
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.verified_user_outlined),
        title: const Text('YouTube PO Token Provider'),
        subtitle: Text(
          _downloadingRuntime
              ? (_downloadTotalBytes > 0
                  ? 'Downloading Node.js runtime: ${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(_downloadTotalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                  : 'Downloading Node.js runtime: ${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB')
              : _running
                  ? 'Local BgUtils service is running'
                  : 'Install the optional Node runtime and start the local BgUtils service',
        ),
        trailing: Icon(_running ? Icons.check_circle : Icons.chevron_right,
            color: _running ? Theme.of(context).colorScheme.primary : null),
        onTap: _busy ? null : _setup,
      ),
      if (_running)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: const Icon(Icons.stop_circle_outlined),
          title: const Text('Stop local PO Token Provider'),
          onTap: _stop,
        ),
    ],
  );
}
