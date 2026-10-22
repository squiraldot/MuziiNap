import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/equalizer.dart';
import '../../../models/equalizer_preset.dart';
import '../../../services/equalizer_preset_file_codec.dart';
import '../../widgets/common_dialog_widget.dart';
import '../../../services/equalizer_preset_store.dart';
import '../../../services/preset_share_service.dart';

class EqualizerPresetPanel extends StatefulWidget {
  const EqualizerPresetPanel({
    super.key,
    required this.config,
    required this.persistChanges,
    required this.onApplyConfig,
  });

  final EqualizerConfig config;
  final bool persistChanges;
  final Future<void> Function(EqualizerConfig config) onApplyConfig;

  @override
  State<EqualizerPresetPanel> createState() => _EqualizerPresetPanelState();
}

class _EqualizerPresetPanelState extends State<EqualizerPresetPanel> {
  final _store = EqualizerPresetStore();
  List<EqualizerPreset> _customPresets = const [];
  String? _selectedPresetId;
  bool _loading = true;
  bool _applyingPreset = false;
  bool _fileOperationInProgress = false;
  Future<void> _presetWriteQueue = Future<void>.value();
  StreamSubscription<String>? _incomingPresetSubscription;

  List<EqualizerPreset> get _presets => [
        ...EqualizerBuiltInPresets.all,
        ..._customPresets,
      ];

  EqualizerPreset? get _selected {
    for (final preset in _presets) {
      if (preset.id == _selectedPresetId) return preset;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _incomingPresetSubscription =
        PresetShareService.incomingPresets.listen(_handleIncomingPayload);
    PresetShareService.getInitialPreset().then((payload) {
      if (payload != null) _handleIncomingPayload(payload);
    });
  }

  @override
  void dispose() {
    _incomingPresetSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleIncomingPayload(String payload) async {
    if (!payload.startsWith('base64:') || !mounted) return;
    try {
      final encoded = payload.substring('base64:'.length);
      final source = utf8.decode(base64Decode(encoded));
      final preset = EqualizerPresetFileCodec.decode(source);
      final shouldApply = await _showImportPreview(preset);
      if (shouldApply != true || !mounted) return;
      _applyingPreset = true;
      try {
        await widget.onApplyConfig(preset.config);
      } finally {
        _applyingPreset = false;
      }
      if (!mounted) return;
      final matching = _presets.where((item) => item.config == preset.config);
      setState(() {
        _selectedPresetId = matching.isEmpty ? null : matching.first.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported “${preset.name}” from a shared file.')),
      );
    } on FormatException catch (error) {
      if (mounted) _showFileError('Invalid MuziiNap preset', error);
    } catch (error) {
      if (mounted) _showFileError('Could not open shared preset', error);
    }
  }

  @override
  void didUpdateWidget(covariant EqualizerPresetPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config == widget.config ||
        _applyingPreset ||
        !widget.persistChanges) {
      return;
    }
    final matching = _presets.where((preset) => preset.config == widget.config);
    final exactPreset = matching.isEmpty ? null : matching.first;
    if (exactPreset != null) {
      setState(() => _selectedPresetId = exactPreset.id);
      return;
    }
    _presetWriteQueue = _presetWriteQueue.then((_) async {
      try {
        await _persistEditedConfig(widget.config);
      } catch (_) {
        // A failed preset write must never break realtime EQ editing.
      }
    });
  }

  Future<void> _load() async {
    final custom = await _store.listCustom();
    final selected = [
      ...EqualizerBuiltInPresets.all,
      ...custom,
    ].where((preset) => preset.config == widget.config).firstOrNull;
    if (!mounted) return;
    setState(() {
      _customPresets = custom;
      _selectedPresetId = selected?.id;
      _loading = false;
    });
  }

  Future<void> _persistEditedConfig(EqualizerConfig config) async {
    final selected = _selected;
    if (selected == null) return;

    if (selected.isBuiltIn) {
      final copy = await _store.duplicate(
        selected,
        name: selected.name + ' Custom',
      );
      final updated = await _store.update(copy, config: config);
      if (!mounted) return;
      setState(() {
        _customPresets = [..._customPresets, updated];
        _selectedPresetId = updated.id;
      });
      return;
    }

    final updated = await _store.update(selected, config: config);
    if (!mounted) return;
    setState(() {
      _customPresets = [
        for (final preset in _customPresets)
          preset.id == updated.id ? updated : preset,
      ];
    });
  }

  Future<void> _applyPreset(EqualizerPreset preset) async {
    setState(() => _selectedPresetId = preset.id);
    _applyingPreset = true;
    try {
      await widget.onApplyConfig(preset.config);
    } finally {
      _applyingPreset = false;
    }
  }

  Future<void> _saveAs() async {
    final controller = TextEditingController(
      text: _selected == null ? 'My Preset' : _selected!.name + ' Custom',
    );
    final name = await _nameDialog(
      title: 'Save preset',
      action: 'Save',
      controller: controller,
    );
    controller.dispose();
    if (name == null) return;

    final preset = await _store.create(
      name: name,
      config: widget.config,
    );
    if (!mounted) return;
    setState(() {
      _customPresets = [..._customPresets, preset];
      _selectedPresetId = preset.id;
    });
  }

  Future<void> _rename() async {
    final selected = _selected;
    if (selected == null || selected.isBuiltIn) return;

    final controller = TextEditingController(text: selected.name);
    final name = await _nameDialog(
      title: 'Rename preset',
      action: 'Rename',
      controller: controller,
    );
    controller.dispose();
    if (name == null) return;

    final updated = await _store.update(selected, name: name);
    if (!mounted) return;
    setState(() {
      _customPresets = [
        for (final preset in _customPresets)
          preset.id == updated.id ? updated : preset,
      ];
    });
  }

  Future<void> _duplicate() async {
    final selected = _selected;
    if (selected == null) return;
    final copy = await _store.duplicate(selected);
    if (!mounted) return;
    setState(() {
      _customPresets = [..._customPresets, copy];
      _selectedPresetId = copy.id;
    });
    _applyingPreset = true;
    try {
      await widget.onApplyConfig(copy.config);
    } finally {
      _applyingPreset = false;
    }
  }

  Future<void> _delete() async {
    final selected = _selected;
    if (selected == null || selected.isBuiltIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => CommonDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete preset?', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('Delete ' + selected.name + '? This cannot be undone.'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    await _store.delete(selected.id);
    if (!mounted) return;
    setState(() {
      _customPresets =
          _customPresets.where((preset) => preset.id != selected.id).toList();
      _selectedPresetId = null;
    });
  }


  Future<void> _export() async {
    if (_fileOperationInProgress) return;

    final selected = _selected ??
        EqualizerPreset(
          id: 'current-eq',
          name: 'My Equalizer',
          author: 'User',
          description: 'Current MuziiNap equalizer settings.',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          isBuiltIn: false,
          config: widget.config,
        );

    setState(() => _fileOperationInProgress = true);
    try {
      final encoded = EqualizerPresetFileCodec.encode(selected);
      final fileName = _fileName(selected.name);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export MuziiNap preset',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(encoded)),
      );

      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset exported: $fileName')),
      );
    } catch (error) {
      if (mounted) _showFileError('Could not export preset', error);
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  Future<void> _share() async {
    if (_fileOperationInProgress) return;

    final selected = _selected ??
        EqualizerPreset(
          id: 'current-eq',
          name: 'My Equalizer',
          author: 'User',
          description: 'Current MuziiNap equalizer settings.',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          isBuiltIn: false,
          config: widget.config,
        );

    setState(() => _fileOperationInProgress = true);
    try {
      final encoded = EqualizerPresetFileCodec.encode(selected);
      final directory = await getTemporaryDirectory();
      final fileName = _fileName(selected.name);
      final file = XFile(
        directory.path + '/' + fileName,
        mimeType: EqualizerPresetFileCodec.mimeType,
      );
      await File(file.path).writeAsBytes(utf8.encode(encoded), flush: true);
      await Share.shareXFiles(
        [file],
        subject: selected.name,
        text: 'MuziiNap Equalizer preset: ' + selected.name,
      );
    } catch (error) {
      if (mounted) _showFileError('Could not share preset', error);
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  Future<void> _import() async {
    if (_fileOperationInProgress) return;

    setState(() => _fileOperationInProgress = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (!EqualizerPresetFileCodec.isSupportedFileName(file.name)) {
        throw FormatException(
          'Please select a .${EqualizerPresetFileCodec.extension} preset file.',
        );
      }

      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      final preset = EqualizerPresetFileCodec.decode(utf8.decode(bytes));

      if (!mounted) return;
      final shouldApply = await _showImportPreview(preset);
      if (shouldApply != true) return;

      _applyingPreset = true;
      try {
        await widget.onApplyConfig(preset.config);
      } finally {
        _applyingPreset = false;
      }

      if (!mounted) return;
      final matching = _presets.where((item) => item.config == preset.config);
      setState(() {
        _selectedPresetId = matching.isEmpty ? null : matching.first.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported “${preset.name}”. Use Save as to keep it in My Presets.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (mounted) _showFileError('Invalid MuziiNap preset', error);
    } catch (error) {
      if (mounted) _showFileError('Could not import preset', error);
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  Future<bool?> _showImportPreview(EqualizerPreset preset) {
    final enabledBands =
        preset.config.bands.where((band) => band.enabled).length;
    return showDialog<bool>(
      context: context,
      builder: (context) => CommonDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preview imported preset',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(
                preset.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text('Author: ${preset.author}'),
              if (preset.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(preset.description),
              ],
              const SizedBox(height: 12),
              Text('Bands: ${enabledBands} enabled'),
              Text('Preamp: ${preset.config.preampDb.toStringAsFixed(1)} dB'),
              Text('Limiter: ${preset.config.limiterEnabled ? 'On' : 'Off'}'),
              Text(
                'Output gain: '
                '${preset.config.outputGainDb.toStringAsFixed(1)} dB',
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileError(String title, Object error) {
    showDialog<void>(
      context: context,
      builder: (context) => CommonDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text(error.toString()),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fileName(String name) {
    final sanitized = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final base = sanitized.isEmpty ? 'muziinap-preset' : sanitized;
    return base.endsWith('.${EqualizerPresetFileCodec.extension}')
        ? base
        : '$base.${EqualizerPresetFileCodec.extension}';
  }

  Future<String?> _nameDialog({
    required String title,
    required String action,
    required TextEditingController controller,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => CommonDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Preset name'),
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                    child: Text(action),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIsCustom = _selected?.isBuiltIn == false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Preset',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_loading || _fileOperationInProgress)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            DropdownButton<String>(
              isExpanded: true,
              value: _presets.any((preset) => preset.id == _selectedPresetId)
                  ? _selectedPresetId
                  : null,
              hint: const Text('Choose a preset'),
              items: [
                for (final preset in _presets)
                  DropdownMenuItem<String>(
                    value: preset.id,
                    child: Row(
                      children: [
                        Expanded(child: Text(preset.name)),
                        if (preset.isBuiltIn)
                          const Icon(Icons.lock_outline, size: 16),
                      ],
                    ),
                  ),
              ],
              onChanged: _loading || _fileOperationInProgress
                  ? null
                  : (id) {
                      if (id == null) return;
                      final preset =
                          _presets.firstWhere((item) => item.id == id);
                      _applyPreset(preset);
                    },
            ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  onPressed: _saveAs,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save as'),
                ),
                TextButton.icon(
                  onPressed: _selected == null ? null : _duplicate,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Duplicate'),
                ),
                TextButton.icon(
                  onPressed: _fileOperationInProgress ? null : _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('https://telegram.me/muziinap/193');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.library_music_outlined),
                  label: const Text('EQ Presets'),
                ),
                TextButton.icon(
                  onPressed: _fileOperationInProgress ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import'),
                ),
                TextButton.icon(
                  onPressed: _fileOperationInProgress ? null : _export,
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Export'),
                ),
                if (selectedIsCustom)
                  TextButton.icon(
                    onPressed: _rename,
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('Rename'),
                  ),
                if (selectedIsCustom)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
