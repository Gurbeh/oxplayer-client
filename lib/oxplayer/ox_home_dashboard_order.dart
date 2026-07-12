import 'package:flutter/widgets.dart';

import 'package:fladder/util/localization_helper.dart';

/// Virtual OrderedViews ids for OX-only home dashboard rows (not Jellyfin library folders).
abstract final class OxHomeDashboardOrder {
  static const tvViewId = '00000000-0000-0000-0000-000000000002';
  static const watchLaterId = '00000000-0000-0000-0000-000000000006';
  static const favoritesId = '00000000-0000-0000-0000-000000000007';

  static const dashboardRowIds = [watchLaterId, favoritesId];

  static bool isDashboardRowId(String id) => id == watchLaterId || id == favoritesId;

  static String? label(BuildContext context, String id) {
    return switch (id) {
      watchLaterId => context.localized.oxplayerWatchlist,
      favoritesId => context.localized.favorites,
      _ => null,
    };
  }

  /// Library folder ids plus dashboard rows for the home-order editor.
  static List<String> allOrderableIds(List<String> libraryIds) {
    final out = <String>[...libraryIds];
    _insertRowIfMissing(out, watchLaterId);
    _insertRowIfMissing(out, favoritesId);
    return out;
  }

  static void _insertRowIfMissing(List<String> out, String rowId) {
    if (out.contains(rowId)) return;
    if (rowId == favoritesId) {
      final watchLaterIndex = out.indexOf(watchLaterId);
      if (watchLaterIndex >= 0) {
        out.insert(watchLaterIndex + 1, rowId);
        return;
      }
    }
    if (rowId == watchLaterId) {
      final tvIndex = out.indexOf(tvViewId);
      out.insert(tvIndex >= 0 ? tvIndex + 1 : out.length, rowId);
      return;
    }
    out.add(rowId);
  }
}
