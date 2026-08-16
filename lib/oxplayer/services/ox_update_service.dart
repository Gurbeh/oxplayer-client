import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/services/ox_github_update_service.dart';
import 'package:fladder/oxplayer/widgets/ox_dialog_focus_trap.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

const String kOxSkippedVersionKey = 'ox_skipped_version';
const String _kPlayInstallerPackage = 'com.android.vending';

/// Whether this Android install came from the Play Store (vs. a sideloaded APK).
/// Cached after the first check — the installer source cannot change at runtime.
abstract final class OxUpdateSource {
  static bool? _isPlayInstall;

  static Future<bool> isPlayInstall() async {
    final cached = _isPlayInstall;
    if (cached != null) return cached;
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final info = await PackageInfo.fromPlatform();
      final result = info.installerStore == _kPlayInstallerPackage;
      _isPlayInstall = result;
      return result;
    } catch (_) {
      // Unknown installer source — treat as non-Play so the sideload updater takes over.
      return false;
    }
  }
}

/// Parses and compares semantic versions (`major.minor.patch`, optional pre-release ignored).
final class OxSemver {
  const OxSemver(
      {required this.major, required this.minor, required this.patch});

  final int major;
  final int minor;
  final int patch;

  static OxSemver? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final core = trimmed.split('+').first.split('-').first;
    final parts = core.split('.');
    if (parts.isEmpty) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }

    while (numbers.length < 3) {
      numbers.add(0);
    }

    return OxSemver(
      major: numbers[0],
      minor: numbers[1],
      patch: numbers[2],
    );
  }

  bool isNewerThan(OxSemver other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    return patch > other.patch;
  }

  bool isMajorUpdateComparedTo(OxSemver other) => major > other.major;

  /// Inverse of `android/app/build.gradle` `versionCode` formula.
  static OxSemver? fromVersionCode(int code) {
    if (code < 0) return null;

    final major = code ~/ 100000;
    final remainder = code % 100000;
    final minor = remainder ~/ 1000;
    final patch = remainder % 1000;

    if (major == 0 && minor == 0 && patch == 0) return null;

    return OxSemver(major: major, minor: minor, patch: patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

final class OxOptionalUpdatePrompt {
  const OxOptionalUpdatePrompt({
    required this.currentVersion,
    required this.targetVersion,
    required this.skipKey,
    required this.sharedPreferences,
    required this.canUseFlexibleUpdate,
  });

  final String currentVersion;
  final String targetVersion;
  final String skipKey;
  final SharedPreferences sharedPreferences;

  /// Whether "Update" should trigger Play's flexible in-app download instead of
  /// linking out to the Play Store listing.
  final bool canUseFlexibleUpdate;
}

/// Android-only selective in-app update flow (Play binary check + semver policy).
abstract final class OxUpdateService {
  static final http.Client _httpClient = http.Client();

  static OxOptionalUpdatePrompt? _pendingOptionalPrompt;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StackRouter? _router;
  static bool _dialogShowing = false;
  static bool _pendingRestartPrompt = false;

  static bool get hasPendingOptionalPrompt => _pendingOptionalPrompt != null;
  static bool get hasPendingRestartPrompt => _pendingRestartPrompt;

  /// Registered from [MaterialApp.router] so optional-update dialogs use a
  /// context below the route [Navigator] (not [OxUpdatePromptHost], which sits above it).
  static void registerNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Registered from [_FladderApp] so we can wait until splash navigation finishes.
  static void registerRouter(StackRouter router) {
    _router = router;
  }

  static bool _isPastSplashScreen() {
    final router = _router;
    if (router == null) return false;
    return router.current.name != SplashRoute.name;
  }

  /// Called from [OxplayerBootstrap.afterAppBootstrap] before [runApp].
  static Future<void> checkOnLaunch({
    required SharedPreferences sharedPreferences,
    required String currentVersion,
    required String currentBuildNumber,
  }) async {
    if (!OxplayerConfig.isEnabled) return;
    if (kIsWeb || !Platform.isAndroid) return;
    // Sideloaded APK installs can't use the Play in-app update API — OxGitHubUpdateService
    // handles those with a self-hosted download + install flow instead.
    if (!await OxUpdateSource.isPlayInstall()) return;

    try {
      final current = OxSemver.parse(currentVersion) ??
          const OxSemver(major: 0, minor: 0, patch: 0);
      final currentVersionCode = int.tryParse(currentBuildNumber);

      AppUpdateInfo? updateInfo;
      var playCheckFailed = false;
      try {
        updateInfo = await InAppUpdate.checkForUpdate();
      } catch (error, stackTrace) {
        playCheckFailed = true;
        developer.log(
          'Play in-app update check failed; falling back to server semver',
          name: 'OxUpdateService',
          error: error,
          stackTrace: stackTrace,
        );
      }

      // A flexible update from a previous session already finished downloading but was
      // never installed (app was backgrounded, not fully closed) — just nudge to restart.
      if (updateInfo?.installStatus == InstallStatus.downloaded) {
        _pendingRestartPrompt = true;
        return;
      }

      final playReportsUpdate =
          updateInfo?.updateAvailability == UpdateAvailability.updateAvailable;
      final playVersionCode = updateInfo?.availableVersionCode;

      // Trust Play when it reports an update. versionCode can disagree across CI vs
      // pubspec-derived codes, so do not treat a lower Play code as "up to date".
      final playSignalsUpdate = playReportsUpdate &&
          (playVersionCode == null ||
              currentVersionCode == null ||
              playVersionCode > currentVersionCode);

      // Only consult /ox/client/android-update when Play's API itself failed.
      // If Play answered "no update", trust that — GitHub can be ahead of Play rollout.
      OxSemver? backendTarget;
      if (playCheckFailed) {
        final configuredTargets = await _fetchConfiguredTargetSemvers();
        backendTarget = _newestSemver(configuredTargets);
      }
      final backendSignalsUpdate =
          backendTarget != null && backendTarget.isNewerThan(current);

      if (!playSignalsUpdate && !backendSignalsUpdate) {
        return;
      }

      final resolved = playSignalsUpdate && updateInfo != null
          ? await _resolveUpdateTarget(updateInfo: updateInfo)
          : null;

      final targetSemver = _pickTargetSemver(
        resolved: resolved,
        backendTarget: backendTarget,
        playVersionCode: playVersionCode,
      );
      final targetLabel =
          resolved?.displayVersion ?? backendTarget?.toString() ?? 'latest';
      final skipKey = _skipKeyForUpdate(
        playSignalsUpdate: playSignalsUpdate,
        playVersionCode: playVersionCode,
        targetSemver: targetSemver,
        targetLabel: targetLabel,
      );

      if (sharedPreferences.getString(kOxSkippedVersionKey) == skipKey) {
        return;
      }

      if (playSignalsUpdate &&
          updateInfo != null &&
          targetSemver != null &&
          targetSemver.isMajorUpdateComparedTo(current)) {
        if (updateInfo.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
          return;
        }
      }

      // Only Play-confirmed updates can use the flexible in-app flow — a backend-only
      // target (ahead of Play's staged rollout) has nothing for Play to download yet.
      final canUseFlexibleUpdate = playSignalsUpdate &&
          updateInfo != null &&
          updateInfo.flexibleUpdateAllowed;

      _pendingOptionalPrompt = OxOptionalUpdatePrompt(
        currentVersion: current.toString(),
        targetVersion: targetLabel,
        skipKey: skipKey,
        sharedPreferences: sharedPreferences,
        canUseFlexibleUpdate: canUseFlexibleUpdate,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Update check failed',
        name: 'OxUpdateService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static OxSemver? _newestSemver(Iterable<OxSemver> semvers) {
    OxSemver? best;
    for (final candidate in semvers) {
      if (best == null || candidate.isNewerThan(best)) {
        best = candidate;
      }
    }
    return best;
  }

  static OxSemver? _pickTargetSemver({
    required ({
      String displayVersion,
      String skipKey,
      OxSemver? targetSemver
    })? resolved,
    required OxSemver? backendTarget,
    required int? playVersionCode,
  }) {
    final candidates = <OxSemver>[
      if (resolved?.targetSemver != null) resolved!.targetSemver!,
      if (backendTarget != null) backendTarget,
      if (playVersionCode != null)
        if (OxSemver.fromVersionCode(playVersionCode) case final fromPlay?)
          fromPlay,
    ];
    return _newestSemver(candidates);
  }

  static String _skipKeyForUpdate({
    required bool playSignalsUpdate,
    required int? playVersionCode,
    required OxSemver? targetSemver,
    required String targetLabel,
  }) {
    if (playSignalsUpdate && playVersionCode != null) {
      return 'code:$playVersionCode';
    }
    if (targetSemver != null) {
      return 'semver:${targetSemver.toString()}';
    }
    return 'semver:$targetLabel';
  }

  /// Shows a deferred optional-update dialog once the route [Navigator] is mounted
  /// and initial splash → home/login navigation has finished.
  static Future<void> showPendingOptionalPrompt() async {
    final prompt = _pendingOptionalPrompt;
    if (prompt == null || _dialogShowing) return;

    if (!_isPastSplashScreen()) {
      return;
    }

    final context = _navigatorKey?.currentContext;
    if (context == null ||
        !context.mounted ||
        Navigator.maybeOf(context) == null) {
      // Navigator may not exist on the first warm-up frame (see OXPLAYER-CLIENT-X).
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
        builder: (dialogContext) => _OxOptionalUpdateDialog(prompt: prompt),
      );
      _pendingOptionalPrompt = null;
    } finally {
      _dialogShowing = false;
    }
  }

  /// Shows a deferred "restart to install" snackbar for a flexible update that has
  /// already finished downloading.
  static Future<void> showPendingRestartPrompt() async {
    if (!_pendingRestartPrompt) return;
    if (!_isPastSplashScreen()) return;

    final context = _navigatorKey?.currentContext;
    if (context == null ||
        !context.mounted ||
        Navigator.maybeOf(context) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showPendingRestartPrompt();
      });
      return;
    }

    _pendingRestartPrompt = false;
    _showRestartSnackBar();
  }

  /// Starts Play's flexible in-app update: downloads in the background with Play's own
  /// notification UI, then prompts to restart once ready.
  static Future<void> startFlexibleUpdate() async {
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        _showRestartSnackBar();
      }
    } catch (error, stackTrace) {
      developer.log(
        'Flexible update failed',
        name: 'OxUpdateService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void _showRestartSnackBar() {
    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        content: const Text(
          'Update downloaded. Restart to install now — it will otherwise install next time you fully close and reopen the app.',
        ),
        action: SnackBarAction(
          label: 'Restart',
          onPressed: () => InAppUpdate.completeFlexibleUpdate(),
        ),
      ),
    );
  }

  static Future<
          ({String displayVersion, String skipKey, OxSemver? targetSemver})?>
      _resolveUpdateTarget({
    required AppUpdateInfo updateInfo,
  }) async {
    final candidates = <OxSemver>[];

    final playCode = updateInfo.availableVersionCode;
    if (playCode != null) {
      final fromPlay = OxSemver.fromVersionCode(playCode);
      if (fromPlay != null) candidates.add(fromPlay);

      final fromMap = _semverFromVersionMapForCode(playCode);
      if (fromMap != null) candidates.add(fromMap);
    }

    for (final configured in await _fetchConfiguredTargetSemvers()) {
      candidates.add(configured);
    }

    OxSemver? best;
    for (final candidate in candidates) {
      if (best == null || candidate.isNewerThan(best)) {
        best = candidate;
      }
    }

    final skipKey = playCode != null ? 'code:$playCode' : best?.toString();
    if (skipKey == null) return null;

    return (
      displayVersion: best?.toString() ?? 'latest',
      skipKey: skipKey,
      targetSemver: best ??
          (playCode != null ? OxSemver.fromVersionCode(playCode) : null),
    );
  }

  static Future<List<OxSemver>> _fetchConfiguredTargetSemvers() async {
    final semvers = <OxSemver>[];

    final fromApi = await _fetchTargetVersionFromBackend();
    final apiSemver = fromApi == null ? null : OxSemver.parse(fromApi);
    if (apiSemver != null) semvers.add(apiSemver);

    final fromConfig = _targetVersionFromConfig();
    final configSemver = fromConfig == null ? null : OxSemver.parse(fromConfig);
    if (configSemver != null) semvers.add(configSemver);

    return semvers;
  }

  static OxSemver? _semverFromVersionMapForCode(int versionCode) {
    const define = String.fromEnvironment(
      'OXPLAYER_ANDROID_VERSION_MAP',
      defaultValue: '',
    );
    final raw = define.trim().isNotEmpty
        ? define.trim()
        : OxplayerDotenv.get('OXPLAYER_ANDROID_VERSION_MAP').trim();
    if (raw.isEmpty) return null;

    for (final entry in raw.split(',')) {
      final parts = entry.split(':');
      if (parts.length != 2) continue;
      if (int.tryParse(parts[0].trim()) != versionCode) continue;
      return OxSemver.parse(parts[1]);
    }

    return null;
  }

  static Future<String?> _fetchTargetVersionFromBackend() async {
    final base = OxplayerEnv.apiBaseUrl;
    if (base == null) return null;

    try {
      final response = await _httpClient.get(
        Uri.parse('$base/ox/client/android-update'),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      final version = (body['version'] as String?)?.trim();
      if (version == null || version.isEmpty) return null;
      return version;
    } catch (_) {
      return null;
    }
  }

  static String? _targetVersionFromConfig() {
    const define = String.fromEnvironment(
      'OXPLAYER_ANDROID_MARKET_VERSION',
      defaultValue: '',
    );
    final fromDefine = define.trim();
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv =
        OxplayerDotenv.get('OXPLAYER_ANDROID_MARKET_VERSION').trim();
    if (fromEnv.isNotEmpty) return fromEnv;

    return _targetVersionFromMapping();
  }

  /// Optional `versionCode:semver` pairs via `OXPLAYER_ANDROID_VERSION_MAP`.
  ///
  /// Example: `10042:1.2.0,10043:1.2.1`
  static String? _targetVersionFromMapping() {
    const define = String.fromEnvironment(
      'OXPLAYER_ANDROID_VERSION_MAP',
      defaultValue: '',
    );
    final raw = define.trim().isNotEmpty
        ? define.trim()
        : OxplayerDotenv.get('OXPLAYER_ANDROID_VERSION_MAP').trim();
    if (raw.isEmpty) return null;

    final entries = raw.split(',');
    String? highest;
    OxSemver? highestParsed;

    for (final entry in entries) {
      final parts = entry.split(':');
      if (parts.length != 2) continue;
      final semver = OxSemver.parse(parts[1]);
      if (semver == null) continue;
      if (highestParsed == null || semver.isNewerThan(highestParsed)) {
        highestParsed = semver;
        highest = semver.toString();
      }
    }

    return highest;
  }

  static Future<void> openPlayStoreListing() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=${packageInfo.packageName}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> skipVersion({
    required SharedPreferences sharedPreferences,
    required String skipKey,
  }) async {
    await sharedPreferences.setString(kOxSkippedVersionKey, skipKey);
  }
}

class _OxOptionalUpdateDialog extends StatefulWidget {
  const _OxOptionalUpdateDialog({required this.prompt});

  final OxOptionalUpdatePrompt prompt;

  @override
  State<_OxOptionalUpdateDialog> createState() =>
      _OxOptionalUpdateDialogState();
}

class _OxOptionalUpdateDialogState extends State<_OxOptionalUpdateDialog> {
  final FocusNode _primaryActionFocus =
      FocusNode(debugLabel: 'OxUpdatePrimaryAction');

  @override
  void dispose() {
    _primaryActionFocus.dispose();
    super.dispose();
  }

  Future<void> _onUpdate() async {
    final prompt = widget.prompt;
    if (prompt.canUseFlexibleUpdate) {
      // Downloads in the background via Play's own UI — don't block the dialog on it.
      if (mounted) Navigator.of(context).pop();
      unawaited(OxUpdateService.startFlexibleUpdate());
    } else {
      await OxUpdateService.openPlayStoreListing();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _onSkip() async {
    final prompt = widget.prompt;
    await OxUpdateService.skipVersion(
      sharedPreferences: prompt.sharedPreferences,
      skipKey: prompt.skipKey,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.prompt;
    final isDpad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final body = Text(
      prompt.targetVersion == 'latest'
          ? 'A new version is available on Google Play. You are on ${prompt.currentVersion}.'
          : 'Version ${prompt.targetVersion} is available. You are on ${prompt.currentVersion}.',
    );

    final updateButton = isDpad
        ? FilledButton(
            focusNode: _primaryActionFocus,
            autofocus: true,
            onPressed: _onUpdate,
            child: const Text('Update'),
          )
        : TextButton(
            focusNode: _primaryActionFocus,
            onPressed: _onUpdate,
            child: const Text('Update'),
          );
    final laterButton = isDpad
        ? OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Remind Me Later'),
          )
        : TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Remind Me Later'),
          );
    final skipButton = isDpad
        ? OutlinedButton(
            onPressed: _onSkip,
            child: const Text('Skip This Version'),
          )
        : TextButton(
            onPressed: _onSkip,
            child: Text(
              'Skip This Version',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          );

    return OxDialogFocusTrap(
      primaryFocus: _primaryActionFocus,
      child: AlertDialog(
        title: const Text('Update available'),
        content: isDpad
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  const SizedBox(height: 24),
                  updateButton,
                  const SizedBox(height: 8),
                  laterButton,
                  const SizedBox(height: 8),
                  skipButton,
                ],
              )
            : body,
        actionsAlignment: MainAxisAlignment.start,
        actions: isDpad
            ? const <Widget>[]
            : [updateButton, laterButton, skipButton],
      ),
    );
  }
}

/// Retries the optional-update prompt after navigation settles past [SplashRoute].
final class OxUpdatePromptNavigatorObserver extends NavigatorObserver {
  void _scheduleTryShow() {
    if (OxUpdateService.hasPendingOptionalPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        OxUpdateService.showPendingOptionalPrompt();
      });
    }
    if (OxUpdateService.hasPendingRestartPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        OxUpdateService.showPendingRestartPrompt();
      });
    }
    if (OxGitHubUpdateService.hasPendingOptionalPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        OxGitHubUpdateService.showPendingOptionalPrompt();
      });
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _scheduleTryShow();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _scheduleTryShow();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _scheduleTryShow();
}

/// Defers optional-update UI until the widget tree has a [BuildContext].
class OxUpdatePromptHost extends StatefulWidget {
  const OxUpdatePromptHost({required this.child, super.key});

  final Widget child;

  @override
  State<OxUpdatePromptHost> createState() => _OxUpdatePromptHostState();
}

class _OxUpdatePromptHostState extends State<OxUpdatePromptHost> {
  @override
  void initState() {
    super.initState();
    if (!OxplayerConfig.isEnabled || kIsWeb) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (OxUpdateService.hasPendingOptionalPrompt) {
        await OxUpdateService.showPendingOptionalPrompt();
      }
      if (!mounted) return;
      if (OxUpdateService.hasPendingRestartPrompt) {
        await OxUpdateService.showPendingRestartPrompt();
      }
      if (!mounted) return;
      if (OxGitHubUpdateService.hasPendingOptionalPrompt) {
        await OxGitHubUpdateService.showPendingOptionalPrompt();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
