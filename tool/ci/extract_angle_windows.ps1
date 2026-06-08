# Used from patched DonutWare media_kit Windows CMake (CI): reliable 7z unpack of the ANGLE archive.
# The archive holds libEGL.dll / libGLESv2.dll / etc. at its root; media_kit expects them at ${ANGLE_SRC}.
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

# ANGLE archives sometimes wrap the DLLs in a single top-level folder; flatten if so.
$egl = Join-Path $DestDir "libEGL.dll"
if (-not (Test-Path -LiteralPath $egl)) {
    $dirs = @(Get-ChildItem -LiteralPath $DestDir -Directory -ErrorAction SilentlyContinue)
    foreach ($dir in $dirs) {
        $innerEgl = Join-Path $dir.FullName "libEGL.dll"
        if (Test-Path -LiteralPath $innerEgl) {
            Copy-Item -Path (Join-Path $dir.FullName "*") -Destination $DestDir -Recurse -Force
            break
        }
    }
}

if (-not (Test-Path -LiteralPath $egl)) {
    throw "libEGL.dll missing under $DestDir after extract"
}
