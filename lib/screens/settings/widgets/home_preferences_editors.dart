import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/home_preferences_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/ox_home_dashboard_order.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/widgets/settings_label_divider.dart';
import 'package:fladder/screens/settings/widgets/settings_list_group.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/sortable_item_list.dart';

class LibraryOrderEditor extends ConsumerWidget {
  const LibraryOrderEditor({
    super.key,
    this.groupedFoldersOnly = false,
    this.showGroupedFoldersSection = true,
  });

  /// When true, only the grouped-libraries section is shown (OXPlayer).
  final bool groupedFoldersOnly;

  /// When false, the grouped-libraries section is omitted.
  final bool showGroupedFoldersSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(homePreferencesProvider);
    final views = ref.watch(viewsProvider).views;
    final orderedIds = preferences.orderedLibraryIds;
    final includedIds = orderedIds.where((id) => !preferences.latestItemsExcludes.contains(id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!groupedFoldersOnly) ...[
          ...settingsListGroup(
            context,
            SettingsLabelDivider(label: context.localized.libraryOrderTitle),
            [
              SettingsListTile(
                label: Text(
                  context.localized.libraryOrderDescription,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SortableItemList<String>(
                items: orderedIds,
                included: includedIds,
                itemBuilder: (id) {
                  final dashboardLabel =
                      OxplayerConfig.isEnabled ? OxHomeDashboardOrder.label(context, id) : null;
                  if (dashboardLabel != null) return Text(dashboardLabel);
                  final view = views.firstWhereOrNull((v) => v.id == id);
                  return Text(view?.name ?? id);
                },
                onReorder: (reordered) {
                  ref.read(homePreferencesProvider.notifier).setOrderedLibraryIds(reordered);
                },
                onIncludeChange: (included) {
                  final excluded = orderedIds.where((id) => !included.contains(id)).toList();
                  ref.read(homePreferencesProvider.notifier).setLatestItemsExcludes(excluded);
                },
              ),
              SettingsListTileCheckbox(
                label: Text(context.localized.hidePlayedInLatestTitle),
                subLabel: Text(context.localized.hidePlayedInLatestDescription),
                value: preferences.hidePlayedInLatest,
                onChanged: (value) {
                  ref.read(homePreferencesProvider.notifier).setHidePlayedInLatest(value ?? false);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (showGroupedFoldersSection) ...[
          ...settingsListGroup(
            context,
            SettingsLabelDivider(label: context.localized.groupedFoldersTitle),
            [
              SettingsListTile(
                label: Text(
                  context.localized.groupedFoldersDescription,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              ...preferences.availableFolders.map((folder) {
                final isGrouped = preferences.groupedFolders.contains(folder.id);
                return SettingsListTileCheckbox(
                  label: Text(folder.name),
                  value: isGrouped,
                  onChanged: (value) {
                    final updated = [...preferences.groupedFolders];
                    if (value == true) {
                      if (!updated.contains(folder.id)) updated.add(folder.id);
                    } else {
                      updated.remove(folder.id);
                    }
                    ref.read(homePreferencesProvider.notifier).setGroupedFolders(updated);
                  },
                );
              }),
            ],
          ),
        ],
      ],
    );
  }
}
