import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import 'credits_screen.dart';
import '../../../services/update_checker.dart';
import 'settings_screen_controller.dart';

/// About MuziiNap: app details, community links, project links and legal info.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const Color _muted = Color(0xFF9B9B9B);
  static const Color _divider = Color(0xFF292929);
  static final RxBool _isCheckingUpdate = false.obs;

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      _showMessage(context, 'This link is not available yet.');
      return;
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showMessage(context, 'Could not open this link.');
      }
    } catch (_) {
      if (context.mounted) _showMessage(context, 'Could not open this link.');
    }
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    if (_isCheckingUpdate.value) return;
    _isCheckingUpdate.value = true;
    try {
      final result = await UpdateChecker.check();
      if (!context.mounted) return;
      if (result.update != null) {
        await UpdateChecker.showUpdateDialog(
          context,
          installedVersion: result.installedVersion,
          release: result.update!,
        );
      } else {
        _showMessage(context, "You're on the latest version (v${result.installedVersion}).");
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'Could not check for updates. Please try again.');
      }
    } finally {
      _isCheckingUpdate.value = false;
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsScreenController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('About'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _divider),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF383838)),
                ),
                child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 42),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'MuziiNap',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Your music, your way.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: _muted),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Version ${controller.currentVersion}',
                  style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const Divider(color: _divider),
            const SizedBox(height: 18),
            _sectionTitle(theme, 'About MuziiNap'),
            const SizedBox(height: 10),
            Text(
              'MuziiNap is an Android music streaming app. '
              'It brings music discovery, playback, playlists, a personal library, '
              'YouTube integration and audio customization together in one place.',
              style: theme.textTheme.bodyMedium?.copyWith(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            _sectionTitle(theme, 'App'),
            const SizedBox(height: 6),
            Obx(
              () => _AboutLinkTile(
                icon: Icons.system_update_alt_rounded,
                title: 'In-app Update',
                subtitle: _isCheckingUpdate.value
                    ? 'Checking for updates…'
                    : 'Check for the latest version and update the app.',
                onTap: _isCheckingUpdate.value ? () {} : () => _checkForUpdate(context),
                trailing: _isCheckingUpdate.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 18),
            const Divider(color: _divider),
            const SizedBox(height: 18),
            _sectionTitle(theme, 'Our Community'),
            const SizedBox(height: 6),
            _AboutLinkTile(
              icon: Icons.send_rounded,
              title: 'Telegram Channel',
              subtitle: 'Announcements, updates and news.',
              onTap: () => _openLink(context, 'https://telegram.me/muziinapofficial'),
            ),
            _AboutLinkTile(
              icon: Icons.language_rounded,
              title: 'Official Website',
              subtitle: 'Visit our website.',
              onTap: () => _openLink(context, 'https://instaprimeofficial.com'),
            ),
            const SizedBox(height: 18),
            const Divider(color: _divider),
            const SizedBox(height: 18),
            _sectionTitle(theme, 'Feedback & Support'),
            const SizedBox(height: 6),
            _AboutLinkTile(
              icon: Icons.lightbulb_outline_rounded,
              title: 'Request a Feature',
              subtitle: 'Suggest an idea to improve MuziiNap.',
              onTap: () => _openLink(context, 'https://telegram.me/muziinap/189'),
            ),
            _AboutLinkTile(
              icon: Icons.bug_report_outlined,
              title: 'Report a Bug',
              subtitle: 'Let us know if something is not working.',
              onTap: () => _openLink(context, 'https://telegram.me/muziinap/190'),
            ),
            const SizedBox(height: 18),
            const Divider(color: _divider),
            const SizedBox(height: 18),
            _sectionTitle(theme, 'Project & Credits'),
            const SizedBox(height: 6),
            _AboutLinkTile(
              icon: Icons.people_alt_outlined,
              title: 'Credits',
              subtitle: 'The people behind the MuziiNap.',
              onTap: () => Get.to(() => const CreditsScreen()),
            ),
            const SizedBox(height: 24),
            const Divider(color: _divider),
            const SizedBox(height: 18),
            Text(
              'Made for music lovers.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: _muted, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionTitle(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _AboutLinkTile extends StatelessWidget {
  const _AboutLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9B9B9B)),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Color(0xFF9B9B9B)),
      onTap: onTap,
    );
  }
}
