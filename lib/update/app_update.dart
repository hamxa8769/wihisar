/// In-app updater for WiHisar.
///
/// Checks the GitHub Releases API for hamxa8769/wihisar and compares the
/// latest tag (e.g. `v0.2.0`) with the running version. Pure version logic
/// lives here with no Flutter dependency so it is unit-testable; the HTTP
/// fetch is a small injectable function so tests never touch the network.
///
/// The updater never downloads or installs anything silently: it shows what
/// is new and opens the release page (or the asset URL) in the browser, and
/// the user installs from there. No auto-download, no background install.
library;

import 'dart:convert';
import 'dart:io';

/// The version of the app that is currently running.
const String kAppVersion = '0.4.0';

/// GitHub repo the updater watches.
const String kUpdateRepo = 'hamxa8769/wihisar';

String get kLatestReleaseApiUrl =>
    'https://api.github.com/repos/$kUpdateRepo/releases/latest';

String get kReleasesPageUrl => 'https://github.com/$kUpdateRepo/releases';

/// Parse `v0.2.0`, `0.2.0`, `v0.2.0+3` into [major, minor, patch].
/// Returns null when the string is not a version at all.
List<int>? parseVersion(String raw) {
  final cleaned = raw.trim().replaceFirst(RegExp(r'^v'), '').split('+').first;
  final parts = cleaned.split('.');
  if (parts.length != 3) return null;
  final numbers = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null) return null;
    numbers.add(n);
  }
  return numbers;
}

/// True when [latest] is strictly newer than [current].
bool isNewerVersion(String latest, String current) {
  final l = parseVersion(latest);
  final c = parseVersion(current);
  if (l == null || c == null) return false;
  for (var i = 0; i < 3; i++) {
    if (l[i] != c[i]) return l[i] > c[i];
  }
  return false;
}

/// One release asset (APK / zip / installer) from the GitHub API.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] as String?) ?? '',
      downloadUrl: (json['browser_download_url'] as String?) ?? '',
    );
  }
}

/// What the updater found on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.releasePageUrl,
    required this.releaseNotes,
    required this.assets,
  });

  final String latestVersion;
  final String releasePageUrl;
  final String releaseNotes;
  final List<ReleaseAsset> assets;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .toList();
    return UpdateInfo(
      latestVersion: tag.replaceFirst(RegExp(r'^v'), ''),
      releasePageUrl: (json['html_url'] as String?) ?? kReleasesPageUrl,
      releaseNotes: (json['body'] as String?) ?? '',
      assets: assets,
    );
  }

  /// The asset that fits this platform best, if any.
  /// Android prefers an .apk, Windows a .zip/.exe, everything else the
  /// release page. Returns null when no asset matches.
  ReleaseAsset? assetFor(String platform) {
    final lower = platform.toLowerCase();
    for (final a in assets) {
      final name = a.name.toLowerCase();
      if (lower == 'android' && name.endsWith('.apk')) return a;
      if (lower == 'windows' &&
          (name.endsWith('.zip') || name.endsWith('.exe'))) {
        return a;
      }
      if ((lower == 'linux' || lower == 'macos') && name.endsWith('.zip')) {
        return a;
      }
    }
    return null;
  }
}

/// Result of one update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    this.info,
    this.error,
  });

  final bool updateAvailable;
  final UpdateInfo? info;

  /// Human-readable reason when the check itself failed (offline, etc.).
  /// Null on success.
  final String? error;
}

typedef ReleaseJsonFetcher = Future<String> Function(Uri url);

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('User-Agent', 'WiHisar/$kAppVersion');
    final response = await request.close().timeout(
      const Duration(seconds: 15),
    );
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException(
        'GitHub releases API returned ${response.statusCode}',
      );
    }
    return body;
  } finally {
    client.close();
  }
}

/// Check GitHub for a newer release than [currentVersion].
/// Never throws: failures come back as [UpdateCheckResult.error].
Future<UpdateCheckResult> checkForUpdate({
  String currentVersion = kAppVersion,
  ReleaseJsonFetcher fetcher = _defaultFetcher,
}) async {
  try {
    final body = await fetcher(Uri.parse(kLatestReleaseApiUrl));
    final info = UpdateInfo.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
    return UpdateCheckResult(
      updateAvailable: isNewerVersion(info.latestVersion, currentVersion),
      info: info,
    );
  } catch (e) {
    return UpdateCheckResult(
      updateAvailable: false,
      error: 'Update check failed: $e',
    );
  }
}
