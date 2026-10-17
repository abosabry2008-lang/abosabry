# Builds the Flutter web app for production and copies it to `erp/web`.
#
# استخدام / Usage:
#   .\erp\deploy\build_web.ps1 -ApiUrl https://erp-api.onrender.com/api/v1
#
# ثم:
#   git add erp/web ; git commit -m "rebuild web" ; git push
#
# Render serves the contents of `erp/web` as the static site (see render.yaml).

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ApiUrl,

  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

$apiUrl = $ApiUrl.TrimEnd('/')
if (-not $apiUrl.StartsWith('http')) {
  throw "ApiUrl must start with http:// or https:// (got: $ApiUrl)"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$appDir   = Join-Path $repoRoot 'erp\app'
$outDir   = Join-Path $repoRoot 'erp\web'

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host " Building Flutter web (release)" -ForegroundColor Cyan
Write-Host "   API_BASE = $apiUrl"
Write-Host "===================================================================" -ForegroundColor Cyan

Push-Location $appDir
try {
  if (-not $SkipPubGet) {
    Write-Host "-> flutter pub get"
    flutter pub get
  }

  Write-Host "-> flutter build web --release"
  flutter build web --release --dart-define=API_BASE=$apiUrl
} finally {
  Pop-Location
}

$builtDir = Join-Path $appDir 'build\web'
if (-not (Test-Path $builtDir)) {
  throw "Build output not found at $builtDir"
}

if (Test-Path $outDir) {
  Remove-Item $outDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outDir | Out-Null
Copy-Item -Path (Join-Path $builtDir '*') -Destination $outDir -Recurse -Force

$sizeMb = [math]::Round(((Get-ChildItem $outDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1)

Write-Host ""
Write-Host "Done. Copied $sizeMb MB -> erp\web" -ForegroundColor Green
Write-Host ""
Write-Host "Next:"
Write-Host "  git add erp/web"
Write-Host "  git commit -m `"web: point the app at $apiUrl`""
Write-Host "  git push"
Write-Host ""
