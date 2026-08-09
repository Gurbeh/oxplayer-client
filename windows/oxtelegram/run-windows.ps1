# Run OXPlayer on Windows with the toolchain + dart-defines this repo needs:
# - Temurin JDK 21 (jni.h for sentry_flutter → jni plugin)
# - Visual Studio 17 2022 (not 2019 — Firebase CRT + ATL)
# - dart_defines.dev.json (TELEGRAM_API_ID/HASH, API bases — same as Android pnpm run)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root "pubspec.yaml"))) {
  $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
Set-Location $root

$jdk = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.8-hotspot"
if (-not (Test-Path (Join-Path $jdk "include\jni.h"))) {
  Write-Error "Temurin JDK 21 missing at $jdk (need include\jni.h). Install EclipseAdoptium.Temurin.21.JDK."
}
$defines = Join-Path $root "dart_defines.dev.json"
if (-not (Test-Path $defines)) {
  Write-Error "Missing $defines — from oxplayer-be run: pnpm run sync:client-env (or pnpm run dev)."
}

$env:JAVA_HOME = $jdk
$env:PATH = "$jdk\bin;$env:PATH"
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"

Write-Host "JAVA_HOME=$env:JAVA_HOME"
Write-Host "CMAKE_GENERATOR=$env:CMAKE_GENERATOR"
Write-Host "dart-defines=$defines"
flutter run -d windows --dart-define-from-file=dart_defines.dev.json @args
