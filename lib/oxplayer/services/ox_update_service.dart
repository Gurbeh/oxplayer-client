import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

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

const String kOxSkippedVersionKey = 'ox_skipped_version';

/// Parses and compares semantic versions (`major.minor.patch`, optional pre-release ignored).
final class OxSemver {
  const OxSemver({required this.major, required this.minor, required this.patch});

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
  });

  final String currentVersion;
  final String targetVersion;
  final String skipKey;
  final SharedPreferences sharedPreferences;
}

/// Android-only selective in-app update flow (Play binary check + semver policy).
abstract final class OxUpdateService {
  static final http.Client _httpClient = http.Client();

  static OxOptionalUpdatePrompt? _pendingOptionalPrompt;

  static bool get hasPendingOptionalPrompt => _pendingOptionalPrompt != null;

  /// Called from [OxplayerBootstrap.afterAppBootstrap] before [runApp].
  static Future<void> checkOnLaunch({
    required SharedPreferences sharedPreferences,
    required String currentVersion,
    required String currentBuildNumber,
  }) async {
    if (!OxplayerConfig.isEnabled) return;
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final current = OxSemver.parse(currentVersion) ?? const OxSemver(major: 0, minor: 0, patch: 0);
      final currentVersionCode = int.tryParse(currentBuildNumber);

      AppUpdateInfo? updateInfo;
      try {
        updateInfo = await InAppUpdate.checkForUpdate();
      } catch (error, stackTrace) {
        developer.log(
          'Play in-app update check failed; falling back to server semver',
          name: 'OxUpdateService',
          error: error,
          stackTrace: stackTrace,
        );
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

      final configuredTargets = await _fetchConfiguredTargetSemvers();
      final backendTarget = _newestSemver(configuredTargets);
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
      final targetLabel = resolved?.displayVersion ?? backendTarget?.toString() ?? 'latest';
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

      _pendingOptionalPrompt = OxOptionalUpdatePrompt(
        currentVersion: current.toString(),
        targetVersion: targetLabel,
        skipKey: skipKey,
        sharedPreferences: sharedPreferences,
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
    required ({String displayVersion, String skipKey, OxSemver? targetSemver})? resolved,
    required OxSemver? backendTarget,
    required int? playVersionCode,
  }) {
    final candidates = <OxSemver>[
      if (resolved?.targetSemver != null) resolved!.targetSemver!,
      if (backendTarget != null) backendTarget,
      if (playVersionCode != null)
        if (OxSemver.fromVersionCode(playVersionCode) case final fromPlay?) fromPlay,
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

  /// Shows a deferred optional-update dialog once a [BuildContext] is available.
  static Future<void> showPendingOptionalPrompt(BuildContext context) async {
    final prompt = _pendingOptionalPrompt;
    if (prompt == null || !context.mounted) return;

    _pendingOptionalPrompt = null;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _OxOptionalUpdateDialog(prompt: prompt),
    );
  }

  static Future<({String displayVersion, String skipKey, OxSemver? targetSemver})?> _resolveUpdateTarget({
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
      targetSemver: best ?? (playCode != null ? OxSemver.fromVersionCode(playCode) : null),
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
      final response = await _httpClient
          .get(
            Uri.parse('$base/ox/client/android-update'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

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

    final fromEnv = OxplayerDotenv.get('OXPLAYER_ANDROID_MARKET_VERSION').trim();
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

class _OxOptionalUpdateDialog extends StatelessWidget {
  const _OxOptionalUpdateDialog({required this.prompt});

  final OxOptionalUpdatePrompt prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Update available'),
      content: Text(
        prompt.targetVersion == 'latest'
            ? 'A new version is available on Google Play. You are on ${prompt.currentVersion}.'
            : 'Version ${prompt.targetVersion} is available. You are on ${prompt.currentVersion}.',
      ),
      actionsAlignment: MainAxisAlignment.start,
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () async {
            await OxUpdateService.openPlayStoreListing();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Update'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Remind Me Later'),
        ),
        TextButton(
          onPressed: () async {
            await OxUpdateService.skipVersion(
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
    if (!OxplayerConfig.isEnabled || kIsWeb || !Platform.isAndroid) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !OxUpdateService.hasPendingOptionalPrompt) return;
      await OxUpdateService.showPendingOptionalPrompt(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
