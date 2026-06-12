import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_auto_config.dart';

/// Runs [oxplayerMaybeConfigureSeerr] once when the home shell mounts.
class OxplayerSeerrBootstrap extends ConsumerStatefulWidget {
  const OxplayerSeerrBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OxplayerSeerrBootstrap> createState() => _OxplayerSeerrBootstrapState();
}

class _OxplayerSeerrBootstrapState extends ConsumerState<OxplayerSeerrBootstrap> {
  @override
  void initState() {
    super.initState();
    if (OxplayerEnv.isEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) oxplayerMaybeConfigureSeerr(ref);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
