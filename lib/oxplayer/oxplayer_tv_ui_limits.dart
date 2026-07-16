import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/home_settings_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// TV / leanback UI limits to keep visuals without OOM.
abstract final class OxplayerTvUiLimits {
  /// Home [TVSliderBanner] item count — one backdrop decoded at a time.
  static const int homeSliderMaxItems = 4;

  static bool shouldCapHomeSlider(WidgetRef ref) =>
      ref.read(argumentsStateProvider).leanBackMode;

  static List<ItemBaseModel> capHomeSliderItems(List<ItemBaseModel> items) {
    if (items.length <= homeSliderMaxItems) return items;
    return items.take(homeSliderMaxItems).toList(growable: false);
  }

  static List<ItemBaseModel> capHomeSliderForTv(WidgetRef ref, List<ItemBaseModel> items) {
    if (!shouldCapHomeSlider(ref)) return items;
    return capHomeSliderItems(items);
  }
}

const _kTvVisualDefaultsAppliedKey = 'oxplayer_tv_visual_defaults_v2_applied';

/// Leanback: TV slider (max 4) + library backdrop. Forces tvSliderBanner over carousel.
void oxplayerApplyTvVisualDefaults(WidgetRef ref) {
  if (!OxplayerConfig.isEnabled) return;
  if (!ref.read(argumentsStateProvider).leanBackMode) return;

  final prefs = ref.read(sharedPreferencesProvider);
  final firstRun = prefs.getBool(_kTvVisualDefaultsAppliedKey) != true;
  if (firstRun) {
    prefs.setBool(_kTvVisualDefaultsAppliedKey, true);

    final home = ref.read(homeSettingsProvider);
    if (home.homeBanner == HomeBanner.hide) {
      ref.read(homeSettingsProvider.notifier).update(
            (settings) => settings.copyWith(homeBanner: HomeBanner.tvSliderBanner),
          );
    }

    final client = ref.read(clientSettingsProvider);
    if (client.backgroundImage == BackgroundType.disabled) {
      ref.read(clientSettingsProvider.notifier).update(
            (settings) => settings.copyWith(backgroundImage: BackgroundType.enabled),
          );
    }
  }

  oxplayerEnforceTvHomeBanner(ref);
}

/// Carousel shows every feed item in a row — force TV slider unless user chose hide.
void oxplayerEnforceTvHomeBanner(WidgetRef ref) {
  if (!OxplayerConfig.isEnabled) return;
  if (!ref.read(argumentsStateProvider).leanBackMode) return;

  final home = ref.read(homeSettingsProvider);
  if (home.homeBanner == HomeBanner.hide) return;
  if (home.homeBanner == HomeBanner.tvSliderBanner) return;

  ref.read(homeSettingsProvider.notifier).update(
        (settings) => settings.copyWith(homeBanner: HomeBanner.tvSliderBanner),
      );
}
