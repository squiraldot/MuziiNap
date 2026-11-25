import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/theme_widget_catalog.dart';
import '../../../services/theme_widget_availability.dart';

class ThemeWidgetGalleryScreen extends StatefulWidget {
  const ThemeWidgetGalleryScreen({super.key});

  @override
  State<ThemeWidgetGalleryScreen> createState() => _ThemeWidgetGalleryScreenState();
}

class _ThemeWidgetGalleryScreenState extends State<ThemeWidgetGalleryScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('muziinap/theme_music_widget');
  Map<String, dynamic> _status = const <String, dynamic>{};
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getWidgetStatus');
      if (mounted) setState(() => _status = result ?? const <String, dynamic>{});
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? 'Could not read widget status.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final widgets = (_status['widgets'] as List?)?.whereType<Map>().toList() ?? const [];
    final active = (_status['activeCount'] as num?)?.toInt() ?? 0;
    final pending = (_status['pendingCount'] as num?)?.toInt() ?? 0;
    final remaining = (_status['remainingCapacity'] as num?)?.toInt() ?? (2 - active - pending).clamp(0, 2);
    final conflict = _status['recoveryConflict'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Widgets'),
        actions: [
          IconButton(
            tooltip: 'Refresh widget status',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Your widgets', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lyrics_outlined),
                title: const Text('Lyrics Widget'),
                subtitle: const Text('Existing MuziiNap lyrics widget · managed separately'),
                trailing: const Icon(Icons.verified_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Text('Active theme widgets', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$active / 2 active · $remaining slots remaining',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (pending > 0) Text('$pending pin request(s) pending'),
                    if (conflict)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Recovery conflict: existing widgets were preserved. Remove extras manually before adding another.',
                            style: TextStyle(color: Colors.orange)),
                      ),
                    const SizedBox(height: 12),
                    if (widgets.isEmpty)
                      const Text('No registered theme widgets yet.')
                    else
                      ...widgets.map((item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.widgets_outlined),
                            title: Text('${item['themeId']} · ${item['designId']}'),
                            subtitle: Text('${item['size']} · ${item['state']} · ID ${item['appWidgetId']}'),
                          )),
                    const Text('To remove a widget, remove it manually from your Android launcher.',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Theme Packs', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...bundledThemeWidgetCatalog.map((pack) => Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _ThemePackDetailScreen(pack: pack),
                )),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.palette_outlined, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pack.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${pack.designs.length} registered design(s) · Open pack'),
                            const SizedBox(height: 4),
                            const Text('Bundled', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            )),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (_loading) const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePackDetailScreen extends StatelessWidget {
  const _ThemePackDetailScreen({required this.pack});

  final ThemeWidgetPackDefinition pack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(pack.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Designs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...pack.designs.map((design) => Card(
            child: ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: Text(design.name),
              subtitle: Text('Bundled design · ${design.supportedSizes.join(', ')} available'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _ThemeDesignDetailScreen(pack: pack, design: design),
              )),
            ),
          )),
        ],
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined, size: 36),
              SizedBox(height: 8),
              Text('Preview unavailable'),
              Text('No remote preview is registered for this design.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _ThemeDesignDetailScreen extends StatefulWidget {
  const _ThemeDesignDetailScreen({required this.pack, required this.design});

  final ThemeWidgetPackDefinition pack;
  final ThemeWidgetDesignDefinition design;

  @override
  State<_ThemeDesignDetailScreen> createState() => _ThemeDesignDetailScreenState();
}

class _ThemeDesignDetailScreenState extends State<_ThemeDesignDetailScreen> {
  static const MethodChannel _channel = MethodChannel('muziinap/theme_music_widget');
  String _selectedSize = '4x2';
  String? _message;
  String? _statusError;
  bool _requesting = false;
  bool _loadingStatus = true;
  ThemeWidgetAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  Future<void> _refreshAvailability() async {
    if (mounted) setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('getWidgetStatus');
      if (status == null) throw PlatformException(
        code: 'empty_status', message: 'Widget status was unavailable.',
      );
      if (mounted) setState(() {
        _availability = ThemeWidgetAvailability.fromStatus(status);
        _loadingStatus = false;
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() {
        _statusError = error.message ?? 'Could not verify widget availability.';
        _loadingStatus = false;
      });
    }
  }

  bool get _designSupportsSelectedSize =>
      widget.design.supportedSizes.contains(_selectedSize);

  bool get _canAdd {
    final availability = _availability;
    return !_loadingStatus &&
        _statusError == null &&
        !_requesting &&
        _designSupportsSelectedSize &&
        availability != null &&
        availability.canAdd(widget.pack.themeId, widget.design.designId);
  }

  String? get _availabilityMessage {
    if (_loadingStatus) return 'Checking available widget slots…';
    if (_statusError != null) return _statusError;
    if (!_designSupportsSelectedSize) return 'Assets for this widget size are not bundled yet.';
    return _availability?.reasonFor(widget.pack.themeId, widget.design.designId);
  }

  Future<void> _addWidget() async {
    if (!_canAdd) return;
    setState(() {
      _requesting = true;
      _message = null;
    });
    try {
      final accepted = await _channel.invokeMethod<bool>('requestPin', <String, Object>{
        'themeId': widget.pack.themeId,
        'designId': widget.design.designId,
        'widgetSize': _selectedSize,
      });
      if (mounted) setState(() => _message = accepted == true
          ? 'Finish the pin request in your launcher.'
          : 'Pinning is not supported by this launcher.');
      await _refreshAvailability();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? 'Unable to add widget.');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.design.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.design.remotePreviewUrl != null)
            AspectRatio(
              aspectRatio: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  widget.design.remotePreviewUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _PreviewPlaceholder(),
                ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 2,
              child: _PreviewPlaceholder(),
            ),
          const SizedBox(height: 20),
          Text('Widget size', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...widget.design.supportedSizes.map((size) => RadioListTile<String>(
            value: size,
            groupValue: _selectedSize,
            onChanged: (value) => setState(() => _selectedSize = value!),
            title: Text(size == '4x2' ? '4 × 2' : '4 × 3'),
            subtitle: const Text('Available'),
          )),
          if (!widget.design.supportedSizes.contains('4x3'))
            const RadioListTile<String>(
              value: '4x3',
              groupValue: '4x2',
              onChanged: null,
              title: Text('4 × 3'),
              subtitle: Text('Unavailable · size-specific assets are not bundled yet'),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _canAdd ? _addWidget : null,
            icon: const Icon(Icons.add),
            label: Text(_requesting ? 'Requesting…' : 'Add widget'),
          ),
          if (_availabilityMessage != null) ...[
            const SizedBox(height: 8),
            Text(_availabilityMessage!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
          const SizedBox(height: 8),
          const Text('Previews are remote-only. A failed or missing preview does not block theme information.',
              style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
