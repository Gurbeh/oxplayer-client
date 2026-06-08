# Regenerate all OXPlayer branding assets from icons/oxplayer_icon.svg
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "==> Normalize SVG (requires source file argument if re-importing)"
if (Test-Path "logo (2).svg") {
    python scripts/normalize_oxplayer_icon.py "logo (2).svg"
}

Write-Host "==> Export PNGs (banner, monochrome, notification, dev sync)"
python scripts/export_branding_assets.py

Write-Host "==> Resvg production PNGs"
npx --yes @resvg/resvg-js-cli icons/oxplayer_icon.svg icons/production/oxplayer_icon_512.png --fit-width 512
npx --yes @resvg/resvg-js-cli icons/oxplayer_icon.svg icons/production/oxplayer_icon.png --fit-width 1024
npx --yes @resvg/resvg-js-cli icons/oxplayer_icon.svg icons/production/oxplayer_icon_desktop.png --fit-width 512
npx --yes @resvg/resvg-js-cli icons/oxplayer_icon.svg icons/production/oxplayer_store_icon.png --fit-width 512

Write-Host "==> Platform launcher icons"
dart run icons_launcher:create --flavors development,production

Write-Host "==> Native splash"
dart run flutter_native_splash:create

Write-Host "Done. Optional: flutter build apk --flavor production --debug"
