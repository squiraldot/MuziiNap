import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Acknowledges the people and services that make the listening experience possible.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  static const Color _muted = Color(0xFF9B9B9B);
  static const Color _divider = Color(0xFF292929);

  static const List<_CreditCategory> _categories = [
    _CreditCategory('Developer', Icons.code_rounded, [
      _Credit('SquiralDot', 'App development', socialLinks: [
        'https://github.com/squiraldot',
        'https://instagram.com/squiraldot',
      ]),
      _Credit('Ravi Verma', 'App development (owner of InstaPrime)', socialLinks: [
        'https://telegram.me/InstaPrimeDev',
      ]),
    ]),
    _CreditCategory('UI/UX', Icons.brush_outlined, [
      _Credit('ViMusic', 'Design inspiration', socialLinks: [
        'https://github.com/vfsfitvnm/ViMusic',
      ]),
    ]),
    _CreditCategory('Manager', Icons.manage_accounts_outlined, [
      _Credit('Danish Moon', 'Promotion and outreach', socialLinks: [
        'https://instagram.com/danzy.30',
        'https://telegram.me/danishmoon03',
      ]),
    ]),
    _CreditCategory('Branding', Icons.auto_awesome_outlined, [
      _Credit('InstaPrime', 'App branding', socialLinks: [
        'https://instaprimeofficial.com',
        'https://telegram.me/instaprimeofficial',
      ]),
    ]),
    _CreditCategory('Helping hand', Icons.volunteer_activism_outlined, [
      _Credit('Abhii', 'Creative Support', socialLinks: [
        'https://instagram.com/abhii.archieve',
        'https://telegram.me/iabhii28',
      ]),
    ]),
    _CreditCategory('Music source', Icons.music_note_outlined, [
      _Credit('YouTube', 'All music is streamed from YouTube', socialLinks: []),
    ]),
    _CreditCategory('Artists and creators', Icons.mic_none_rounded, [
      _Credit('Every artist and channel', 'Songs belong to their owners', socialLinks: []),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Credits'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _divider),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          children: [
            const _VinylHero(),
            const SizedBox(height: 30),
            for (final category in _categories) ...[
              _CategoryHeading(category: category),
              const SizedBox(height: 8),
              for (final credit in category.credits)
                _CreditTile(credit: credit),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 4),
            const Divider(height: 1, color: _divider),
            _FooterRow(
              icon: Icons.article_outlined,
              title: 'Licenses',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'MuziiNap',
              ),
            ),
            const Divider(height: 1, color: _divider),
            _FooterRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              onTap: () => _showPrivacyPolicyUnavailable(context),
            ),
            const Divider(height: 1, color: _divider),
            const SizedBox(height: 28),
            Text(
              'Thank you for listening.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _muted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicyUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Privacy policy URL is not configured in this app yet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Credit {
  const _Credit(this.name, this.description, {required this.socialLinks});
  final String name;
  final String description;
  // Add profile URLs here; matching platform icons appear only for configured links.
  final List<String> socialLinks;
}

class _CreditCategory {
  const _CreditCategory(this.title, this.icon, this.credits);
  final String title;
  final IconData icon;
  final List<_Credit> credits;
}

class _VinylHero extends StatelessWidget {
  const _VinylHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 154,
          height: 154,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 6; i++)
                Container(
                  width: 150 - i * 18.0,
                  height: 150 - i * 18.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i.isEven
                        ? const Color(0xFF171717)
                        : const Color(0xFF202020),
                    border: Border.all(
                      color: const Color(0xFF303030),
                      width: 1,
                    ),
                  ),
                ),
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6FAE),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'MuziiNap',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          'The people behind the MuziiNap',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF9B9B9B),
              ),
        ),
      ],
    );
  }
}

class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({required this.category});
  final _CreditCategory category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(category.icon, color: Colors.white, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            category.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit});
  final _Credit credit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: const Color(0xFF242424),
            child: Text(
              credit.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credit.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  credit.description,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF9B9B9B),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
          if (credit.socialLinks.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (final url in credit.socialLinks)
              _SocialLink(url: url),
          ],
        ],
      ),
    );
  }
}

class _SocialLink extends StatelessWidget {
  const _SocialLink({required this.url});
  final String url;

  IconData get _icon {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('instagram.com')) return Icons.camera_alt_outlined;
    if (host.contains('telegram.') || host.contains('telegram.me')) return Icons.send_rounded;
    if (host.contains('youtube.com') || host.contains('youtu.be')) return Icons.play_circle_outline;
    if (host.contains('t.me')) return Icons.send_rounded;
    if (host.contains('facebook.com')) return Icons.facebook;
    if (host.contains('x.com') || host.contains('twitter.com')) return Icons.alternate_email;
    if (host.contains('github.com')) return Icons.code_rounded;
    if (host.contains('linkedin.com')) return Icons.work_outline;
    if (host.contains('discord.')) return Icons.forum_outlined;
    if (host.contains('instaprimeofficial.com')) return Icons.language_rounded;
    return Icons.link_rounded;
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: url,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        icon: Icon(_icon, color: Colors.white, size: 19),
        onPressed: () async {
          final uri = Uri.tryParse(url);
          if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      );
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 2),
        minVerticalPadding: 12,
        leading: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFF9B9B9B),
        ),
        onTap: onTap,
      ),
    );
  }
}
