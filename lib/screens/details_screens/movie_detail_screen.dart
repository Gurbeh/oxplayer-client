import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/movies_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/oxplayer/ox_library_detail_labels.dart';
import 'package:fladder/oxplayer/oxplayer_detail_loading.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_media_streams.dart';
import 'package:fladder/oxplayer/oxplayer_media_variant.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/widgets/ox_detail_action_layout.dart';
import 'package:fladder/oxplayer/widgets/ox_movie_boxset_row.dart';
import 'package:fladder/oxplayer/widgets/ox_movie_request_button.dart';
import 'package:fladder/oxplayer/widgets/ox_seerr_people_row.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/chapter_row.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/media/special_features_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/util/widget_extensions.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const MovieDetailScreen({required this.item, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<MovieDetailScreen> {
  MovieDetailsProvider get providerInstance =>
      movieDetailsProvider(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerInstance);
    final wrapAlignment = AdaptiveLayout.viewSizeOf(context) != ViewSize.phone
        ? WrapAlignment.start
        : WrapAlignment.center;
    final hasPlayableMedia = details != null && oxMovieHasPlayableMedia(details);
    final showMovieRequest = OxplayerEnv.isEnabled &&
        details?.overview.seerrUrl?.isNotEmpty == true &&
        details?.tmdbId != null &&
        !hasPlayableMedia;

    return DetailScaffold(
      label: widget.item.name,
      item: details,
      actions: (context) => details?.generateActions(
        context,
        ref,
        exclude: {
          ItemActions.play,
          ItemActions.playFromStart,
          ItemActions.details,
        },
        onDeleteSuccesFully: (item) {
          if (context.mounted) {
            context.router.popBack();
          }
        },
      ),
      onRefresh: () async =>
          await ref.read(providerInstance.notifier).fetchDetails(widget.item),
      backDrops: details?.images,
      content: (detailsContext, padding) => details != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OverviewHeader(
                    name: details.name,
                    image: details.images,
                    padding: padding,
                    mainButton: hasPlayableMedia
                        ? MediaPlayButton(
                            item: details,
                            onLongPressed: (restart) async {
                              await details.play(
                                detailsContext,
                                ref,
                                showPlaybackOption: true,
                                startPosition: restart ? Duration.zero : null,
                              );
                              if (!mounted) return;
                              ref
                                  .read(providerInstance.notifier)
                                  .fetchDetails(widget.item);
                            },
                            onPressed: (restart) async {
                              await details.play(
                                detailsContext,
                                ref,
                                startPosition: restart ? Duration.zero : null,
                              );
                              if (!mounted) return;
                              ref
                                  .read(providerInstance.notifier)
                                  .fetchDetails(widget.item);
                            },
                          )
                        : showMovieRequest
                            ? OxMovieRequestButton(
                                tmdbId: details.tmdbId!,
                                prominent: true,
                              )
                            : null,
                    centerButtons: OxDetailActionLayout(
                      alignment: wrapAlignment,
                      children: [
                        SelectableIconButton(
                          onPressed: () async {
                            await ref.read(userProvider.notifier).setAsFavorite(
                                !details.userData.isFavourite, details.id);
                          },
                          selected: details.userData.isFavourite,
                          selectedIcon: IconsaxPlusBold.heart,
                          icon: IconsaxPlusLinear.heart,
                        ),
                        SelectableIconButton(
                          onPressed: () async {
                            await ref.read(userProvider.notifier).markAsPlayed(
                                !details.userData.played, details.id);
                          },
                          selected: details.userData.played,
                          selectedIcon: IconsaxPlusBold.tick_circle,
                          icon: IconsaxPlusLinear.tick_circle,
                        ),
                        SelectableIconButton(
                          refreshOnEnd: false,
                          onPressed: () async {
                            await showBottomSheetPill(
                              context: detailsContext,
                              content: (context, scrollController) => ListView(
                                controller: scrollController,
                                shrinkWrap: true,
                                children: details
                                    .generateActions(detailsContext, ref)
                                    .listTileItems(context, useIcons: true),
                              ),
                            );
                          },
                          selected: false,
                          icon: IconsaxPlusLinear.more,
                        ),
                      ],
                    ),
                    originalTitle: details.originalTitle,
                    productionYear: details.premiereDate.year.toString(),
                    runTime: details.overview.runTime,
                    genres: details.overview.genreItems,
                    studios: details.overview.studios,
                    officialRating: details.overview.parentalRating,
                    communityRating: details.overview.communityRating,
                    contentTags: details.overview.tags,
                    additionalLabels: oxLibraryDetailLabels(
                      context,
                      ref,
                      widget.item.id,
                      details.overview,
                    ),
                    mediaStreamHelper:
                        oxplayerShowMediaStreamHelper(details.mediaStreams)
                            ? MediaStreamHelper(
                                mediaStream: details.mediaStreams,
                                onItemChanged: (changed) {
                                  oxplayerOnUserMediaStreamsChanged(
                                    ref,
                                    changed,
                                    itemId: details.id,
                                  );
                                  ref
                                      .read(providerInstance.notifier)
                                      .setMediaStreamHelper(changed);
                                },
                              )
                            : null,
                  ),
                  if (details.overview.summary.isNotEmpty == true)
                    ExpandingText(
                      text: details.overview.summary,
                    ).padding(padding),
                  if (details.chapters.isNotEmpty)
                    ChapterRow(
                      chapters: details.chapters,
                      contentPadding: padding,
                      onPressed: (chapter) {
                        details.play(
                          detailsContext,
                          ref,
                          startPosition: chapter.startPosition,
                        );
                      },
                    ),
                  if (details.overview.people.isNotEmpty)
                    OxplayerConfig.isEnabled
                        ? OxSeerrPeopleRow(
                            people: details.overview.people,
                            contentPadding: padding,
                            useLibraryPersonScreen: true,
                          )
                        : PeopleRow(
                            people: details.overview.people,
                            contentPadding: padding,
                          ),
                  if (details.specialFeatures.isNotEmpty)
                    SpecialFeaturesRow(
                        contentPadding: padding,
                        label: detailsContext.localized
                            .specialFeature(details.specialFeatures.length),
                        specialFeatures: details.specialFeatures),
                  if (details.related.isNotEmpty)
                    PosterRow(
                      posters: details.related,
                      contentPadding: padding,
                      label: detailsContext.localized.related,
                      oxDetailBadges: OxplayerConfig.isEnabled,
                    ),
                  if (OxplayerConfig.isEnabled)
                    OxMovieBoxSetRow(
                      itemId: widget.item.id,
                      contentPadding: padding,
                    ),
                  if (details.seerrRecommended.isNotEmpty)
                    SeerrPosterRow(
                      posters: details.seerrRecommended,
                      label:
                          "${detailsContext.localized.discover} ${detailsContext.localized.recommended.toLowerCase()}",
                      contentPadding: padding,
                      oxDetailBadges: OxplayerConfig.isEnabled,
                    ),
                  if (details.seerrRelated.isNotEmpty)
                    SeerrPosterRow(
                      posters: details.seerrRelated,
                      label:
                          "${detailsContext.localized.discover} ${detailsContext.localized.related.toLowerCase()}",
                      contentPadding: padding,
                      oxDetailBadges: OxplayerConfig.isEnabled,
                    ),
                  if (details.overview.externalUrls?.isNotEmpty == true)
                    Padding(
                      padding: padding,
                      child: ExternalUrlsRow(
                        urls: details.overview.externalUrls,
                      ),
                    )
                ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
              ),
            )
          : OxplayerConfig.isEnabled
              ? OxDetailLoadingContent(item: widget.item, padding: padding)
              : Container(),
    );
  }
}
