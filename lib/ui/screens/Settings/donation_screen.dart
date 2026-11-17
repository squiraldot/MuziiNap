import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/supporter.dart';
import '../../../services/supporters_api_service.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key, this.supportersService});
  final SupportersApiService? supportersService;
  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> with WidgetsBindingObserver {
  static const String _supportUrl = 'https://buymeacoffee.com/realmerrmist';
  static const String _illustrationUrl = 'https://raw.githubusercontent.com/squiraldot/MuziiNap-Official/refs/heads/main/assets/donation_illustration.png';
  late final SupportersApiService _service = widget.supportersService ?? SupportersApiService();
  final CancelToken _cancelToken = CancelToken();
  SupportersResponse? _snapshot;
  SupportersException? _failure;
  Future<void>? _activeRequest;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken.cancel('Donation screen disposed');
    super.dispose();
  }

  Future<void> _refresh() {
    final active = _activeRequest;
    if (active != null) return active;
    final request = _load();
    _activeRequest = request;
    return request.whenComplete(() {
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() {
      _loading = _snapshot == null;
      _refreshing = _snapshot != null;
      _failure = null;
    });
    try {
      final result = await _service.fetchSupporters(cancelToken: _cancelToken);
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _failure = null;
        _loading = false;
        _refreshing = false;
      });
    } on SupportersException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failure = const SupportersException(SupportersFailure.server);
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _openSupportPage() async {
    try {
      final opened = await launchUrl(Uri.parse(_supportUrl), mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showLaunchError();
    } catch (_) {
      if (mounted) _showLaunchError();
    }
  }

  void _showLaunchError() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not open the support page. Please try again.')),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        title: const Text('Support Us'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: theme.dividerColor)),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              CachedNetworkImage(
                key: const Key('donation-illustration'),
                imageUrl: _illustrationUrl,
                height: 226, width: double.infinity, fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox(height: 226,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                errorWidget: (_, __, ___) => SizedBox(height: 226,
                  child: Icon(Icons.image_not_supported_outlined, size: 48,
                    color: theme.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(height: 8),
              Text('Feed our Developers\n(Pizzaa🍕)', key: const Key('donation-heading'),
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onSurface,
                  fontSize: 34, fontWeight: FontWeight.w600, height: 1.18)),
              const SizedBox(height: 8),
              Text("We're Hungry but our Pocket is Lonely😭", textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500)),
              const SizedBox(height: 28),
              SizedBox(height: 54, child: FilledButton(
                onPressed: _openSupportPage,
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary, shape: const StadiumBorder(),
                  textStyle: textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Buy a Pizzaa for Us!🍕'), SizedBox(width: 12),
                  Icon(Icons.arrow_forward_rounded, size: 21),
                ]),
              )),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_rounded, color: theme.colorScheme.onSurfaceVariant, size: 14),
                const SizedBox(width: 7),
                Text('Secure Payment with Stripe', style: textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              ]),
              const SizedBox(height: 30),
              _supportersPanel(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportersPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    return Container(
      key: const Key('latest-supporters-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(32)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Our Pizza Heroes 🍕', style: theme.textTheme.titleLarge?.copyWith(
            color: colors.onSurface, fontWeight: FontWeight.w700))),
          IconButton(key: const Key('supporters-refresh'), tooltip: 'Refresh supporters',
            onPressed: _activeRequest == null ? _refresh : null,
            icon: _refreshing ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded)),
        ]),
        if (_snapshot != null && _failure != null)
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text('Could not refresh. Showing the last available supporter list.',
              key: const Key('supporters-stale'),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(
              key: Key('supporters-loading'), strokeWidth: 2)))
        else if (_snapshot != null)
          if (_snapshot!.supporters.isEmpty) _emptyState(theme)
          else ..._snapshot!.supporters.map((s) => _SupporterTile(supporter: s))
        else
          _errorState(theme),
      ]),
    );
  }

  Widget _emptyState(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 4),
    child: Center(child: Column(children: [
      const Text('🍕', style: TextStyle(fontSize: 34)),
      const SizedBox(height: 8),
      Text('No pizza heroes yet!', textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('The first slice is waiting for someone! 😝', textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ])),
  );

  Widget _errorState(ThemeData theme) {
    final unavailable = _failure?.failure == SupportersFailure.unavailable;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
      child: Column(children: [
        Icon(unavailable ? Icons.hourglass_empty_rounded : Icons.cloud_off_rounded,
          size: 30, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(unavailable ? 'Supporter updates are getting ready.'
          : (_failure?.userMessage ?? 'Could not load supporters.'),
          key: const Key('supporters-error'), textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        TextButton.icon(key: const Key('supporters-retry'),
          onPressed: _activeRequest == null ? _refresh : null,
          icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
      ]),
    );
  }
}

class _SupporterTile extends StatelessWidget {
  const _SupporterTile({required this.supporter});
  final Supporter supporter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details = <String>[];
    if (supporter.amount != null) {
      final amount = supporter.amount == supporter.amount!.toInt()
        ? supporter.amount!.toInt().toString() : supporter.amount.toString();
      details.add('${supporter.currency == null ? '' : '${supporter.currency} '}$amount');
    }
    if (supporter.supportedAt != null) {
      final date = supporter.supportedAt!.toLocal();
      details.add('${date.day.toString().padLeft(2, '0')} ${_month(date.month)} ${date.year}');
    }
    return Container(key: const Key('supporter-card'),
      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 17, backgroundColor: colors.primary.withValues(alpha: 0.16),
            child: Icon(Icons.favorite_rounded, size: 17, color: colors.primary)),
          const SizedBox(width: 10),
          Expanded(child: Text(supporter.name, key: const Key('supporter-name'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurface, fontWeight: FontWeight.w700))),
          if (details.isNotEmpty) Flexible(child: Text(details.join(' · '),
            textAlign: TextAlign.end, style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant))),
        ]),
        if (supporter.message != null) ...[
          const SizedBox(height: 9),
          Text('“${supporter.message}”', key: const Key('supporter-message'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant, height: 1.35)),
        ],
      ]),
    );
  }

  static String _month(int month) => const [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][month - 1];
}