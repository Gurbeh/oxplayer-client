import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

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

/// Update check via GitHub Releases for Windows/macOS/Linux and sideloaded (non-Play)
/// Android installs. Windows and Android download in the background and install
/// themselves; macOS/Linux fall back to opening the release asset externally.
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
    const define =
        String.fromEnvironment('OXPLAYER_GITHUB_REPO', defaultValue: '');
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
    if (kIsWeb || !await _isSupportedPlatform()) return;

    try {
      final current = OxSemver.parse(currentVersion) ??
          const OxSemver(major: 0, minor: 0, patch: 0);
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

  /// Desktop always qualifies; Android only when the app wasn't installed via Play
  /// (Play-installed users are handled by [OxUpdateService]'s flexible update flow).
  static Future<bool> _isSupportedPlatform() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return true;
    if (Platform.isAndroid) return !await OxUpdateSource.isPlayInstall();
    return false;
  }

  /// Windows and Android download the release asset in-app and install it themselves;
  /// macOS/Linux still hand off to the browser (no unattended-install story there).
  static bool get _supportsInAppInstall =>
      Platform.isWindows || Platform.isAndroid;

  static Future<
      ({
        String version,
        String changelog,
        String? downloadUrl,
        String releasePageUrl
      })?> _fetchLatestStableRelease() async {
    final slug = _githubRepoSlug;
    final response = await _httpClient.get(
      Uri.parse('https://api.github.com/repos/$slug/releases/latest'),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;

    final tag =
        (body['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '').trim();
    if (tag == null || tag.isEmpty) return null;

    final changelog = (body['body'] as String?)?.trim() ?? '';
    final releasePageUrl = (body['html_url'] as String?)?.trim() ??
        'https://github.com/$slug/releases/latest';
    final assets = body['assets'] as List<dynamic>? ?? [];

    final downloadUrl = await _resolveDownloadUrl(assets);
    return (
      version: tag,
      changelog: changelog,
      downloadUrl: downloadUrl,
      releasePageUrl: releasePageUrl,
    );
  }

  /// Public R2 origin for stable latest binaries (same as website `/dl/*` redirects).
  /// GitHub `objects.githubusercontent.com` often stalls at 100% for end users.
  static const String _releasesCdnOrigin =
      'https://pub-620251e8a4724a0b8a0b01903c727616.r2.dev';

  static Future<String?> _resolveDownloadUrl(List<dynamic> assets) async {
    final r2Url = await _r2LatestUrlForPlatform();
    if (r2Url != null) return r2Url;

    final patterns = await _downloadPatternsForPlatform();
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

  static Future<String?> _r2LatestUrlForPlatform() async {
    if (Platform.isWindows) {
      return '$_releasesCdnOrigin/releases/latest/OXPlayer-Windows-Setup.exe';
    }
    if (Platform.isMacOS) {
      return '$_releasesCdnOrigin/releases/latest/OXPlayer-macOS.dmg';
    }
    if (Platform.isLinux) {
      return '$_releasesCdnOrigin/releases/latest/OXPlayer-Linux.AppImage';
    }
    if (Platform.isAndroid) {
      final abis = await _androidSupportedAbis();
      const published = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};
      for (final abi in abis) {
        if (published.contains(abi)) {
          return '$_releasesCdnOrigin/releases/latest/OXPlayer-Android-$abi.apk';
        }
      }
      return '$_releasesCdnOrigin/releases/latest/OXPlayer-Android-arm64-v8a.apk';
    }
    return null;
  }

  static Future<List<RegExp>> _downloadPatternsForPlatform() async {
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
    if (Platform.isAndroid) {
      final abis = await _androidSupportedAbis();
      return [
        for (final abi in abis)
          RegExp('^OXPlayer-Android-.+-${RegExp.escape(abi)}\\.apk\$'),
        // Fallback if ABI detection fails or reports an architecture we don't publish.
        RegExp(r'^OXPlayer-Android-.+-arm64-v8a\.apk$'),
      ];
    }
    return const [];
  }

  static Future<List<String>> _androidSupportedAbis() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.supportedAbis;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> showPendingOptionalPrompt() async {
    final prompt = _pendingOptionalPrompt;
    if (prompt == null || _dialogShowing) return;

    if (!_isPastSplashScreen()) return;

    final context = _navigatorKey?.currentContext;
    if (context == null ||
        !context.mounted ||
        Navigator.maybeOf(context) == null) {
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
        builder: (dialogContext) =>
            _OxGitHubOptionalUpdateDialog(prompt: prompt),
      );
      _pendingOptionalPrompt = null;
    } finally {
      _dialogShowing = false;
    }
  }

  /// Shows the in-app download/install progress dialog. Only valid when
  /// [_supportsInAppInstall] and [OxGitHubUpdatePrompt.downloadUrl] is set.
  static void showDownloadProgressDialog(OxGitHubUpdatePrompt prompt) {
    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _OxDownloadProgressDialog(
        downloadUrl: prompt.downloadUrl!,
        releasePageUrl: prompt.releasePageUrl,
      ),
    );
  }

  static Future<void> openDownloadPage({
    required String? downloadUrl,
    required String releasePageUrl,
  }) async {
    final target = (downloadUrl != null && downloadUrl.isNotEmpty)
        ? downloadUrl
        : releasePageUrl;
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
    final hasInAppInstall = OxGitHubUpdateService._supportsInAppInstall &&
        (prompt.downloadUrl?.isNotEmpty ?? false);

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
            if (hasInAppInstall) {
              if (context.mounted) Navigator.of(context).pop();
              OxGitHubUpdateService.showDownloadProgressDialog(prompt);
            } else {
              await OxGitHubUpdateService.openDownloadPage(
                downloadUrl: prompt.downloadUrl,
                releasePageUrl: prompt.releasePageUrl,
              );
              if (context.mounted) Navigator.of(context).pop();
            }
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

enum _OxUpdateDownloadState { downloading, installing, error }

/// Downloads the release asset with a visible progress bar, then installs it:
/// silently (Windows, via the Inno Setup `/VERYSILENT` flags) or by handing the
/// downloaded APK to the system installer (Android).
class _OxDownloadProgressDialog extends StatefulWidget {
  const _OxDownloadProgressDialog({
    required this.downloadUrl,
    required this.releasePageUrl,
  });

  final String downloadUrl;
  final String releasePageUrl;

  @override
  State<_OxDownloadProgressDialog> createState() =>
      _OxDownloadProgressDialogState();
}

class _OxDownloadProgressDialogState extends State<_OxDownloadProgressDialog> {
  double? _progress;
  _OxUpdateDownloadState _state = _OxUpdateDownloadState.downloading;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final segments = Uri.parse(widget.downloadUrl).pathSegments;
      final filename = segments.isNotEmpty ? segments.last : 'oxplayer_update';

      final task = DownloadTask(
        url: widget.downloadUrl,
        filename: filename,
        baseDirectory: BaseDirectory.temporary,
        updates: Updates.statusAndProgress,
      );

      final result = await FileDownloader().download(
        task,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() =>
              _progress = progress >= 0 && progress <= 1 ? progress : null);
        },
      );

      if (result.status != TaskStatus.complete) {
        throw StateError('Update download ended with status ${result.status}');
      }

      if (!mounted) return;
      setState(() => _state = _OxUpdateDownloadState.installing);

      if (Platform.isAndroid) {
        final opened = await FileDownloader().openFile(
          task: task,
          mimeType: 'application/vnd.android.package-archive',
        );
        if (!opened) {
          throw StateError('Could not launch the Android package installer');
        }
      } else if (Platform.isWindows) {
        final filePath = await task.filePath();
        await Process.start(
          filePath,
          [
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/CLOSEAPPLICATIONS',
            '/RESTARTAPPLICATIONS'
          ],
          mode: ProcessStartMode.detached,
        );
        await windowManager.close();
        return;
      }

      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      developer.log(
        'In-app update install failed',
        name: 'OxGitHubUpdateService',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _state = _OxUpdateDownloadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isError = _state == _OxUpdateDownloadState.error;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(isError ? 'Update failed' : 'Downloading update'),
        content: isError
            ? const Text(
                'The update could not be downloaded automatically. You can download it from the browser instead.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 12),
                  Text(
                    _state == _OxUpdateDownloadState.installing
                        ? 'Starting installer…'
                        : '${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
        actionsAlignment: MainAxisAlignment.start,
        actions: isError
            ? [
                TextButton(
                  autofocus: true,
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await OxGitHubUpdateService.openDownloadPage(
                      downloadUrl: widget.downloadUrl,
                      releasePageUrl: widget.releasePageUrl,
                    );
                  },
                  child: const Text('Open in Browser'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ]
            : const [],
      ),
    );
  }
}
