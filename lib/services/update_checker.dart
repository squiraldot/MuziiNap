import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _releasesApi =
    'https://api.github.com/repos/squiraldot/MuziiNap-Releases/releases';
const _downloadUrl = 'https://t.me/muziinapofficial';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
  });

  final String version;
  final String notes;
}

class VersionCheckResult {
  const VersionCheckResult({
    required this.installedVersion,
    this.update,
  });

  final String installedVersion;
  final AppRelease? update;
}

class UpdateChecker {
  UpdateChecker._();

  static AppRelease? selectLatestStableRelease(List<dynamic> releases) {
    AppRelease? highest;
    for (final item in releases) {
      if (item is! Map<String, dynamic> ||
          item['draft'] == true ||
          item['prerelease'] == true) {
        continue;
      }
      final tag = item['tag_name'];
      if (tag is! String) continue;
      final candidate = SemanticVersion.tryParse(tag);
      if (candidate == null || candidate.isPrerelease) continue;
      if (highest == null ||
          candidate.compareTo(SemanticVersion.tryParse(highest.version)!) > 0) {
        final body = item['body'];
        highest = AppRelease(
          version: candidate.toString(),
          notes: body is String ? body.trim() : '',
        );
      }
    }
    return highest;
  }

  static Future<VersionCheckResult>? _inFlight;
  
  static Future<VersionCheckResult> check({http.Client? client}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _performCheck(client: client);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  static Future<VersionCheckResult> _performCheck({http.Client? client}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final installed = packageInfo.version;
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(
            Uri.parse(_releasesApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'MuziiNap-Version-Checker',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        throw StateError('GitHub returned HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException('Invalid releases JSON.');

      final highest = selectLatestStableRelease(decoded);

      final installedVersion = SemanticVersion.tryParse(installed);
      final latestVersion = highest == null
          ? null
          : SemanticVersion.tryParse(highest.version);
      return VersionCheckResult(
        installedVersion: installed,
        update: installedVersion != null &&
                latestVersion != null &&
                latestVersion.compareTo(installedVersion) > 0
            ? highest
            : null,
      );
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static bool _dialogVisible = false;

  static Future<void> showUpdateDialog(
    BuildContext context, {
    required String installedVersion,
    required AppRelease release,
  }) async {
    if (_dialogVisible || !context.mounted) return;
    _dialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update Available'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current version: v$installedVersion'),
                  const SizedBox(height: 4),
                  Text('New version: v${release.version}'),
                  if (release.notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Release notes',
                        style: Theme.of(dialogContext).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SelectableText(release.notes),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  final opened = await launchUrl(
                    Uri.parse(_downloadUrl),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open the download link.')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open the download link.')),
                    );
                  }
                }
              },
              child: const Text('Download'),
            ),
          ],
        ),
      );
    } finally {
      _dialogVisible = false;
    }
  }
}

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch, this.prerelease);

  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;

  bool get isPrerelease => prerelease.isNotEmpty;

  static SemanticVersion? tryParse(String input) {
    final normalized = input.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final prerelease = match[4] == null ? <String>[] : match[4]!.split('.');
    if (prerelease.any((part) => part.isEmpty ||
        (RegExp(r'^\d+$').hasMatch(part) &&
            part.length > 1 &&
            part.startsWith('0')))) {
      return null;
    }
    return SemanticVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      prerelease,
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final core = major.compareTo(other.major);
    if (core != 0) return core;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    final patchResult = patch.compareTo(other.patch);
    if (patchResult != 0) return patchResult;
    if (prerelease.isEmpty) return other.prerelease.isEmpty ? 0 : 1;
    if (other.prerelease.isEmpty) return -1;
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i];
      final b = other.prerelease[i];
      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);
      final result = aNum != null && bNum != null
          ? aNum.compareTo(bNum)
          : aNum != null
              ? -1
              : bNum != null
                  ? 1
                  : a.compareTo(b);
      if (result != 0) return result;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  @override
  String toString() => '$major.$minor.$patch'
      '${isPrerelease ? '-${prerelease.join('.')}' : ''}';
}
