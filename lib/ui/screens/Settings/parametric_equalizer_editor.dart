import 'package:flutter/material.dart';

import '../../../models/equalizer.dart';

class ParametricEqualizerEditor extends StatelessWidget {
  const ParametricEqualizerEditor({
    super.key,
    required this.config,
    required this.enabled,
    required this.onChanged,
  });

  final EqualizerConfig config;
  final bool enabled;
  final ValueChanged<EqualizerConfig> onChanged;

  void _updateBand(EqualizerBand band) {
    final bands = [
      for (final current in config.bands)
        current.id == band.id ? band : current,
    ];
    onChanged(config.copyWith(bands: bands));
  }

  void _addBand() {
    if (config.bands.length >= EqualizerConfig.maxParametricBands) return;

    final band = EqualizerBand(
      id: 'parametric-${DateTime.now().microsecondsSinceEpoch}',
      type: EqualizerFilterType.peaking,
      frequency: 1000,
      gainDb: 0,
      q: 1,
      enabled: true,
    );
    onChanged(config.addBand(band));
  }

  void _removeBand(String id) {
    onChanged(config.removeBand(id));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Parametric EQ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Text('${config.bands.length}/${EqualizerConfig.maxParametricBands}'),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: enabled &&
                      config.bands.length < EqualizerConfig.maxParametricBands
                  ? _addBand
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Add band'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Each band keeps its frequency, gain, Q and filter type when switching modes.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (config.bands.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No bands configured. Add a band to begin.'),
            ),
          )
        else
          for (var index = 0; index < config.bands.length; index++)
            _ParametricBandCard(
              key: ValueKey(config.bands[index].id),
              band: config.bands[index],
              enabled: enabled,
              onChanged: _updateBand,
              onDelete: () => _removeBand(config.bands[index].id),
            ),
      ],
    );
  }
}

class _ParametricBandCard extends StatefulWidget {
  const _ParametricBandCard({
    super.key,
    required this.band,
    required this.enabled,
    required this.onChanged,
    required this.onDelete,
  });

  final EqualizerBand band;
  final bool enabled;
  final ValueChanged<EqualizerBand> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ParametricBandCard> createState() => _ParametricBandCardState();
}

class _ParametricBandCardState extends State<_ParametricBandCard> {
  late final TextEditingController _frequencyController;
  late final TextEditingController _gainController;
  late final TextEditingController _qController;

  @override
  void initState() {
    super.initState();
    _frequencyController =
        TextEditingController(text: widget.band.frequency.toString());
    _gainController =
        TextEditingController(text: widget.band.gainDb.toStringAsFixed(1));
    _qController = TextEditingController(text: widget.band.q.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _ParametricBandCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.band.frequency != widget.band.frequency) {
      _frequencyController.text = widget.band.frequency.toString();
    }
    if (oldWidget.band.gainDb != widget.band.gainDb) {
      _gainController.text = widget.band.gainDb.toStringAsFixed(1);
    }
    if (oldWidget.band.q != widget.band.q) {
      _qController.text = widget.band.q.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _frequencyController.dispose();
    _gainController.dispose();
    _qController.dispose();
    super.dispose();
  }

  void _submitFrequency(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      widget.onChanged(
        widget.band.copyWith(
          frequency: parsed.clamp(
            EqualizerBand.minFrequencyHz,
            EqualizerBand.maxFrequencyHz,
          ).toDouble(),
        ),
      );
    }
  }

  void _submitGain(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      widget.onChanged(
        widget.band.copyWith(
          gainDb: parsed
              .clamp(EqualizerBand.minGainDb, EqualizerBand.maxGainDb)
              .toDouble(),
        ),
      );
    }
  }

  void _submitQ(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      widget.onChanged(
        widget.band.copyWith(
          q: parsed.clamp(EqualizerBand.minQ, EqualizerBand.maxQ).toDouble(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final band = widget.band;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        enabled: widget.enabled,
        leading: Switch(
          value: band.enabled,
          onChanged: widget.enabled
              ? (value) => widget.onChanged(band.copyWith(enabled: value))
              : null,
        ),
        title: Text(
          '${band.frequency.toStringAsFixed(0)} Hz · ${band.gainDb >= 0 ? '+' : ''}'
          '${band.gainDb.toStringAsFixed(1)} dB · Q ${band.q.toStringAsFixed(2)}',
        ),
        subtitle: Text(_filterLabel(band.type)),
        trailing: IconButton(
          tooltip: 'Delete band',
          onPressed: widget.enabled ? widget.onDelete : null,
          icon: const Icon(Icons.delete_outline),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          DropdownButtonFormField<EqualizerFilterType>(
            value: band.type,
            decoration: const InputDecoration(labelText: 'Filter type'),
            items: [
              for (final type in EqualizerFilterType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(_filterLabel(type)),
                ),
            ],
            onChanged: widget.enabled
                ? (value) {
                    if (value != null) {
                      widget.onChanged(band.copyWith(type: value));
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _frequencyController,
                  enabled: widget.enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                    suffixText: 'Hz',
                  ),
                  onSubmitted: _submitFrequency,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _gainController,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Gain',
                    suffixText: 'dB',
                  ),
                  onSubmitted: _submitGain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _qController,
                  enabled: widget.enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Q'),
                  onSubmitted: _submitQ,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _filterLabel(EqualizerFilterType type) {
  return switch (type) {
    EqualizerFilterType.peaking => 'Peaking',
    EqualizerFilterType.lowShelf => 'Low Shelf',
    EqualizerFilterType.highShelf => 'High Shelf',
    EqualizerFilterType.lowPass => 'Low Pass',
    EqualizerFilterType.highPass => 'High Pass',
    EqualizerFilterType.bandPass => 'Band Pass',
    EqualizerFilterType.notch => 'Notch',
  };
}
