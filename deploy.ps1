$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CompiledDir = Join-Path $ScriptDir "compiled\t6"
$PlutoScripts = Join-Path $env:LOCALAPPDATA "Plutonium\storage\t6\scripts\zm"

if (-not (Test-Path $CompiledDir)) {
    Write-Host "error: compiled/t6/ not found. Run build.ps1 first." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $PlutoScripts)) {
    Write-Host "Creating Plutonium scripts directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $PlutoScripts -Force | Out-Null
}

$files = Get-ChildItem -Path $CompiledDir -Filter "zm_*.gsc"

if ($files.Count -eq 0) {
    Write-Host "error: no compiled zm_*.gsc files. Run build.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Deploying to: $PlutoScripts" -ForegroundColor Cyan
Write-Host ""

foreach ($file in $files) {
    Copy-Item $file.FullName -Destination $PlutoScripts -Force
    Write-Host "  copied $($file.Name) ($($file.Length) bytes)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done! $($files.Count) scripts deployed." -ForegroundColor Green
