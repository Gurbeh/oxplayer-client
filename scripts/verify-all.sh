#!/usr/bin/env bash
# Static checks before pushing oxplayer-client changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "=== oxplayer-client verify-all ==="
dart analyze lib/
dart format --output=none --set-exit-if-changed lib/oxplayer lib/models/playback lib/screens/details_screens/movie_detail_screen.dart lib/screens/details_screens/episode_detail_screen.dart lib/screens/details_screens/series_detail_screen.dart lib/screens/details_screens/components/overview_header.dart lib/screens/details_screens/components/media_stream_information.dart
echo "=== verify-all OK ==="
