<#
.SYNOPSIS
    Builds mods/ and config/ for the server from THIS packwiz directory.

.DESCRIPTION
    Runs packwiz-installer (server side only) against the local pack.toml in a
    scratch directory, then keeps only the mods/ and config/ folders.
    Copy those two folders to the server, replacing the existing ones.
    Run update.ps1 (or `packwiz refresh`) first if you changed anything, so
    index.toml matches the files on disk.

.PARAMETER OutputDir
    Where to put the result. Defaults to .\server-out next to this script.

.PARAMETER Force
    Replace OutputDir if it already exists and is not empty.

.EXAMPLE
    .\make-server.ps1
    .\make-server.ps1 -OutputDir D:\export -Force
#>

param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "server-out"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$BootstrapUrl = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: java not found in PATH" -ForegroundColor Red
    exit 1
}

# Resolve relative paths against the caller's current directory, not the script's.
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
$PackUrl = ([System.Uri](Join-Path $PSScriptRoot "pack.toml")).AbsoluteUri

Write-Host ""
Write-Host "=== Server Folder Build ===" -ForegroundColor Cyan
Write-Host ""

if ((Test-Path $OutputDir) -and (Get-ChildItem $OutputDir -Force | Select-Object -First 1)) {
    if (-not $Force) {
        Write-Host "ERROR: Output dir is not empty: $OutputDir (use -Force to replace it)" -ForegroundColor Red
        exit 1
    }
    Remove-Item $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

# The installer litters its working dir (jars, packwiz.json, plus root files like
# options.txt), so it runs in a scratch dir and only mods/ and config/ are kept.
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("make-server-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $work | Out-Null

try {
    Write-Host "[1/2] Installing server-side mods and configs from $PackUrl" -ForegroundColor Yellow
    Invoke-WebRequest -UseBasicParsing -Uri $BootstrapUrl -OutFile (Join-Path $work "packwiz-installer-bootstrap.jar")

    Push-Location $work
    try {
        & java -jar packwiz-installer-bootstrap.jar -g -s server $PackUrl
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: packwiz-installer failed!" -ForegroundColor Red
            exit 1
        }
    } finally {
        Pop-Location
    }

    Write-Host "[2/2] Collecting mods/ and config/..." -ForegroundColor Yellow
    foreach ($dir in "mods", "config") {
        $src = Join-Path $work $dir
        if (Test-Path $src) {
            Move-Item $src (Join-Path $OutputDir $dir)
        } else {
            Write-Host "  WARNING: pack produced no $dir/ folder" -ForegroundColor Red
        }
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

function Count-Files($path) {
    if (Test-Path $path) { (Get-ChildItem $path -Recurse -File).Count } else { 0 }
}

Write-Host ""
Write-Host "Done: $OutputDir" -ForegroundColor Green
Write-Host "  mods:   $(Count-Files (Join-Path $OutputDir 'mods')) files"
Write-Host "  config: $(Count-Files (Join-Path $OutputDir 'config')) files"
Write-Host "Replace the server's mods/ and config/ with these."
Write-Host ""
