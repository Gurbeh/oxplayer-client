import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Default retry interval when the server omits `Retry-After` and `retry_after`.
const int oxplayerPlaybackHydrateRetryAfterDefaultSec = 5;

/// Safety cap so a broken server cannot keep the client polling forever.
const Duration oxplayerPlaybackHydrateMaxPollDuration = Duration(minutes: 15);

const int _httpOk = 200;
const int _httpAccepted = 202;

typedef PlaybackInfoRequestFn = Future<Response<PlaybackInfoResponse>> Function();

/// Polls [request] while the API returns HTTP 202 (media hydrate in progress).
///
/// Returns the first HTTP 200 response, or the first non-202 error response (4xx/5xx).
/// Uses [Future.delayed] between attempts so the UI thread is never blocked.
Future<Response<PlaybackInfoResponse>> oxplayerPollPlaybackInfoUntilReady(
  PlaybackInfoRequestFn request,
) async {
  final deadline = DateTime.now().add(oxplayerPlaybackHydrateMaxPollDuration);

  while (true) {
    final response = await request();
    final status = response.statusCode;

    if (status == _httpOk) {
      return response;
    }

    if (status == _httpAccepted) {
      if (DateTime.now().isAfter(deadline)) {
        throw OxplayerPlaybackHydrateTimeoutException(
          lastRetryAfterSec: oxplayerPlaybackHydrateRetryAfterSeconds(response),
        );
      }
      final delay = Duration(seconds: oxplayerPlaybackHydrateRetryAfterSeconds(response));
      await Future<void>.delayed(delay);
      continue;
    }

    if (status >= 400) {
      return response;
    }

    // Other 2xx (unexpected for PlaybackInfo) — pass through.
    if (response.isSuccessful) {
      return response;
    }

    return response;
  }
}

/// Parses retry delay from `Retry-After` header, then JSON `retry_after`, else [oxplayerPlaybackHydrateRetryAfterDefaultSec].
int oxplayerPlaybackHydrateRetryAfterSeconds(Response<PlaybackInfoResponse> response) {
  final header = response.base.headers['retry-after'];
  if (header != null) {
    final parsed = int.tryParse(header.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }

  final rawBody = response.bodyString;
  if (rawBody.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        final retry = decoded['retry_after'];
        if (retry is num && retry > 0) {
          return retry.round();
        }
      }
    } catch (_) {
      // Ignore malformed preparing payload.
    }
  }

  return oxplayerPlaybackHydrateRetryAfterDefaultSec;
}

/// Thrown when hydrate polling exceeds [oxplayerPlaybackHydrateMaxPollDuration].
final class OxplayerPlaybackHydrateTimeoutException implements Exception {
  OxplayerPlaybackHydrateTimeoutException({required this.lastRetryAfterSec});

  final int lastRetryAfterSec;

  @override
  String toString() =>
      'Playback hydrate timed out after ${oxplayerPlaybackHydrateMaxPollDuration.inMinutes} minutes';
}
