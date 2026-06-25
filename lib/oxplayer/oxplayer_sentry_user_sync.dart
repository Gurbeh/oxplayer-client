import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_sentry.dart';
import 'package:fladder/providers/user_provider.dart';

/// Keeps Sentry user context in sync with the signed-in Jellyfin account.
class OxplayerSentryUserSync extends ConsumerStatefulWidget {
  const OxplayerSentryUserSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OxplayerSentryUserSync> createState() => _OxplayerSentryUserSyncState();
}

class _OxplayerSentryUserSyncState extends ConsumerState<OxplayerSentryUserSync> {
  ProviderSubscription<AccountModel?>? _userSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OxplayerSentry.syncUser(ref.read(userProvider));
    });
    _userSub = ref.listenManual<AccountModel?>(userProvider, (prev, next) {
      final prevId = prev?.id;
      final nextId = next?.id;
      if (prevId == nextId) return;
      OxplayerSentry.syncUser(next);
    });
  }

  @override
  void dispose() {
    _userSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
