# Used from patched DonutWare media_kit Windows CMake (CI): reliable 7z unpack of the libmpv archive.
# The archive holds libmpv-2.dll + other DLLs at its root plus an include/mpv header tree; media_kit
# expects libmpv-2.dll at ${LIBMPV_SRC} and the headers flattened to ${LIBMPV_SRC}/include.
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$DestDir
)

$ErrorActionPreference = "Stop"

$seven = Join-Path ${env:ProgramFiles} "7-Zip\7z.exe"
if (-not (Test-Path -LiteralPath $seven)) {
    $seven = "C:\Program Files\7-Zip\7z.exe"
}
if (-not (Test-Path -LiteralPath $seven)) {
    throw "7-Zip not found (looked in ProgramFiles\7-Zip)"
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

& $seven x $Archive "-o$DestDir" -y
if ($LASTEXITCODE -ne 0) {
    throw "7z extract failed with exit code $LASTEXITCODE"
}

# Replicate media_kit's include/mpv -> include juggling.
$includeMpv = Join-Path $DestDir "include\mpv"
if (Test-Path -LiteralPath $includeMpv) {
    $tmp = Join-Path $DestDir "mpv_headers_tmp"
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $includeMpv -Destination $tmp
    Remove-Item -LiteralPath (Join-Path $DestDir "include") -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $tmp -Destination (Join-Path $DestDir "include")
}

$dll = Join-Path $DestDir "libmpv-2.dll"
if (-not (Test-Path -LiteralPath $dll)) {
    throw "libmpv-2.dll missing under $DestDir after extract"
}
