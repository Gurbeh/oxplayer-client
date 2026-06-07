import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_test_account_qr_hold.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/localization_helper.dart';

void showOxplayerBotQrSheet(
  BuildContext context, {
  required String telegramLink,
  String? botUsername,
  VoidCallback? onQrHoldComplete,
  bool qrHoldEnabled = true,
}) {
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!rootContext.mounted) return;
    showModalBottomSheet<void>(
      context: rootContext,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final l10n = sheetContext.localized;
        final bottom = MediaQuery.paddingOf(sheetContext).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  botUsername != null ? '@$botUsername' : l10n.oxplayerHelpTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.oxplayerHelpQrCaption,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _loginQrImage(
                  telegramLink: telegramLink,
                  onQrHoldComplete: onQrHoldComplete,
                  qrHoldEnabled: qrHoldEnabled,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => launchUrl(sheetContext, telegramLink),
                  child: Text(l10n.oxplayerHelpOpenBot(botUsername ?? '')),
                ),
              ],
            ),
          ),
        );
      },
    );
  });
}

Widget _loginQrImage({
  required String telegramLink,
  VoidCallback? onQrHoldComplete,
  required bool qrHoldEnabled,
}) {
  final qr = QrImageView(
    data: telegramLink,
    size: 200,
    version: QrVersions.auto,
    backgroundColor: Colors.white,
  );
  if (onQrHoldComplete == null) return qr;
  return OxplayerTestAccountQrHold(
    enabled: qrHoldEnabled,
    onHoldComplete: onQrHoldComplete,
    child: qr,
  );
}
