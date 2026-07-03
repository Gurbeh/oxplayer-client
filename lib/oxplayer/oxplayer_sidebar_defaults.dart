import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

const _kSidebarDefaultAppliedKey = 'oxplayer_expand_sidebar_default_applied';

/// On first install, expand the navigation sidebar on TV and tablet layouts.
/// After the user toggles it, [ClientSettingsModel.expandSideBar] is persisted as usual.
void oxplayerApplySidebarDefaults(WidgetRef ref, BuildContext context) {
  if (!OxplayerConfig.isEnabled) return;

  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getBool(_kSidebarDefaultAppliedKey) == true) return;

  final hasExistingSettings = _hasPersistedClientSettings(prefs.getString('clientSettings'));
  prefs.setBool(_kSidebarDefaultAppliedKey, true);

  if (hasExistingSettings) return;
  if (!_shouldDefaultExpandSidebar(context, ref)) return;

  ref.read(clientSettingsProvider.notifier).update(
        (settings) => settings.copyWith(expandSideBar: true),
      );
}

bool _hasPersistedClientSettings(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> && decoded.isNotEmpty;
  } catch (_) {
    return false;
  }
}

bool _shouldDefaultExpandSidebar(BuildContext context, WidgetRef ref) {
  final arguments = ref.read(argumentsStateProvider);
  if (arguments.leanBackMode || arguments.htpcMode) return true;

  final viewSize = AdaptiveLayout.layoutOf(context);
  return viewSize == ViewSize.tablet || viewSize == ViewSize.television;
}
