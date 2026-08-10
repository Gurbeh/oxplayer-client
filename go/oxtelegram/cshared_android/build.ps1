# Rebuild Android liboxtelegramstream.so (gotd stream_cb c-shared) for every vendored ABI and
# copy into android/ox_tdlib_bridge's jniLibs, mirroring windows/oxtelegram/build.ps1.
#
# Requires: Go + Android NDK (ANDROID_NDK_HOME, or set $ndkHome below).
#
# NOTE: API level 24 below is a build-script default, not necessarily the project's real
# minSdkVersion (flutter.minSdkVersion) - check android/local.properties / app/build.gradle and
# adjust $apiLevel if they diverge, otherwise this .so's own minimum OS version could be higher
# than the app's.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$ndkHome = $env:ANDROID_NDK_HOME
if (-not $ndkHome) {
    $sdkNdkDir = Join-Path $env:LOCALAPPDATA "Android\Sdk\ndk"
    if (Test-Path $sdkNdkDir) {
        $ndkHome = (Get-ChildItem $sdkNdkDir -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
    }
}
if (-not $ndkHome -or -not (Test-Path $ndkHome)) {
    throw "Android NDK not found - set ANDROID_NDK_HOME."
}
Write-Host "Using NDK: $ndkHome"

$apiLevel = 24
$toolchainBin = Join-Path $ndkHome "toolchains\llvm\prebuilt\windows-x86_64\bin"
$outDir = Join-Path $root "android\ox_tdlib_bridge\src\main\jniLibs"

$targets = @{
    "arm64-v8a"   = "aarch64-linux-android$apiLevel-clang.cmd"
    "armeabi-v7a" = "armv7a-linux-androideabi$apiLevel-clang.cmd"
    "x86_64"      = "x86_64-linux-android$apiLevel-clang.cmd"
}
$goArch = @{
    "arm64-v8a"   = "arm64"
    "armeabi-v7a" = "arm"
    "x86_64"      = "amd64"
}

Set-Location (Join-Path $root "go\oxtelegram\cshared_android")
$env:CGO_ENABLED = "1"
$env:GOOS = "android"

foreach ($abi in $targets.Keys) {
    $cc = Join-Path $toolchainBin $targets[$abi]
    if (-not (Test-Path $cc)) {
        throw "NDK clang not found for $abi at $cc (check that `$apiLevel matches an installed NDK platform)"
    }
    $abiOutDir = Join-Path $outDir $abi
    New-Item -ItemType Directory -Force -Path $abiOutDir | Out-Null
    $env:CC = $cc
    $env:GOARCH = $goArch[$abi]
    Write-Host "Building $abi (GOARCH=$($goArch[$abi])) ..."
    go build -buildmode=c-shared -o (Join-Path $abiOutDir "liboxtelegramstream.so") .
    Write-Host "Wrote $(Join-Path $abiOutDir 'liboxtelegramstream.so')"
}

Remove-Item Env:\GOOS, Env:\GOARCH, Env:\CC -ErrorAction SilentlyContinue
Write-Host "Done. liboxtelegramstream.so written for: $($targets.Keys -join ', ')"
