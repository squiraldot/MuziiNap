import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A playful MuziiNap support page linking to Buy Me a Coffee.
class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {

  static const String _supportUrl = 'https://buymeacoffee.com/realmerrmist';

  Future<void> _openSupportPage() async {
    final uri = Uri.parse(_supportUrl);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the support page. Please try again.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the support page. Please try again.')),
        );
      }
    }
  }

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: theme.dividerColor),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            _buildHero(textTheme),
            const SizedBox(height: 12),
            _buildDivider(theme),
            const SizedBox(height: 14),
            SizedBox(
              key: const Key('latest-supporters-reserved-space'),
              height: MediaQuery.sizeOf(context).height * 0.42,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _openSupportPage,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: const StadiumBorder(),
                  textStyle: textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Buy a Pizzaa for Us!🍕'),
                    SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, color: theme.colorScheme.onSurface, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Secure Payment with Stripe',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(TextTheme textTheme) {
    final primaryTextColor = textTheme.titleLarge?.color ?? Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        SizedBox(
          height: 112,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 12,
                bottom: 14,
                child: _FoodEmoji('🍕', size: 34),
              ),
              Positioned(
                right: 12,
                bottom: 16,
                child: _FoodEmoji('🥤', size: 32),
              ),
              Positioned(
                top: 0,
                child: Image.asset(
                  'assets/icons/icon.png',
                  width: 108,
                  height: 108,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Text('🐿️', style: TextStyle(fontSize: 72)),
                ),
              ),
              Positioned(
                left: 64,
                top: 14,
                child: Text('✦', style: TextStyle(color: primaryTextColor, fontSize: 16)),
              ),
              Positioned(
                right: 58,
                top: 20,
                child: Text('✧', style: TextStyle(color: primaryTextColor, fontSize: 17)),
              ),
            ],
          ),
        ),
        Text(
          'Feed Our Developers😝 (Pizzaa!🍕)',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(
            color: primaryTextColor,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          "We're Hungry but our Pocket is Lonely😭",
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(
            color: textTheme.bodyLarge?.color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: Divider(color: theme.dividerColor, thickness: 1)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('🍕', style: TextStyle(fontSize: 17)),
        ),
        Expanded(child: Divider(color: theme.dividerColor, thickness: 1)),
      ],
    );
  }


}

class _FoodEmoji extends StatelessWidget {
  const _FoodEmoji(this.emoji, {required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(emoji, style: TextStyle(fontSize: size));
  }
}
