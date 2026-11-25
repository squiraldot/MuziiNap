import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  Future<void> _requestPin(String size) async {
    setState(() => _message = null);
    try {
      final accepted = await _channel.invokeMethod<bool>('requestPin', <String, Object>{
        'themeId': 'dragon-ball-z',
        'designId': 'widget-1',
        'widgetSize': size,
      });
      if (!mounted) return;
      setState(() => _message = accepted == true
          ? 'Android launcher pin request opened. Complete it in the launcher.'
          : 'This launcher does not support pin requests. Add the widget from its widget picker.');
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? 'Could not request this widget.');
      await _refresh();
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
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const _ThemePackDetailScreen(),
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dragon Ball Z', style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('1 bundled design · Open pack'),
                            SizedBox(height: 4),
                            Text('Installed', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
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
  const _ThemePackDetailScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dragon Ball Z')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Designs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Widget 1'),
              subtitle: const Text('Bundled design · 4×2 assets available'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const _ThemeDesignDetailScreen(),
              )),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeDesignDetailScreen extends StatefulWidget {
  const _ThemeDesignDetailScreen();

  @override
  State<_ThemeDesignDetailScreen> createState() => _ThemeDesignDetailScreenState();
}

class _ThemeDesignDetailScreenState extends State<_ThemeDesignDetailScreen> {
  static const MethodChannel _channel = MethodChannel('muziinap/theme_music_widget');
  String _selectedSize = '4x2';
  String? _message;
  bool _requesting = false;

  Future<void> _addWidget() async {
    setState(() {
      _requesting = true;
      _message = null;
    });
    try {
      final accepted = await _channel.invokeMethod<bool>('requestPin', <String, Object>{
        'themeId': 'dragon-ball-z',
        'designId': 'widget-1',
        'widgetSize': _selectedSize,
      });
      if (mounted) setState(() => _message = accepted == true
          ? 'Finish the pin request in your launcher.'
          : 'Pinning is not supported by this launcher.');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? 'Unable to add widget.');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widget 1')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 2,
            child: DecoratedBox(
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
            ),
          ),
          const SizedBox(height: 20),
          Text('Widget size', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioListTile<String>(
            value: '4x2',
            groupValue: _selectedSize,
            onChanged: (value) => setState(() => _selectedSize = value!),
            title: const Text('4 × 2'),
            subtitle: const Text('Available'),
          ),
          const RadioListTile<String>(
            value: '4x3',
            groupValue: '4x2',
            onChanged: null,
            title: Text('4 × 3'),
            subtitle: Text('Unavailable · size-specific assets are not bundled yet'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _requesting ? null : _addWidget,
            icon: const Icon(Icons.add),
            label: Text(_requesting ? 'Requesting…' : 'Add widget'),
          ),
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
