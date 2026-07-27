import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_episode_actions.dart';
import 'package:fladder/oxplayer/ox_series_selected_episode.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/localization_helper.dart';

class OxSeriesEpisodePickerSheet extends ConsumerStatefulWidget {
  final SeriesModel series;
  final ScrollController scrollController;
  final VoidCallback? onEpisodePlayed;

  const OxSeriesEpisodePickerSheet({
    required this.series,
    required this.scrollController,
    this.onEpisodePlayed,
    super.key,
  });

  @override
  ConsumerState<OxSeriesEpisodePickerSheet> createState() => _OxSeriesEpisodePickerSheetState();
}

class _OxSeriesEpisodePickerSheetState extends ConsumerState<OxSeriesEpisodePickerSheet> {
  late final List<OxSeriesPickerSeason> _seasons = oxSeriesPickerSeasons(widget.series);
  OxSeriesPickerSeason? _selectedSeason;

  @override
  void initState() {
    super.initState();
    if (_seasons.length == 1) {
      _selectedSeason = _seasons.first;
    }
  }

  bool get _onEpisodeStep => _selectedSeason != null;

  void _selectSeason(OxSeriesPickerSeason season) {
    setState(() => _selectedSeason = season);
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
  }

  void _backToSeasons() {
    if (_seasons.length <= 1) return;
    setState(() => _selectedSeason = null);
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
  }

  String _seasonListTitle(BuildContext context, OxSeriesPickerSeason season) {
    final l10n = context.localized;
    if (season.name != season.seasonNumber.toString()) {
      return season.name;
    }
    return '${l10n.season(1)} ${season.seasonNumber}';
  }

  String _seasonStepSubtitle(BuildContext context, OxSeriesPickerSeason season) {
    final playable = season.episodes.where((episode) => episode.playAble).length;
    return context.localized.episode(playable);
  }

  Future<void> _playEpisode(EpisodeModel episode) async {
    if (!episode.playAble) return;
    oxSetSeriesSelectedEpisode(ref, widget.series.id, episode);
    if (!mounted) return;
    Navigator.of(context).pop();
    await episode.play(context, ref);
    widget.onEpisodePlayed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.localized;

    return ListView(
      controller: widget.scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              if (_onEpisodeStep && _seasons.length > 1)
                IconButton(
                  onPressed: _backToSeasons,
                  icon: const Icon(IconsaxPlusLinear.arrow_left),
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _onEpisodeStep
                      ? _seasonListTitle(context, _selectedSeason!)
                      : l10n.season(_seasons.length),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_onEpisodeStep)
          ..._episodeTiles(context, _selectedSeason!)
        else
          ..._seasonTiles(context),
      ],
    );
  }

  List<Widget> _seasonTiles(BuildContext context) {
    return _seasons
        .map(
          (season) => FocusButton(
            onTap: () => _selectSeason(season),
            borderRadius: FladderTheme.largeShape.borderRadius,
            child: ListTile(
              leading: CircleAvatar(
                child: Text(season.seasonNumber.toString()),
              ),
              title: Text(_seasonListTitle(context, season)),
              subtitle: Text(_seasonStepSubtitle(context, season)),
              trailing: const Icon(IconsaxPlusLinear.arrow_right_3),
            ),
          ),
        )
        .toList();
  }

  List<Widget> _episodeTiles(BuildContext context, OxSeriesPickerSeason season) {
    final l10n = context.localized;

    return season.episodes
        .map(
          (episode) {
            final playable = episode.playAble;
            return FocusButton(
              onTap: playable ? () => _playEpisode(episode) : null,
              borderRadius: FladderTheme.largeShape.borderRadius,
              child: ListTile(
                enabled: playable,
                leading: CircleAvatar(
                  child: Text(episode.episodeRange),
                ),
                title: Text(episode.name.isEmpty ? 'TBA' : episode.name),
                subtitle: Text(
                  playable
                      ? episode.seasonEpisodeLabel(l10n)
                      : episode.status.label(l10n, episode.overview.dateAdded),
                ),
                trailing: playable
                    ? Icon(
                        IconsaxPlusBold.play,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
            );
          },
        )
        .toList();
  }
}
