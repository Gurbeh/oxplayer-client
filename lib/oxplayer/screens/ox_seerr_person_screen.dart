import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';

class OxSeerrPersonScreen extends ConsumerStatefulWidget {
  final Person person;
  final int tmdbPersonId;

  const OxSeerrPersonScreen({
    required this.person,
    required this.tmdbPersonId,
    super.key,
  });

  @override
  ConsumerState<OxSeerrPersonScreen> createState() => _OxSeerrPersonScreenState();
}

class _OxSeerrPersonScreenState extends ConsumerState<OxSeerrPersonScreen> {
  bool _loading = true;
  List<SeerrDashboardPosterModel> _movies = const [];
  List<SeerrDashboardPosterModel> _series = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadCredits);
  }

  Future<void> _loadCredits() async {
    setState(() => _loading = true);
    final api = ref.read(seerrApiProvider);
    final response = await api.personCombinedCredits(personId: widget.tmdbPersonId);
    if (!mounted) return;

    final movies = <SeerrDashboardPosterModel>[];
    final series = <SeerrDashboardPosterModel>[];
    if (response.isSuccessful && response.body != null) {
      final credits = response.body!;
      for (final credit in [...?credits.cast, ...?credits.crew]) {
        final poster = api.posterFromPersonCredit(credit);
        if (poster == null) continue;
        if (poster.type == SeerrMediaType.tvshow) {
          series.add(poster);
        } else {
          movies.add(poster);
        }
      }
    }

    setState(() {
      _loading = false;
      _movies = movies;
      _series = series;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      label: widget.person.name,
      onRefresh: _loadCredits,
      content: (context, contentPadding) {
        if (_loading) {
          return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.of(context).size.height / 8),
            Padding(
              padding: contentPadding,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: SizedBox(
                      width: AdaptiveLayout.viewSizeOf(context) == ViewSize.phone
                          ? MediaQuery.of(context).size.width * 0.55
                          : MediaQuery.of(context).size.width / 4,
                      child: AspectRatio(
                        aspectRatio: 0.7,
                        child: FladderImage(
                          fit: BoxFit.cover,
                          image: widget.person.image,
                          placeHolder: _placeHolder(context, widget.person.name),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.person.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (widget.person.role.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.person.role,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_movies.isNotEmpty)
              SeerrPosterRow(
                contentPadding: contentPadding,
                posters: _movies,
                label: context.localized.seerrMovies,
              ),
            if (_series.isNotEmpty)
              SeerrPosterRow(
                contentPadding: contentPadding,
                posters: _series,
                label: context.localized.seerrSeries,
              ),
            if (!_loading && _movies.isEmpty && _series.isEmpty)
              Padding(
                padding: contentPadding,
                child: Text(
                  context.localized.noOverviewAvailable,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _placeHolder(BuildContext context, String name) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          name.getInitials(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
