$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$PlutoMod = "$env:LOCALAPPDATA\Plutonium\storage\t6\mods\zm_origins_fix"
$FF = Join-Path $RepoRoot "zone\mod.ff"

if (-not (Test-Path $FF)) {
    Write-Host "error: zone/mod.ff not found." -ForegroundColor Red
    Write-Host "Either use the pre-built file or run build_ff.sh to build from source."
    exit 1
}

New-Item -ItemType Directory -Path $PlutoMod -Force | Out-Null
Copy-Item $FF -Destination "$PlutoMod\mod.ff" -Force

$FFSizeKB = [int]((Get-Item $FF).Length / 1024)
Write-Host "Deployed mod.ff ($FFSizeKB KB) to:" -ForegroundColor Green
Write-Host "  $PlutoMod\mod.ff"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Deploy addon scripts: .\deploy.ps1"
Write-Host "  2. Launch Plutonium T6, enable zm_origins_fix mod"
Write-Host "  3. Load Origins"
