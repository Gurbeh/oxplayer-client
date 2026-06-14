import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_seerr_request_visibility.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:flutter_test/flutter_test.dart';

SeerrSeason _season(int number) => SeerrSeason(seasonNumber: number);

void main() {
  group('oxIsRequestableSeasonNumber', () {
    test('rejects null and season 0', () {
      expect(oxIsRequestableSeasonNumber(null), isFalse);
      expect(oxIsRequestableSeasonNumber(0), isFalse);
    });

    test('accepts positive seasons', () {
      expect(oxIsRequestableSeasonNumber(1), isTrue);
      expect(oxIsRequestableSeasonNumber(2), isTrue);
    });
  });

  group('oxHasRequestableSeasons', () {
    test('ignores season 0 when only specials exist', () {
      expect(
        oxHasRequestableSeasons(
          seasons: [_season(0)],
          seasonStatuses: const {0: SeerrMediaStatus.unknown},
        ),
        isFalse,
      );
    });

    test('season 1 available + season 2 unknown → requestable', () {
      expect(
        oxHasRequestableSeasons(
          seasons: [_season(1), _season(2)],
          seasonStatuses: const {
            1: SeerrMediaStatus.available,
            2: SeerrMediaStatus.unknown,
          },
        ),
        isTrue,
      );
    });

    test('all non-zero seasons available → not requestable', () {
      expect(
        oxHasRequestableSeasons(
          seasons: [_season(1), _season(2)],
          seasonStatuses: const {
            1: SeerrMediaStatus.available,
            2: SeerrMediaStatus.available,
          },
        ),
        isFalse,
      );
    });

    test('partiallyAvailable season is requestable', () {
      expect(
        oxHasRequestableSeasons(
          seasons: [_season(1)],
          seasonStatuses: const {1: SeerrMediaStatus.partiallyAvailable},
        ),
        isTrue,
      );
    });

    test('season 0 available does not block when season 1 is unknown', () {
      expect(
        oxHasRequestableSeasons(
          seasons: [_season(0), _season(1)],
          seasonStatuses: const {
            0: SeerrMediaStatus.available,
            1: SeerrMediaStatus.unknown,
          },
        ),
        isTrue,
      );
    });
  });

  group('oxShouldShowSeriesRequestButton', () {
    test('empty seerrUrl → false', () {
      expect(
        oxShouldShowSeriesRequestButton(
          seerrUrl: null,
          tmdbId: 1,
          seerrConfigured: true,
          seasons: [_season(1)],
          seasonStatuses: const {1: SeerrMediaStatus.unknown},
        ),
        isFalse,
      );
    });

    test('seerr not configured → false', () {
      expect(
        oxShouldShowSeriesRequestButton(
          seerrUrl: 'ox',
          tmdbId: 1,
          seerrConfigured: false,
          seasons: [_season(1)],
          seasonStatuses: const {1: SeerrMediaStatus.unknown},
        ),
        isFalse,
      );
    });

    test('gates pass and incomplete seasons → true', () {
      expect(
        oxShouldShowSeriesRequestButton(
          seerrUrl: 'ox',
          tmdbId: 99,
          seerrConfigured: true,
          seasons: [_season(1), _season(2)],
          seasonStatuses: const {
            1: SeerrMediaStatus.available,
            2: SeerrMediaStatus.unknown,
          },
        ),
        isTrue,
      );
    });

    test('gates pass and all seasons available → false', () {
      expect(
        oxShouldShowSeriesRequestButton(
          seerrUrl: 'ox',
          tmdbId: 99,
          seerrConfigured: true,
          seasons: [_season(1)],
          seasonStatuses: const {1: SeerrMediaStatus.available},
        ),
        isFalse,
      );
    });
  });
}
