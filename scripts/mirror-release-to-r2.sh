#!/usr/bin/env bash
# Mirror stable release binaries to Cloudflare R2 under releases/latest/ (+ versioned copy).
# Used by GitHub Actions create_release (build_type=release only).
#
# Required env:
#   CLOUDFLARE_S3_ACCESS_KEY_ID
#   CLOUDFLARE_S3_SECRET_ACCESS_KEY
#   CLOUDFLARE_S3_API_ENDPOINT   (e.g. https://<accountid>.r2.cloudflarestorage.com)
#   CLOUDFLARE_R2_BUCKET         (default: oxplayer-channel-news)
#   VERSION                      (e.g. 1.1.123)
#
# Optional:
#   RELEASE_FILES                space-separated local filenames (default: staged OXPlayer-* assets)
set -euo pipefail

BUCKET="${CLOUDFLARE_R2_BUCKET:-oxplayer-channel-news}"
ENDPOINT="${CLOUDFLARE_S3_API_ENDPOINT:?CLOUDFLARE_S3_API_ENDPOINT required}"
VERSION="${VERSION:?VERSION required}"

if [[ -z "${CLOUDFLARE_S3_ACCESS_KEY_ID:-}" || -z "${CLOUDFLARE_S3_SECRET_ACCESS_KEY:-}" ]]; then
  echo "::error::CLOUDFLARE_S3_* credentials missing — cannot mirror to R2"
  exit 1
fi

export AWS_ACCESS_KEY_ID="${CLOUDFLARE_S3_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${CLOUDFLARE_S3_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION=auto

# shellcheck disable=SC2206
FILES=(${RELEASE_FILES:-})
if ((${#FILES[@]} == 0)); then
  FILES=(
    "OXPlayer-Android-${VERSION}-arm64-v8a.apk"
    "OXPlayer-Android-${VERSION}-armeabi-v7a.apk"
    "OXPlayer-Android-${VERSION}-x86_64.apk"
    "OXPlayer-Windows-${VERSION}-Setup.exe"
    "OXPlayer-Windows-${VERSION}.zip"
  )
fi

latest_key_for() {
  local f="$1"
  case "$f" in
    OXPlayer-Android-*-arm64-v8a.apk) echo "releases/latest/OXPlayer-Android-arm64-v8a.apk" ;;
    OXPlayer-Android-*-armeabi-v7a.apk) echo "releases/latest/OXPlayer-Android-armeabi-v7a.apk" ;;
    OXPlayer-Android-*-x86_64.apk) echo "releases/latest/OXPlayer-Android-x86_64.apk" ;;
    OXPlayer-Windows-*-Setup.exe) echo "releases/latest/OXPlayer-Windows-Setup.exe" ;;
    OXPlayer-Windows-*.zip) echo "releases/latest/OXPlayer-Windows.zip" ;;
    OXPlayer-iOS-*.ipa) echo "releases/latest/OXPlayer-iOS.ipa" ;;
    OXPlayer-macOS-*.dmg) echo "releases/latest/OXPlayer-macOS.dmg" ;;
    OXPlayer-Linux-*.AppImage) echo "releases/latest/OXPlayer-Linux.AppImage" ;;
    *) echo "" ;;
  esac
}

content_type_for() {
  local f="$1"
  case "$f" in
    *.apk) echo "application/vnd.android.package-archive" ;;
    *.aab) echo "application/octet-stream" ;;
    *.exe) echo "application/vnd.microsoft.portable-executable" ;;
    *.zip) echo "application/zip" ;;
    *.ipa) echo "application/octet-stream" ;;
    *.dmg) echo "application/x-apple-diskimage" ;;
    *.AppImage) echo "application/octet-stream" ;;
    *) echo "application/octet-stream" ;;
  esac
}

basename_for_disposition() {
  local key="$1"
  basename "$key"
}

upload_one() {
  local src="$1"
  local key="$2"
  local ctype
  ctype="$(content_type_for "$src")"
  local fname
  fname="$(basename_for_disposition "$key")"
  echo "R2 put s3://${BUCKET}/${key} <- ${src}"
  aws s3 cp "$src" "s3://${BUCKET}/${key}" \
    --endpoint-url "$ENDPOINT" \
    --content-type "$ctype" \
    --content-disposition "attachment; filename=\"${fname}\"" \
    --cache-control "public, max-age=300, must-revalidate"
}

if ! command -v aws >/dev/null 2>&1; then
  echo "Installing AWS CLI v2…"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install >/dev/null
fi

uploaded=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "::warning::skip missing asset: $f"
    continue
  fi
  versioned="releases/v${VERSION}/$(basename "$f")"
  upload_one "$f" "$versioned"
  latest="$(latest_key_for "$f")"
  if [[ -n "$latest" ]]; then
    upload_one "$f" "$latest"
  fi
  uploaded=$((uploaded + 1))
done

if (( uploaded == 0 )); then
  echo "::error::no assets uploaded to R2"
  exit 1
fi

echo "Mirrored ${uploaded} asset(s) to R2 bucket ${BUCKET} (latest + v${VERSION})"
