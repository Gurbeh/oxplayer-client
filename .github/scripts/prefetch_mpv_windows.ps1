# Pre-fetch mpv + ANGLE archives for media_kit_libs_windows_video (survives corrupt/504 downloads).
$ErrorActionPreference = "Stop"

$destDir = "build/windows/x64"
$cacheDir = ".ci-cache/mpv-windows"
New-Item -ItemType Directory -Force -Path $destDir, $cacheDir | Out-Null

# Keep in sync with DonutWare/media-kit libs/windows/media_kit_libs_windows_video/windows/CMakeLists.txt
$files = @(
    @{
        Name = "mpv-dev-x86_64-20260531-git-13a3e3a.7z"
        Url  = "https://github.com/DonutWare/mpv-winbuild-cmake/releases/download/20260531/mpv-dev-x86_64-20260531-git-13a3e3a.7z"
        Md5  = "69141eef346f9c82640274e6a0f36e7a"
    },
    @{
        Name = "ANGLE.7z"
        Url  = "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
        Md5  = "e866f13e8d552348058afaafe869b1ed"
    }
)

function Test-FileMd5([string]$Path, [string]$Expected) {
    $hash = (Get-FileHash -Path $Path -Algorithm MD5).Hash.ToLower()
    return $hash -eq $Expected.ToLower()
}

foreach ($file in $files) {
    $dest = Join-Path $destDir $file.Name
    $cache = Join-Path $cacheDir $file.Name

    if ((Test-Path -LiteralPath $dest) -and (Test-FileMd5 $dest $file.Md5)) {
        Write-Host "$($file.Name) already valid."
        continue
    }

    if ((Test-Path -LiteralPath $cache) -and (Test-FileMd5 $cache $file.Md5)) {
        Write-Host "Seeding $($file.Name) from CI cache."
        Copy-Item -LiteralPath $cache -Destination $dest -Force
        continue
    }

    $ok = $false
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        Write-Host "Downloading $($file.Name) (attempt $attempt/8)..."
        $tmp = "$dest.tmp"
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Invoke-WebRequest -Uri $file.Url -OutFile $tmp -UseBasicParsing
        if (Test-FileMd5 $tmp $file.Md5) {
            Move-Item -LiteralPath $tmp -Destination $dest -Force
            Copy-Item -LiteralPath $dest -Destination $cache -Force
            Write-Host "$($file.Name) verified."
            $ok = $true
            break
        }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds (10 * $attempt)
    }

    if (-not $ok) {
        throw "Failed to download a valid $($file.Name)."
    }
}
