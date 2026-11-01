import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../../services/constant.dart';

enum _BgUtilsSetupState { idle, checkingRuntime, downloadingRuntime, verifyingRuntime, awaitingInstallation, startingService, running, failed }

class BgUtilsProviderSettings extends StatefulWidget {
  const BgUtilsProviderSettings({super.key});
  @override
  State<BgUtilsProviderSettings> createState() => _BgUtilsProviderSettingsState();
}

class _BgUtilsProviderSettingsState extends State<BgUtilsProviderSettings> with WidgetsBindingObserver {
  static const _channel = MethodChannel('muziinap/bgutils');
  static const _setupTimeout = Duration(minutes: 18);
  Timer? _statusTimer;
  _BgUtilsSetupState _state = _BgUtilsSetupState.idle;
  bool _statusInitialized = false;
  bool _running = false;
  bool _setupInFlight = false;
  bool _waitingForInstaller = false;\n  bool _awaitingInstallPermission = false;
  int _downloadedBytes = 0;
  int _downloadTotalBytes = 0;
  int _pollGeneration = 0;
  String? _errorMessage;
  String? _stageMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus().then((_) {
        if (mounted && _waitingForInstaller && !_setupInFlight) _resumeAfterInstaller();
      });
    }
  }

  Future<void> _resumeAfterInstaller() async {
    final status = await _readStatus();
    if (!mounted || status == null) return;
    if (status['runtimeInstalled'] == true) {
      setState(() {
        _waitingForInstaller = false;
        _state = _BgUtilsSetupState.startingService;
        _stageMessage = 'Node.js installed. Starting BgUtils...';
      });
      await _setup();
    } else if (_awaitingInstallPermission) {
      setState(() {
        _waitingForInstaller = false;
        _awaitingInstallPermission = false;
        _state = _BgUtilsSetupState.checkingRuntime;
        _stageMessage = 'Permission granted. Opening Android installer...';
      });
      await _setup();
    } else {
      setState(() {
        _waitingForInstaller = false;
        _state = _BgUtilsSetupState.failed;
        _errorMessage = 'Node.js installation was cancelled or did not complete. Tap Retry to try again.';
      });
    }
  }

  Future<Map<String, dynamic>?> _readStatus() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('status').timeout(const Duration(seconds: 5));
    } on PlatformException catch (error) {
      _showPollingError(error.message ?? error.code);
    } on TimeoutException {
      _showPollingError('Native status check timed out.');
    } catch (error) {
      _showPollingError('Could not read provider status: $error');
    }
    return null;
  }

  void _showPollingError(String message) {
    if (!mounted || _setupInFlight) return;
    setState(() {
      _errorMessage = message;
      if (!_running) _state = _BgUtilsSetupState.failed;
    });
  }

  Future<void> _refreshStatus() async {
    final generation = ++_pollGeneration;
    final status = await _readStatus();
    if (!mounted || status == null || generation != _pollGeneration) return;
    final running = status['serverReady'] == true && status['serviceRunning'] == true;
    final downloading = status['runtimeDownloadInProgress'] == true;
    final downloaded = (status['runtimeDownloadBytes'] as num?)?.toInt() ?? 0;
    final total = (status['runtimeDownloadTotalBytes'] as num?)?.toInt() ?? 0;
    final runtimeState = status['runtimeInstallState'] as String?;\n    final serviceState = status['serviceState'] as String?;\n    final serviceFailure = status['serviceFailure'] as String?;
    if (!mounted || generation != _pollGeneration) return;
    setState(() {
      _running = running;
      _downloadedBytes = downloaded;
      _downloadTotalBytes = total;
      _statusInitialized = true;
      if (running) {
        _state = _BgUtilsSetupState.running;
        _errorMessage = null;
        _stageMessage = 'Provider running successfully.';
      } else if (downloading) {
        _state = _BgUtilsSetupState.downloadingRuntime;
        _stageMessage = 'Downloading Node.js runtime...';
      } else if (serviceState == 'failed') {\n        _state = _BgUtilsSetupState.failed;\n        _errorMessage = serviceFailure ?? 'BgUtils service failed to start. Tap Retry.';\n      } else if (runtimeState == 'verified' || runtimeState == 'awaiting_installation' || runtimeState == 'awaiting_install_permission') {
        _state = _BgUtilsSetupState.awaitingInstallation;
        _stageMessage = 'Waiting for Android installation...';
      } else if (!_setupInFlight && _state != _BgUtilsSetupState.failed && !_waitingForInstaller) {
        _state = _BgUtilsSetupState.idle;
      }
    });
    await Hive.box(appPrefsBoxName).put('bgutilLocalEnabled', running);
  }

  Future<void> _setup() async {
    if (_setupInFlight || _running) return;
    setState(() {
      _setupInFlight = true;
      _errorMessage = null;
      _state = _BgUtilsSetupState.checkingRuntime;
      _stageMessage = 'Checking Node.js runtime...';
    });
    try {
      final status = await _channel.invokeMethod<String>('setup').timeout(_setupTimeout);
      if (!mounted) return;
      if (status == 'server_started') {
        await Hive.box(appPrefsBoxName).put('bgutilLocalEnabled', true);
        setState(() {
          _running = true;
          _state = _BgUtilsSetupState.running;
          _stageMessage = 'Provider running successfully.';
          _waitingForInstaller = false;
        });
        _showMessage('YouTube PO Token Provider is running successfully.');
      } else if (status == 'installer_opened' || status == 'allow_install_from_this_source') {
        setState(() {
          _waitingForInstaller = true;
          _awaitingInstallPermission = status == 'allow_install_from_this_source';
          _state = _BgUtilsSetupState.awaitingInstallation;
          _stageMessage = status == 'allow_install_from_this_source'
              ? 'Allow MuziiNap to install apps, then return here.'
              : 'Waiting for Android to finish installing Node.js...';
        });
      } else {
        setState(() {
          _state = _BgUtilsSetupState.verifyingRuntime;
          _stageMessage = 'Verifying runtime installation...';
        });
      }
      await _refreshStatus();
    } on TimeoutException {
      if (mounted) setState(() {
        _state = _BgUtilsSetupState.failed;
        _errorMessage = 'Setup exceeded the 9-minute limit. Check your connection and retry.';
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() {
        _state = _BgUtilsSetupState.failed;
        _errorMessage = '${error.message ?? 'BgUtils setup failed'} (${error.code})';
      });
    } catch (error) {
      if (mounted) setState(() {
        _state = _BgUtilsSetupState.failed;
        _errorMessage = 'Unexpected setup error: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _setupInFlight = false);
        await _refreshStatus();
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stop() async {
    try {
      await _channel.invokeMethod<bool>('stop').timeout(const Duration(seconds: 10));
      await Hive.box(appPrefsBoxName).put('bgutilLocalEnabled', false);
      if (mounted) {
        setState(() {
          _running = false;
          _state = _BgUtilsSetupState.idle;
        });
        _showMessage('Local PO Token Provider stopped.');
      }
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? 'Could not stop BgUtils');
    } on TimeoutException {
      if (mounted) _showMessage('Timed out while stopping BgUtils.');
    }
  }

  String _statusText() {
    if (_state == _BgUtilsSetupState.downloadingRuntime) {
      final downloaded = (_downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
      if (_downloadTotalBytes > 0) {
        final total = (_downloadTotalBytes / (1024 * 1024)).toStringAsFixed(1);
        return 'Downloading Node.js runtime: $downloaded / $total MB';
      }
      return 'Downloading Node.js runtime: $downloaded MB';
    }
    if (_errorMessage != null) return _errorMessage!;
    if (_stageMessage != null) return _stageMessage!;
    switch (_state) {
      case _BgUtilsSetupState.idle: return 'Install the optional Node runtime and start the local BgUtils service';
      case _BgUtilsSetupState.checkingRuntime: return 'Checking Node.js runtime...';
      case _BgUtilsSetupState.downloadingRuntime: return 'Downloading Node.js runtime...';
      case _BgUtilsSetupState.verifyingRuntime: return 'Verifying downloaded runtime...';
      case _BgUtilsSetupState.awaitingInstallation: return 'Waiting for Android installation...';
      case _BgUtilsSetupState.startingService: return 'Starting local service...';
      case _BgUtilsSetupState.running: return 'Local BgUtils service is running';
      case _BgUtilsSetupState.failed: return 'Setup failed. Tap Retry.';
    }
  }

  bool get _showProgress => _setupInFlight ||
      _state == _BgUtilsSetupState.downloadingRuntime ||
      _state == _BgUtilsSetupState.checkingRuntime ||
      _state == _BgUtilsSetupState.verifyingRuntime ||
      _state == _BgUtilsSetupState.startingService ||
      _state == _BgUtilsSetupState.awaitingInstallation;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: _showProgress
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                _running ? Icons.verified_user : _state == _BgUtilsSetupState.failed ? Icons.error_outline : Icons.verified_user_outlined,
                color: _state == _BgUtilsSetupState.failed ? Theme.of(context).colorScheme.error : null,
              ),
        title: const Text('YouTube PO Token Provider'),
        subtitle: Text(_statusText()),
        trailing: Icon(_running ? Icons.check_circle : Icons.chevron_right,
            color: _running ? Theme.of(context).colorScheme.primary : null),
        onTap: _setupInFlight ? null : _setup,
      ),
      if (_state == _BgUtilsSetupState.downloadingRuntime && _downloadTotalBytes > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(value: (_downloadedBytes / _downloadTotalBytes).clamp(0.0, 1.0)),
        ),
      if (_state == _BgUtilsSetupState.failed)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _setupInFlight ? null : _setup,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
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
