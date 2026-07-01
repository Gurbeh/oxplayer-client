import 'dart:developer';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_pending_route.dart';
import 'package:fladder/oxplayer/oxplayer_share_deep_link.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/deep_link_helper.dart';
import 'package:protocol_handler/protocol_handler.dart';

/// Windows startup args (e.g. `oxplayer.exe "oxplayer:///share/{id}"`).
List<String> _windowsStartupArgs = const [];

void oxplayerRememberWindowsStartupArgs(List<String> args) {
  _windowsStartupArgs = List.unmodifiable(args);
}

/// Register `oxplayer://` and wire cold-start + live protocol URLs to the router.
Future<OxplayerWindowsDeepLinkListener?> oxplayerSetupWindowsDeepLinks({
  required AutoRouter autoRouter,
}) async {
  if (!OxplayerConfig.isEnabled) return null;

  final listener = OxplayerWindowsDeepLinkListener(autoRouter);
  await listener.init();

  for (final arg in _windowsStartupArgs) {
    listener.handleUrl(arg);
  }

  return listener;
}

final class OxplayerWindowsDeepLinkListener with ProtocolListener {
  OxplayerWindowsDeepLinkListener(this._router);

  final AutoRouter _router;

  Future<void> init() async {
    protocolHandler.addListener(this);
  }

  void dispose() {
    protocolHandler.removeListener(this);
  }

  @override
  void onProtocolUrlReceived(String url) {
    handleUrl(url);
  }

  void handleUrl(String url) {
    final uri = _uriFromDeepLinkArg(url);
    if (uri == null) return;

    final route = payloadToRoute(uri);
    if (route == null) return;

    oxplayerDeepLinkForRoute(route);
    final path = pageRouteInfoToPath(route);
    log('OXPlayer Windows deep link → $path');

    try {
      if (route is DetailsRoute) {
        _router.replaceAll([
          HomeRoute(children: [route]),
        ]);
      } else {
        _router.navigatePath(path);
      }
    } catch (e, st) {
      log('Windows deep link navigation failed: $e', stackTrace: st);
    }
  }
}

Uri? _uriFromDeepLinkArg(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('$kOxplayerDeepLinkScheme://') || trimmed.startsWith('fladder://')) {
    return Uri.tryParse(trimmed);
  }
  return null;
}
