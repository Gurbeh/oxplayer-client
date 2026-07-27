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
  final VoidCallback? onEpisodePlayed;

  const OxSeriesEpisodePickerSheet({
    required this.series,
    this.onEpisodePlayed,
    super.key,
  });

  @override
  ConsumerState<OxSeriesEpisodePickerSheet> createState() => _OxSeriesEpisodePickerSheetState();
}

class _OxSeriesEpisodePickerSheetState extends ConsumerState<OxSeriesEpisodePickerSheet>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 380);

  late final List<OxSeriesPickerSeason> _seasons = oxSeriesPickerSeasons(widget.series);
  late final AnimationController _slideController;
  late final Animation<double> _slideCurve;
  OxSeriesPickerSeason? _selectedSeason;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(vsync: this, duration: _slideDuration);
    _slideCurve = CurvedAnimation(parent: _slideController, curve: Curves.easeInOutCubic);

    if (_seasons.length == 1) {
      _selectedSeason = _seasons.first;
      _slideController.value = 1;
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _scrollSheetToTop() {
    void jump() {
      if (!mounted) return;
      final position = Scrollable.maybeOf(context)?.position;
      if (position != null && position.hasContentDimensions) {
        position.jumpTo(position.minScrollExtent);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
  }

  void _selectSeason(OxSeriesPickerSeason season) {
    setState(() => _selectedSeason = season);
    _scrollSheetToTop();
    _slideController.forward(from: 0).whenComplete(() {
      if (mounted) _scrollSheetToTop();
    });
  }

  void _backToSeasons() {
    if (_seasons.length <= 1) return;
    _slideController.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() => _selectedSeason = null);
      _scrollSheetToTop();
    });
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
    final l10n = context.localized;
    final showEpisodeHeader = _slideController.value > 0.5 && _selectedSeason != null;

    return PopScope(
      canPop: _slideController.value == 0 && !_slideController.isAnimating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _slideController.value > 0) {
          _backToSeasons();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: _slideCurve,
            builder: (context, _) {
              return _PickerHeader(
                title: showEpisodeHeader
                    ? _seasonListTitle(context, _selectedSeason!)
                    : l10n.season(_seasons.length),
                subtitle: showEpisodeHeader
                    ? l10n.select
                    : l10n.episode(
                        _seasons.fold<int>(0, (sum, season) => sum + season.episodes.length),
                      ),
                showBack: _seasons.length > 1 && _slideController.value > 0,
                onBack: _backToSeasons,
              );
            },
          ),
          if (_seasons.length > 1)
            ClipRect(
              child: AnimatedBuilder(
                animation: _slideCurve,
                builder: (context, _) {
                  final t = _slideCurve.value;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      _SlidePanel(
                        offset: Offset(-t, 0),
                        ignoring: t > 0.5,
                        child: _StepList(children: _seasonTiles(context)),
                      ),
                      if (_selectedSeason != null)
                        _SlidePanel(
                          offset: Offset(1 - t, 0),
                          ignoring: t < 0.5,
                          child: _StepList(children: _episodeTiles(context, _selectedSeason!)),
                        ),
                    ],
                  );
                },
              ),
            )
          else if (_selectedSeason != null)
            _StepList(children: _episodeTiles(context, _selectedSeason!)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _seasonTiles(BuildContext context) {
    return _seasons
        .asMap()
        .entries
        .map(
          (entry) => FocusButton(
            autoFocus: entry.key == 0 && _slideController.value == 0,
            onTap: () => _selectSeason(entry.value),
            borderRadius: FladderTheme.largeShape.borderRadius,
            child: ListTile(
              leading: CircleAvatar(
                child: Text(entry.value.seasonNumber.toString()),
              ),
              title: Text(_seasonListTitle(context, entry.value)),
              subtitle: Text(_seasonStepSubtitle(context, entry.value)),
              trailing: const Icon(IconsaxPlusLinear.arrow_right_3),
            ),
          ),
        )
        .toList();
  }

  List<Widget> _episodeTiles(BuildContext context, OxSeriesPickerSeason season) {
    final l10n = context.localized;

    return season.episodes
        .asMap()
        .entries
        .map(
          (entry) {
            final episode = entry.value;
            final playable = episode.playAble;
            return FocusButton(
              autoFocus: entry.key == 0 && _slideController.value == 1,
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

class _SlidePanel extends StatelessWidget {
  final Offset offset;
  final bool ignoring;
  final Widget child;

  const _SlidePanel({
    required this.offset,
    required this.ignoring,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: ignoring,
      child: FractionalTranslation(
        translation: offset,
        child: child,
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showBack;
  final VoidCallback onBack;

  const _PickerHeader({
    required this.title,
    required this.subtitle,
    required this.showBack,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              if (showBack)
                FocusButton(
                  onTap: onBack,
                  borderRadius: FladderTheme.largeShape.borderRadius,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(IconsaxPlusLinear.arrow_left),
                  ),
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Column(
                    key: ValueKey('$title|$subtitle'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  final List<Widget> children;

  const _StepList({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
