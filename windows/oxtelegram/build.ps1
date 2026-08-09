# Rebuild Windows oxtelegram.dll (gotd c-shared). Requires Go + MinGW gcc (CGO).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location (Join-Path $root "go\oxtelegram")
$outDir = Join-Path $root "windows\oxtelegram"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$env:CGO_ENABLED = "1"
go build -buildmode=c-shared -o (Join-Path $outDir "oxtelegram.dll") ./cshared
Write-Host "Wrote $(Join-Path $outDir 'oxtelegram.dll')"
