import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_auto_config.dart';
import 'package:fladder/providers/user_provider.dart';

/// Runs [oxplayerMaybeConfigureSeerr] when the home shell mounts and when the user
/// session becomes available (first login after token is set).
class OxplayerSeerrBootstrap extends ConsumerStatefulWidget {
  const OxplayerSeerrBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OxplayerSeerrBootstrap> createState() => _OxplayerSeerrBootstrapState();
}

class _OxplayerSeerrBootstrapState extends ConsumerState<OxplayerSeerrBootstrap> {
  ProviderSubscription<AccountModel?>? _userSub;

  @override
  void initState() {
    super.initState();
    if (OxplayerEnv.isEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) oxplayerMaybeConfigureSeerr(ref);
      });
      _userSub = ref.listenManual<AccountModel?>(userProvider, (prev, next) {
        if (next == null) return;
        if (next.seerrCredentials?.isConfigured == true) return;
        final prevToken = prev?.credentials.token.trim() ?? '';
        final nextToken = next.credentials.token.trim();
        if (nextToken.isEmpty) return;
        if (prevToken != nextToken || prev == null) {
          oxplayerMaybeConfigureSeerr(ref);
        }
      });
    }
  }

  @override
  void dispose() {
    _userSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
