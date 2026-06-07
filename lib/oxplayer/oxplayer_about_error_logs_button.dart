import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_sentry.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_qr_hold.dart';

/// Error logs button with a hidden 5s hold gesture that sends a Sentry test message.
class OxplayerAboutErrorLogsButton extends StatefulWidget {
  const OxplayerAboutErrorLogsButton({
    required this.label,
    required this.onOpenErrorLogs,
    super.key,
  });

  final String label;
  final VoidCallback onOpenErrorLogs;

  @override
  State<OxplayerAboutErrorLogsButton> createState() => _OxplayerAboutErrorLogsButtonState();
}

class _OxplayerAboutErrorLogsButtonState extends State<OxplayerAboutErrorLogsButton> {
  bool _skipNextTap = false;

  Future<void> _onHoldComplete() async {
    _skipNextTap = true;
    await OxplayerSentry.sendTestMessage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sentry test sent')),
    );
  }

  void _onPressed() {
    if (_skipNextTap) {
      _skipNextTap = false;
      return;
    }
    widget.onOpenErrorLogs();
  }

  @override
  Widget build(BuildContext context) {
    return OxplayerTestAccountQrHold(
      onHoldComplete: _onHoldComplete,
      child: FilledButton.tonal(
        onPressed: _onPressed,
        child: Text(widget.label),
      ),
    );
  }
}
