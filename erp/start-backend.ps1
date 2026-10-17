# Starts the local PostgreSQL server (if needed) and the ERP REST API.
# Usage:  powershell -ExecutionPolicy Bypass -File erp\start-backend.ps1
$ErrorActionPreference = 'Continue'

$tools   = Join-Path $env:LOCALAPPDATA 'erp-tools'
$nodeDir = Join-Path $tools 'node-v24.20.0-win-x64'
$pg      = Join-Path $tools 'pg-extract\pgsql'
$pgData  = Join-Path $tools 'pgdata'
$pgLog   = Join-Path $tools 'pg.log'

if (Test-Path $nodeDir) { $env:Path = "$nodeDir;" + $env:Path }

# 1. Make sure PostgreSQL is up.
& "$pg\bin\pg_ctl.exe" -D $pgData status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Starting PostgreSQL on port 5432 ...' -ForegroundColor Cyan
  & "$pg\bin\pg_ctl.exe" -D $pgData -l $pgLog -o '-p 5432' start
  Start-Sleep -Seconds 3
} else {
  Write-Host 'PostgreSQL is already running.' -ForegroundColor Green
}

# 2. Start the API.
Set-Location (Join-Path $PSScriptRoot 'backend')
Write-Host 'Starting the ERP API at http://localhost:4000/api/v1 ...' -ForegroundColor Cyan
& npm.cmd run dev
