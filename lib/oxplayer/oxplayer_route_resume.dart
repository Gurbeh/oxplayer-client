import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_selector.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
import 'package:fladder/providers/api_provider.dart';

/// Re-probes CDN edges when app resumes (e.g. left Iran → pick global again).
class OxplayerRouteResumeHost extends ConsumerStatefulWidget {
  const OxplayerRouteResumeHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OxplayerRouteResumeHost> createState() => _OxplayerRouteResumeHostState();
}

class _OxplayerRouteResumeHostState extends ConsumerState<OxplayerRouteResumeHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reresolveRoute());
    }
  }

  Future<void> _reresolveRoute() async {
    if (!OxplayerConfig.isEnabled) return;
    final before = OxplayerRoute.active;
    await OxplayerRouteSelector.resolveAtStartup();
    if (!mounted || before == OxplayerRoute.active) return;
    OxplayerStreamNodesApi.invalidateCache();
    ref.invalidate(serverUrlProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
