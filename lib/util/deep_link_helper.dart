import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:auto_route/auto_route.dart' show DeepLink, PageRouteInfo;

import 'package:fladder/oxplayer/oxplayer_pending_route.dart';
import 'package:fladder/oxplayer/oxplayer_share.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// Custom URL scheme used by OXPlayer native deep links.
const kOxplayerDeepLinkScheme = 'oxplayer';

FutureOr<DeepLink> deepLinkBuilder(Uri? payload) {
  final route = payloadToRoute(payload);
  if (route != null) {
    final path = pageRouteInfoToPath(route);
    oxplayerBufferPendingPath(path);
    return DeepLink.path(path);
  }
  return DeepLink.defaultPath;
}

class AuthLinkData {
  final String serverUrl;
  final String? seerrUrl;
  final String userName;
  final String? password;

  AuthLinkData({
    required this.serverUrl,
    this.seerrUrl,
    required this.userName,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'server': serverUrl,
        if (seerrUrl != null) 'seerr': seerrUrl,
        'userName': userName,
        if (password != null && password!.isNotEmpty) 'password': password,
      };

  factory AuthLinkData.fromJson(Map<String, dynamic> json) => AuthLinkData(
        serverUrl: json['server'] as String,
        seerrUrl: json['seerr'] as String?,
        userName: json['userName'] as String,
        password: json['password'] as String?,
      );

  static AuthLinkData? parse(String encoded) {
    String removeUrlPrefix = encoded.replaceFirst(RegExp(r'^fladder:\/\/\/login\?authLink='), '');
    try {
      final pad = removeUrlPrefix.length % 4;
      if (pad != 0) {
        removeUrlPrefix = removeUrlPrefix.padRight(removeUrlPrefix.length + (4 - pad), '=');
      }
      final bytes = base64Url.decode(removeUrlPrefix);
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AuthLinkData.fromJson(map);
    } catch (e) {
      log("Failed to parse auth link data: $e");
      return null;
    }
  }

  @override
  String toString() {
    return 'AuthLinkData(serverUrl: $serverUrl, seerrUrl: $seerrUrl, userName: $userName, password: ${password != null ? "****" : null})';
  }
}

String encodeAuthLink(AuthLinkData data) {
  final jsonStr = jsonEncode(data.toJson());
  final bytes = utf8.encode(jsonStr);
  var encoded = base64Url.encode(bytes);
  encoded = encoded.replaceAll('=', '');
  return encoded;
}

String buildAuthUrl(AuthLinkData data) {
  final payload = encodeAuthLink(data);
  return '$kOxplayerDeepLinkScheme:///login?authLink=$payload';
}

PageRouteInfo? payloadToRoute(Uri? payload) {
  if (payload == null) return null;

  final shareId = oxplayerCatalogIdFromShareUri(payload);
  if (shareId != null &&
      (oxplayerIsShareWebHost(payload) ||
          payload.scheme == kOxplayerDeepLinkScheme ||
          payload.scheme == 'fladder')) {
    return DetailsRoute(id: shareId);
  }

  if (payload.path.contains('/login')) {
    final authLink = payload.queryParameters['authLink'];
    if (authLink != null && authLink.isNotEmpty) {
      log("Parsing auth link from payload: $authLink");
      return LoginRoute(authLink: authLink);
    }
    return LoginRoute(authLink: "sdflkj");
  }

  if (payload.path.contains('/seerr')) {
    final segments = payload.pathSegments;
    if (segments.length >= 3) {
      final mediaType = segments[1];
      final tmdbId = int.tryParse(segments[2]);
      if (tmdbId != null) return SeerrDetailsRoute(mediaType: mediaType, tmdbId: tmdbId);
    }
    return const SeerrRoute();
  }
  if (payload.path.contains('/details')) {
    final id = payload.queryParameters['id'];
    if (id != null && id.isNotEmpty) {
      return DetailsRoute(id: id);
    }
  }
  return null;
}

String pageRouteInfoToPath(PageRouteInfo route) {
  try {
    return switch (route) {
      DetailsRoute() => '/details?id=${route.queryParams.get('id')}',
      SeerrDetailsRoute() =>
        '/seerr?mediaType=${route.queryParams.get('mediaType')}&tmdbId=${route.queryParams.get('tmdbId')}',
      LoginRoute() => '/login?authLink=${route.queryParams.get('authLink')}',
      _ => '/',
    };
  } catch (e) {
    log("Failed to convert route to path: $e");
    return route.routeName;
  }
}
