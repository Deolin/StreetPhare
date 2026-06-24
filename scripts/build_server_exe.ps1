# scripts/build_server_exe.ps1
#
# Build standalone Windows executable (.exe) for StreetPhare Server.
#
# Compiles server_dart/bin/server.dart into a native AOT executable,
# copies required assets (web dashboard, web_src), and optionally
# creates a portable distribution zip.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/build_server_exe.ps1
#
# Optional flags:
#   -Clean        Remove previous build output before compiling
#   -Zip          Create a portable .zip archive after build
#   -OutputDir    Override default output directory (default: build/server_standalone)

param(
    [switch]$Clean,
    [switch]$Zip,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path "$scriptDir\.."
$serverSrc = "$projectRoot\server_dart"
$buildDir = if ($OutputDir) { $OutputDir } else { "$projectRoot\build\server_standalone" }

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   StreetPhare Server — Build Standalone EXE      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Phase 1 : Clean ────────────────────────────────────────────────────────
if ($Clean) {
    Write-Host "[Clean] Suppression de $buildDir ..." -ForegroundColor Yellow
    if (Test-Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir
    }
    Write-Host "[Clean] Terminé." -ForegroundColor Green
}

# ── Phase 2 : Restore dependencies ──────────────────────────────────────────
Write-Host "[Phase 1/4] Restauration des dépendances..." -ForegroundColor Yellow
Push-Location $serverSrc
try {
    dart pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERREUR: dart pub get a échoué." -ForegroundColor Red
        exit 1
    }
    Write-Host "[Phase 1/4] Dépendances OK." -ForegroundColor Green
} finally {
    Pop-Location
}

# ── Phase 3 : Analyse statique ──────────────────────────────────────────────
Write-Host "[Phase 2/4] Analyse statique..." -ForegroundColor Yellow
Push-Location $serverSrc
try {
    dart analyze bin/server.dart
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ATTENTION: Des avertissements d'analyse existent." -ForegroundColor Yellow
    }
    Write-Host "[Phase 2/4] Analyse terminée." -ForegroundColor Green
} finally {
    Pop-Location
}

# ── Phase 4 : Compilation AOT ───────────────────────────────────────────────
Write-Host "[Phase 3/4] Compilation AOT -> server.exe ..." -ForegroundColor Yellow

# Crée le répertoire de sortie
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

Push-Location $serverSrc
try {
    # Le --no-pub est utilisé car on a déjà fait pub get
    dart compile exe bin/server.dart -o "$buildDir\server.exe"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERREUR: Compilation AOT échouée." -ForegroundColor Red
        exit 1
    }
    Write-Host "[Phase 3/4] Compilation réussie -> $buildDir\server.exe" -ForegroundColor Green
} finally {
    Pop-Location
}

# ── Phase 5 : Copie des assets ──────────────────────────────────────────────
Write-Host "[Phase 4/4] Copie des assets..." -ForegroundColor Yellow

# Copie du dashboard web (nécessaire pour l'interface admin)
$webSrc = "$serverSrc\web"
$webDst = "$buildDir\web"
if (Test-Path $webSrc) {
    Copy-Item -Recurse -Force "$webSrc" -Destination "$webDst"
    Write-Host "  ✓ web/ (dashboard admin)" -ForegroundColor Gray
}

# Copie de web_src si présent
$webSrcSrc = "$serverSrc\web_src"
$webSrcDst = "$buildDir\web_src"
if (Test-Path $webSrcSrc) {
    Copy-Item -Recurse -Force "$webSrcSrc" -Destination "$webSrcDst"
    Write-Host "  ✓ web_src/" -ForegroundColor Gray
}

# Copie du README
$readmeSrc = "$serverSrc\README.md"
if (Test-Path $readmeSrc) {
    Copy-Item -Force "$readmeSrc" -Destination "$buildDir\README.md"
    Write-Host "  ✓ README.md" -ForegroundColor Gray
}

Write-Host "[Phase 4/4] Assets copiés." -ForegroundColor Green
Write-Host ""

# ── Résumé ──────────────────────────────────────────────────────────────────
$exePath = "$buildDir\server.exe"
$exeSize = if (Test-Path $exePath) {
    "{0:N2} MB" -f ((Get-Item $exePath).Length / 1MB)
} else {
    "inconnu"
}

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   BUILD TERMINÉ                                  ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║   Exécutable : $exePath" -ForegroundColor White
Write-Host "║   Taille     : $exeSize" -ForegroundColor White
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║   Lancement (mode primary, port 3000) :" -ForegroundColor White
Write-Host "║     $buildDir\server.exe" -ForegroundColor Gray
Write-Host "║" -ForegroundColor White
Write-Host "║   Lancement (mode backup, port 3001) :" -ForegroundColor White
Write-Host "║     set ROLE=backup && set PORT=3001 && $buildDir\server.exe" -ForegroundColor Gray
Write-Host "║" -ForegroundColor White
Write-Host "║   Endpoints :" -ForegroundColor White
Write-Host "║     HTTP       : http://localhost:3000" -ForegroundColor Gray
Write-Host "║     Dashboard  : http://localhost:3000/dashboard" -ForegroundColor Gray
Write-Host "║     WS Mesh    : ws://localhost:3000/mesh" -ForegroundColor Gray
Write-Host "║     WS Admin   : ws://localhost:3000/admin" -ForegroundColor Gray
Write-Host "║     Health     : http://localhost:3000/healthz" -ForegroundColor Gray
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── Option: Zip ─────────────────────────────────────────────────────────────
if ($Zip) {
    $zipPath = "$projectRoot\build\server_standalone.zip"
    Write-Host ""
    Write-Host "Création de l'archive portable..." -ForegroundColor Yellow
    Compress-Archive -Path "$buildDir\*" -DestinationPath $zipPath -Force
    Write-Host "Archive créée : $zipPath" -ForegroundColor Green
}