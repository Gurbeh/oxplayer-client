import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_crashlytics.dart';
import 'package:fladder/oxplayer/oxplayer_sentry.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/crash_screen/crash_screen.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class OxplayerDeveloperModeScreen extends ConsumerWidget {
  const OxplayerDeveloperModeScreen({super.key});

  Future<void> _sendSentryTest(BuildContext context) async {
    await OxplayerSentry.sendTestMessage(source: 'developer_mode');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.localized.oxplayerDeveloperModeSentrySent)),
    );
  }

  void _openErrorLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CrashScreen(),
    );
  }

  void _openStreamCheck(BuildContext context) {
    context.router.push(const OxplayerPlaybackDiagRoute());
  }

  void _triggerCrashlyticsTest(BuildContext context) {
    if (!OxplayerCrashlytics.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.localized.oxplayerDeveloperModeCrashlyticsUnavailable)),
      );
      return;
    }
    OxplayerCrashlytics.triggerTestCrash();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.localized;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.oxplayerDeveloperModeTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.oxplayerDeveloperModeIntro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => _openErrorLogs(context),
            child: Text(l10n.errorLogs),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _sendSentryTest(context),
            child: Text(l10n.oxplayerDeveloperModeCheckSentry),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _openStreamCheck(context),
            child: Text(l10n.oxplayerDeveloperModeCheckStream),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _triggerCrashlyticsTest(context),
            child: Text(l10n.oxplayerDeveloperModeCheckCrashlytics),
          ),
        ],
      ),
    );
  }
}
