$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GscTool = Join-Path $ScriptDir "tools\gsc-tool.exe"
$ScriptsDir = Join-Path $ScriptDir "scripts"
$CompiledDir = Join-Path $ScriptDir "compiled"

if (-not (Test-Path $GscTool)) {
    Write-Host "error: gsc-tool.exe not found at $GscTool" -ForegroundColor Red
    Write-Host "download from https://github.com/xensik/gsc-tool/releases"
    Write-Host "extract windows-x64-release.zip into tools\"
    exit 1
}

$version = & $GscTool --version 2>&1 | Select-Object -First 1
Write-Host "gsc-tool: $version"
Write-Host ""

$pass = 0
$fail = 0

Get-ChildItem -Path $ScriptsDir -Filter "*.gsc" | ForEach-Object {
    $name = $_.Name
    Write-Host -NoNewline "compiling $name ... "

    $output = & $GscTool -m comp -g t6 -s pc $_.FullName 2>&1
    if ($output -match "compiled") {
        Write-Host "ok" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host $output
        $fail++
    }
}

Write-Host ""
Write-Host "results: $pass passed, $fail failed"

if ($fail -gt 0) {
    exit 1
}

$outputDir = Join-Path $CompiledDir "t6"
if (Test-Path $outputDir) {
    Write-Host ""
    Write-Host "compiled scripts in: $outputDir"
    Get-ChildItem $outputDir | Format-Table Name, Length, LastWriteTime -AutoSize
}
