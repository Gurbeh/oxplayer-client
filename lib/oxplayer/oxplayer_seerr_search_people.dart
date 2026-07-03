import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_search_catalog_ui.dart';
import 'package:fladder/oxplayer/widgets/ox_seerr_people_row.dart';
import 'package:fladder/models/seerr/seerr_item_models.dart';
import 'package:fladder/oxplayer/ox_person_tmdb_id.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

final oxplayerSeerrSearchPeopleProvider =
    FutureProvider.autoDispose.family<List<Person>, OxplayerSeerrSearchPeopleQuery>(
  (ref, query) => oxplayerFetchSeerrSearchPeople(ref, query),
);

class OxplayerSeerrSearchPeopleQuery {
  const OxplayerSeerrSearchPeopleQuery({
    required this.term,
    required this.searchMode,
  });

  final String term;
  final SeerrSearchMode searchMode;

  @override
  bool operator ==(Object other) =>
      other is OxplayerSeerrSearchPeopleQuery && other.term == term && other.searchMode == searchMode;

  @override
  int get hashCode => Object.hash(term, searchMode);
}

bool oxplayerSeerrSearchShowsPeople(SeerrSearchMode mode) {
  return mode == SeerrSearchMode.search;
}

Person? oxplayerPersonFromDiscoverItem(SeerrDiscoverItem item) {
  if (item.mediaType != SeerrMediaType.person) return null;

  final id = item.id;
  final name = (item.name ?? item.title ?? '').trim();
  if (id == null || id <= 0 || name.isEmpty) return null;

  final imagePath = item.internalProfilePath ?? item.internalPosterPath;
  final imageUrl = resolveImageUrl(path: imagePath);

  return Person(
    id: oxCanonicalTmdbPersonItemId(id),
    name: name,
    image: imageUrl != null ? ImageData(path: imageUrl, key: 'seerr_search_person_$id') : null,
  );
}

Future<List<Person>> oxplayerFetchSeerrSearchPeople(
  Ref ref,
  OxplayerSeerrSearchPeopleQuery query,
) async {
  final term = query.term.trim();
  if (term.isEmpty || !oxplayerSeerrSearchShowsPeople(query.searchMode)) {
    return const [];
  }

  final api = ref.read(seerrApiProvider);
  final response = await api.search(query: term, page: 1);
  if (!response.isSuccessful) return const [];

  final people = <Person>[];
  for (final item in response.body?.results ?? const <SeerrDiscoverItem>[]) {
    final person = oxplayerPersonFromDiscoverItem(item);
    if (person != null) people.add(person);
  }
  return people;
}

class OxplayerSeerrSearchPeopleRow extends ConsumerWidget {
  final String query;
  final SeerrSearchMode searchMode;

  const OxplayerSeerrSearchPeopleRow({
    required this.query,
    required this.searchMode,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogOnly = ref.watch(oxplayerSeerrCatalogOnlyFilterProvider);
    final trimmed = query.trim();
    if (catalogOnly || trimmed.isEmpty || !oxplayerSeerrSearchShowsPeople(searchMode)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final peopleAsync = ref.watch(
      oxplayerSeerrSearchPeopleProvider(
        OxplayerSeerrSearchPeopleQuery(term: trimmed, searchMode: searchMode),
      ),
    );

    return peopleAsync.when(
      data: (people) {
        if (people.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OxSeerrPeopleRow(
              people: people,
              contentPadding: AdaptiveLayout.adaptivePadding(context),
              useLibraryPersonScreen: true,
            ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}
