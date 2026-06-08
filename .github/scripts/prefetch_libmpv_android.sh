#!/usr/bin/env bash
# Pre-fetch libmpv Android JARs for media_kit_libs_android_video (survives GitHub 504s).
set -euo pipefail

CACHE_DIR=".ci-cache/libmpv-android-v1.1.8"
BASE_URL="https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.8"

read -r -d '' JARS <<'EOF' || true
full-arm64-v8a.jar d8142f0317695da2b5970b49232a16fe
full-armeabi-v7a.jar 78d9b7a5875ab8907542cad8319d1761
full-x86_64.jar be8349d300f2cfaa59670b5b1a0368ce
full-x86.jar 2b46056915db8e1aa8a0e79f39071543
EOF

pub_cache="${PUB_CACHE:-${HOME}/.pub-cache}"
plugin_android="$(
  find "${pub_cache}/git" -path '*/media_kit_libs_android_video/android/build.gradle' 2>/dev/null | head -1
)"
if [[ -z "${plugin_android}" ]]; then
  echo "media_kit_libs_android_video not found under ${pub_cache}/git (run flutter pub get first)."
  exit 1
fi

dest_dir="${plugin_android%/build.gradle}/build/v1.1.8"
mkdir -p "${dest_dir}" "${CACHE_DIR}"

verify_md5() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(md5sum "${file}" | awk '{print $1}')"
  [[ "${actual}" == "${expected}" ]]
}

download_jar() {
  local name="$1"
  local md5="$2"
  local url="${BASE_URL}/${name}"
  local dest="${dest_dir}/${name}"
  local cache="${CACHE_DIR}/${name}"

  if [[ -f "${dest}" ]] && verify_md5 "${dest}" "${md5}"; then
    echo "${name} already valid in plugin build dir."
    return 0
  fi

  if [[ -f "${cache}" ]] && verify_md5 "${cache}" "${md5}"; then
    echo "Seeding ${name} from CI cache."
    cp "${cache}" "${dest}"
    return 0
  fi

  rm -f "${dest}" "${cache}"
  for attempt in 1 2 3 4 5 6 7 8; do
    echo "Downloading ${name} (attempt ${attempt}/8)..."
    if curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 \
      -o "${dest}.tmp" "${url}" && verify_md5 "${dest}.tmp" "${md5}"; then
      mv "${dest}.tmp" "${dest}"
      cp "${dest}" "${cache}"
      echo "${name} verified."
      return 0
    fi
    rm -f "${dest}.tmp"
    sleep $((attempt * 10))
  done

  echo "Failed to download a valid ${name}."
  return 1
}

while read -r name md5; do
  [[ -z "${name}" ]] && continue
  download_jar "${name}" "${md5}"
done <<< "${JARS}"
