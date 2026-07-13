import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_login_bot_actions.dart';
import 'package:fladder/util/localization_helper.dart';

class OxplayerClaimCodeLoginPanel extends ConsumerStatefulWidget {
  const OxplayerClaimCodeLoginPanel({
    required this.onSuccess,
    this.onBack,
    super.key,
  });

  final Future<void> Function() onSuccess;
  final VoidCallback? onBack;

  @override
  ConsumerState<OxplayerClaimCodeLoginPanel> createState() => _OxplayerClaimCodeLoginPanelState();
}

class _OxplayerClaimCodeLoginPanelState extends ConsumerState<OxplayerClaimCodeLoginPanel> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.localized;
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = l10n.oxplayerLoginCodeInvalid);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await oxplayerAuthenticateWithClaimCode(ref, code);
      if (!mounted) return;
      if (response?.isSuccessful != true || response?.body == null) {
        setState(() => _error = context.localized.oxplayerLoginCodeFailed);
        return;
      }
      await widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.localized;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.oxplayerLoginBack),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          l10n.oxplayerLoginCodeTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.oxplayerLoginCodeHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: l10n.oxplayerLoginCodeLabel, counterText: ''),
          onSubmitted: (_) => _loading ? null : _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.oxplayerLoginContinue),
        ),
        const SizedBox(height: 12),
        const OxplayerLoginBotActions(),
      ],
    );
  }
}
