import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// Sentry signal when [DetailsScreen] cannot resolve a library item (share/deep link / id-only nav).
abstract final class OxplayerDetailUnavailableTelemetry {
  static DateTime? _lastReportAt;
  static String? _lastItemId;

  static Future<void> report({
    required String itemId,
    required bool hadInlineItem,
    required List<String> fetchTrace,
    required int fetchAttempts,
    required StackRouter router,
    int? lastHttpStatus,
  }) async {
    if (!OxplayerEnv.isEnabled || !Sentry.isEnabled) return;
    if (itemId.isEmpty) return;

    final now = DateTime.now();
    if (_lastItemId == itemId &&
        _lastReportAt != null &&
        now.difference(_lastReportAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastReportAt = now;
    _lastItemId = itemId;

    final nav = _navigationContext(router);

    await Sentry.captureMessage(
      'library detail unavailable: $itemId',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope
          ..setTag('ox.detail', 'unavailable')
          ..setTag('item_id', itemId)
          ..setTag('had_inline_item', hadInlineItem.toString());
        if (lastHttpStatus != null) {
          scope.setTag('http_status', lastHttpStatus.toString());
        }
        scope.setContexts('detail_unavailable', {
          'item_id': itemId,
          'had_inline_item': hadInlineItem,
          'fetch_attempts': fetchAttempts,
          'fetch_trace': fetchTrace,
          if (lastHttpStatus != null) 'last_http_status': lastHttpStatus,
          ...nav,
        });
      },
    );
  }

  static Map<String, Object?> _navigationContext(StackRouter router) {
    final stack = <Map<String, Object?>>[];
    for (final page in router.stack) {
      final routeData = page.routeData;
      final entry = <String, Object?>{
        'name': page.name ?? '',
        'path': routeData.path,
      };
      final query = routeData.queryParams.rawMap;
      if (query.isNotEmpty) {
        entry['query'] = Map<String, String>.from(query);
      }
      final args = routeData.args;
      if (args is DetailsRouteArgs) {
        entry['details_id'] = args.id;
        entry['details_had_item'] = args.item != null;
        if (args.item != null) {
          entry['details_item_type'] = args.item.runtimeType.toString();
        }
      }
      stack.add(entry);
    }

    final current = router.current;
    return {
      'current_route': current.name,
      'current_path': current.path,
      'stack_depth': stack.length,
      'route_stack': stack,
    };
  }
}
