import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/services/ox_update_service.dart';
import 'package:fladder/routes/auto_router.gr.dart';

const String kOxGithubSkippedVersionKey = 'ox_github_skipped_version';

final class OxGitHubUpdatePrompt {
  const OxGitHubUpdatePrompt({
    required this.currentVersion,
    required this.targetVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.releasePageUrl,
    required this.skipKey,
    required this.sharedPreferences,
  });

  final String currentVersion;
  final String targetVersion;
  final String changelog;
  final String? downloadUrl;
  final String releasePageUrl;
  final String skipKey;
  final SharedPreferences sharedPreferences;
}

/// Desktop update check via GitHub Releases — opens the platform installer externally.
abstract final class OxGitHubUpdateService {
  static final http.Client _httpClient = http.Client();

  static OxGitHubUpdatePrompt? _pendingOptionalPrompt;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StackRouter? _router;
  static bool _dialogShowing = false;

  static bool get hasPendingOptionalPrompt => _pendingOptionalPrompt != null;

  static void registerNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  static void registerRouter(StackRouter router) {
    _router = router;
  }

  static bool _isPastSplashScreen() {
    final router = _router;
    if (router == null) return false;
    return router.current.name != SplashRoute.name;
  }

  static String get _githubRepoSlug {
    const define = String.fromEnvironment('OXPLAYER_GITHUB_REPO', defaultValue: '');
    final fromDefine = define.trim();
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv = OxplayerDotenv.get('OXPLAYER_GITHUB_REPO').trim();
    if (fromEnv.isNotEmpty) return fromEnv;

    return 'Gurbeh/oxplayer-client';
  }

  static Future<void> checkOnLaunch({
    required SharedPreferences sharedPreferences,
    required String currentVersion,
  }) async {
    if (!OxplayerConfig.isEnabled) return;
    if (kIsWeb || !_isDesktopPlatform) return;

    try {
      final current = OxSemver.parse(currentVersion) ?? const OxSemver(major: 0, minor: 0, patch: 0);
      final release = await _fetchLatestStableRelease();
      if (release == null) return;

      final target = OxSemver.parse(release.version);
      if (target == null || !target.isNewerThan(current)) return;

      final skipKey = 'semver:${release.version}';
      if (sharedPreferences.getString(kOxGithubSkippedVersionKey) == skipKey) {
        return;
      }

      _pendingOptionalPrompt = OxGitHubUpdatePrompt(
        currentVersion: current.toString(),
        targetVersion: release.version,
        changelog: release.changelog,
        downloadUrl: release.downloadUrl,
        releasePageUrl: release.releasePageUrl,
        skipKey: skipKey,
        sharedPreferences: sharedPreferences,
      );
    } catch (error, stackTrace) {
      developer.log(
        'GitHub update check failed',
        name: 'OxGitHubUpdateService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<({String version, String changelog, String? downloadUrl, String releasePageUrl})?>
      _fetchLatestStableRelease() async {
    final slug = _githubRepoSlug;
    final response = await _httpClient
        .get(
          Uri.parse('https://api.github.com/repos/$slug/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;

    final tag = (body['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '').trim();
    if (tag == null || tag.isEmpty) return null;

    final changelog = (body['body'] as String?)?.trim() ?? '';
    final releasePageUrl = (body['html_url'] as String?)?.trim() ?? 'https://github.com/$slug/releases/latest';
    final assets = body['assets'] as List<dynamic>? ?? [];

    final downloadUrl = _resolveDownloadUrl(assets);
    return (
      version: tag,
      changelog: changelog,
      downloadUrl: downloadUrl,
      releasePageUrl: releasePageUrl,
    );
  }

  static String? _resolveDownloadUrl(List<dynamic> assets) {
    final patterns = _downloadPatternsForPlatform();
    if (patterns.isEmpty) return null;

    for (final pattern in patterns) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String? ?? '';
        if (url.isEmpty) continue;
        if (pattern.hasMatch(name)) return url;
      }
    }

    return null;
  }

  static List<RegExp> _downloadPatternsForPlatform() {
    if (Platform.isWindows) {
      return [
        RegExp(r'^OXPlayer-Windows-.+-Setup\.exe$'),
        RegExp(r'^OXPlayer-Windows-.+\.zip$'),
      ];
    }
    if (Platform.isMacOS) {
      return [RegExp(r'^OXPlayer-macOS-.+\.dmg$')];
    }
    if (Platform.isLinux) {
      return [
        RegExp(r'^OXPlayer-Linux-.+\.AppImage$'),
        RegExp(r'^OXPlayer-Linux-.+\.flatpak$'),
        RegExp(r'^OXPlayer-Linux-.+\.zip$'),
      ];
    }
    return const [];
  }

  static Future<void> showPendingOptionalPrompt() async {
    final prompt = _pendingOptionalPrompt;
    if (prompt == null || _dialogShowing) return;

    if (!_isPastSplashScreen()) return;

    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted || Navigator.maybeOf(context) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showPendingOptionalPrompt();
      });
      return;
    }

    _dialogShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) => _OxGitHubOptionalUpdateDialog(prompt: prompt),
      );
      _pendingOptionalPrompt = null;
    } finally {
      _dialogShowing = false;
    }
  }

  static Future<void> openDownloadPage({
    required String? downloadUrl,
    required String releasePageUrl,
  }) async {
    final target = (downloadUrl != null && downloadUrl.isNotEmpty) ? downloadUrl : releasePageUrl;
    final uri = Uri.parse(target);
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> skipVersion({
    required SharedPreferences sharedPreferences,
    required String skipKey,
  }) async {
    await sharedPreferences.setString(kOxGithubSkippedVersionKey, skipKey);
  }
}

class _OxGitHubOptionalUpdateDialog extends StatelessWidget {
  const _OxGitHubOptionalUpdateDialog({required this.prompt});

  final OxGitHubUpdatePrompt prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changelog = prompt.changelog.trim();
    final preview = changelog.isEmpty
        ? ''
        : changelog.length > 400
            ? '${changelog.substring(0, 400).trim()}…'
            : changelog;

    return AlertDialog(
      title: const Text('Update available'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Version ${prompt.targetVersion} is available. You are on ${prompt.currentVersion}.',
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                preview,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.start,
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () async {
            await OxGitHubUpdateService.openDownloadPage(
              downloadUrl: prompt.downloadUrl,
              releasePageUrl: prompt.releasePageUrl,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Download'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Remind Me Later'),
        ),
        TextButton(
          onPressed: () async {
            await OxGitHubUpdateService.skipVersion(
              sharedPreferences: prompt.sharedPreferences,
              skipKey: prompt.skipKey,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(
            'Skip This Version',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
