import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/equalizer.dart';
import '../../../services/autoeq_service.dart';
import '../../../services/equalizer_preset_store.dart';

class AutoEqPanel extends StatefulWidget {
  const AutoEqPanel({
    super.key,
    required this.onApplyConfig,
  });

  final Future<void> Function(EqualizerConfig config) onApplyConfig;

  @override
  State<AutoEqPanel> createState() => _AutoEqPanelState();
}

class _AutoEqPanelState extends State<AutoEqPanel> {
  final _service = AutoEqService();
  final _searchController = TextEditingController();
  final _presetStore = EqualizerPresetStore();
  Timer? _debounce;

  List<AutoEqProfileSummary> _results = const [];
  AutoEqProfileSummary? _selected;
  AutoEqProfile? _profile;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_scheduleSearch);
    _search();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _service.search(_searchController.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadProfile(AutoEqProfileSummary summary) async {
    setState(() {
      _selected = summary;
      _profile = null;
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _service.loadProfile(summary);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // Keep the catalogue visible after a failed request so the user can
        // select another measurement or retry without reopening the screen.
        _selected = null;
        _profile = null;
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _apply() async {
    final profile = _profile;
    if (profile == null) return;
    await widget.onApplyConfig(profile.toConfig());
  }

  Future<void> _savePreset() async {
    final profile = _profile;
    if (profile == null) return;
    final preset = await _presetStore.create(
      name: profile.name + ' AutoEQ',
      author: 'AutoEq',
      description: 'AutoEq correction • ' + profile.source + ' • ' + profile.rig,
      config: profile.toConfig(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ' + preset.name + ' to My Presets.')),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AutoEQ / Headphone Profiles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Search public AutoEq measurements and preview a parametric correction.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search headphone / IEM',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_selected == null && _results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.name),
                      subtitle: Text(item.form + ' • ' + item.source),
                      onTap: () => _loadProfile(item),
                    );
                  },
                ),
              ),
            if (profile != null) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(profile.name),
                subtitle: Text(profile.source + ' • ' + profile.rig),
              ),
              SizedBox(
                height: 140,
                width: double.infinity,
                child: CustomPaint(
                  painter: _AutoEqCurvePainter(profile.bands),
                ),
              ),
              const SizedBox(height: 8),
              Text('Preamp: ' + profile.preampDb.toStringAsFixed(1) + ' dB'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final band in profile.bands)
                    Chip(
                      label: Text(
                        band.type.value +
                            ' ' +
                            band.frequency.round().toString() +
                            'Hz ' +
                            band.gainDb.toStringAsFixed(1) +
                            'dB',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.tune),
                    label: const Text('Apply'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _savePreset,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save preset'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected = null;
                      _profile = null;
                    }),
                    child: const Text('Back to search'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutoEqCurvePainter extends CustomPainter {
  const _AutoEqCurvePainter(this.bands);

  final List<EqualizerBand> bands;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final sorted = [...bands]..sort((a, b) => a.frequency.compareTo(b.frequency));
    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final band = sorted[i];
      final x = _x(band.frequency, size.width);
      final y = size.height * (1 - ((band.gainDb + 12) / 24)).clamp(0.0, 1.0);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 4, paint);
    }
    canvas.drawPath(path, paint);
  }

  double _x(double frequency, double width) {
    final minLog = math.log(20) / math.ln10;
    final maxLog = math.log(20000) / math.ln10;
    final value = math.log(frequency.clamp(20.0, 20000.0)) / math.ln10;
    return ((value - minLog) / (maxLog - minLog)).clamp(0.0, 1.0) * width;
  }

  @override
  bool shouldRepaint(covariant _AutoEqCurvePainter oldDelegate) => true;
}
