# Regenerate all OXPlayer branding assets from icons/oxplayer_icon.svg
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "==> Normalize SVG (requires source file argument if re-importing)"
if (Test-Path "logo (2).svg") {
    python scripts/normalize_oxplayer_icon.py "logo (2).svg"
}

Write-Host "==> Export PNGs (launcher, banner, monochrome, notification, dev sync)"
python scripts/export_branding_assets.py

Write-Host "==> Platform launcher icons (development first; production last for shared windows/web/linux)"
dart run icons_launcher:create --flavor development
dart run icons_launcher:create --flavor production

Write-Host "==> Native splash"
dart run flutter_native_splash:create

Write-Host "Done. Optional: flutter build apk --flavor production --debug"
