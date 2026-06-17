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

  @override
  String toString() => '$major.$minor.$patch';
}

final class OxOptionalUpdatePrompt {
  const OxOptionalUpdatePrompt({
    required this.currentVersion,
    required this.targetVersion,
    required this.sharedPreferences,
  });

  final String currentVersion;
  final String targetVersion;
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
  }) async {
    if (!OxplayerConfig.isEnabled) return;
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      final targetVersion = await _resolveTargetVersion();
      if (targetVersion == null) {
        developer.log(
          'Play reports an update but no target semver is configured',
          name: 'OxUpdateService',
        );
        return;
      }

      final skipped = sharedPreferences.getString(kOxSkippedVersionKey);
      if (skipped == targetVersion) {
        return;
      }

      final current = OxSemver.parse(currentVersion);
      final target = OxSemver.parse(targetVersion);
      if (current == null || target == null) {
        developer.log(
          'Unable to parse versions (current=$currentVersion target=$targetVersion)',
          name: 'OxUpdateService',
        );
        return;
      }

      if (!target.isNewerThan(current)) {
        return;
      }

      if (target.isMajorUpdateComparedTo(current)) {
        if (updateInfo.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else {
          _pendingOptionalPrompt = OxOptionalUpdatePrompt(
            currentVersion: current.toString(),
            targetVersion: target.toString(),
            sharedPreferences: sharedPreferences,
          );
        }
        return;
      }

      _pendingOptionalPrompt = OxOptionalUpdatePrompt(
        currentVersion: current.toString(),
        targetVersion: target.toString(),
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

  static Future<String?> _resolveTargetVersion() async {
    final fromApi = await _fetchTargetVersionFromBackend();
    if (fromApi != null) return fromApi;
    return _targetVersionFromConfig();
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
    required String targetVersion,
  }) async {
    await sharedPreferences.setString(kOxSkippedVersionKey, targetVersion);
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
        'Version ${prompt.targetVersion} is available. You are on ${prompt.currentVersion}.',
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
              targetVersion: prompt.targetVersion,
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
