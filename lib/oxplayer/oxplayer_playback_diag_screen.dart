import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_playback_diag_runner.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class OxplayerPlaybackDiagScreen extends ConsumerStatefulWidget {
  const OxplayerPlaybackDiagScreen({super.key});

  @override
  ConsumerState<OxplayerPlaybackDiagScreen> createState() => _OxplayerPlaybackDiagScreenState();
}

class _OxplayerPlaybackDiagScreenState extends ConsumerState<OxplayerPlaybackDiagScreen> {
  OxplayerPlaybackDiagRunner? _runner;
  _DiagPhase _phase = _DiagPhase.idle;
  String _statusKey = 'oxplayerPlaybackDiagStatusIdle';
  String? _report;

  @override
  void dispose() {
    _runner?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_phase == _DiagPhase.running) return;
    setState(() {
      _phase = _DiagPhase.running;
      _report = null;
      _statusKey = 'oxplayerPlaybackDiagStatusStarting';
    });

    final runner = OxplayerPlaybackDiagRunner(ref);
    _runner = runner;
    try {
      final text = await runner.run(onPhase: (phase) {
        if (!mounted) return;
        setState(() => _statusKey = _phaseToStatusKey(phase));
      });
      if (!mounted || _phase != _DiagPhase.running) return;
      setState(() {
        _report = text;
        _phase = _DiagPhase.done;
        _statusKey = 'oxplayerPlaybackDiagStatusDone';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _report = '{\n  "error": "${e.runtimeType}"\n}';
        _phase = _DiagPhase.done;
        _statusKey = 'oxplayerPlaybackDiagStatusFailed';
      });
    }
  }

  void _cancel() {
    _runner?.cancel();
    setState(() {
      _phase = _DiagPhase.idle;
      _statusKey = 'oxplayerPlaybackDiagStatusCancelled';
    });
  }

  Future<void> _copy() async {
    final text = _report;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.localized.oxplayerPlaybackDiagCopied)),
    );
  }

  String _localizedStatus(BuildContext context) {
    final l10n = context.localized;
    return switch (_statusKey) {
      'oxplayerPlaybackDiagStatusStarting' => l10n.oxplayerPlaybackDiagStatusStarting,
      'oxplayerPlaybackDiagStatusCollecting' => l10n.oxplayerPlaybackDiagStatusCollecting,
      'oxplayerPlaybackDiagStatusProbing' => l10n.oxplayerPlaybackDiagStatusProbing,
      'oxplayerPlaybackDiagStatusWatching' => l10n.oxplayerPlaybackDiagStatusWatching,
      'oxplayerPlaybackDiagStatusDone' => l10n.oxplayerPlaybackDiagStatusDone,
      'oxplayerPlaybackDiagStatusFailed' => l10n.oxplayerPlaybackDiagStatusFailed,
      'oxplayerPlaybackDiagStatusCancelled' => l10n.oxplayerPlaybackDiagStatusCancelled,
      _ => l10n.oxplayerPlaybackDiagStatusIdle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.localized;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.oxplayerPlaybackDiagTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.oxplayerPlaybackDiagIntro,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _phase == _DiagPhase.running ? IconsaxPlusLinear.timer_1 : IconsaxPlusLinear.info_circle,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_localizedStatus(context))),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _report ?? l10n.oxplayerPlaybackDiagPlaceholder,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Courier New', 'monospace'],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_phase == _DiagPhase.running)
                FilledButton.tonal(
                  onPressed: _cancel,
                  child: Text(l10n.oxplayerPlaybackDiagCancel),
                )
              else if (_phase == _DiagPhase.done)
                FilledButton(
                  onPressed: _copy,
                  child: Text(l10n.oxplayerPlaybackDiagCopy),
                )
              else
                FilledButton(
                  onPressed: _start,
                  child: Text(l10n.oxplayerPlaybackDiagStart),
                ),
              if (_phase == _DiagPhase.done) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _start,
                  child: Text(l10n.oxplayerPlaybackDiagRestart),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _phaseToStatusKey(String phase) => switch (phase) {
        'collecting_context' => 'oxplayerPlaybackDiagStatusCollecting',
        'probing_api' => 'oxplayerPlaybackDiagStatusProbing',
        'watching_playback' => 'oxplayerPlaybackDiagStatusWatching',
        _ => 'oxplayerPlaybackDiagStatusStarting',
      };
}

enum _DiagPhase { idle, running, done }
