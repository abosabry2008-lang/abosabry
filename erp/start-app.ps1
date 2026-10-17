# Runs the Flutter ERP client in Chrome (web).
# Start the backend first:  powershell -ExecutionPolicy Bypass -File erp\start-backend.ps1
# Usage:  powershell -ExecutionPolicy Bypass -File erp\start-app.ps1
$ErrorActionPreference = 'Continue'

Set-Location (Join-Path $PSScriptRoot 'app')
Write-Host 'Starting the Flutter ERP client (Chrome) ...' -ForegroundColor Cyan
& flutter run -d chrome
