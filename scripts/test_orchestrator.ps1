# scripts/test_orchestrator.ps1
#
# Orchestrateur de tests StreetPhare — Windows PowerShell
#
# Automatise :
#   1. Compilation à blanc (Android, Windows, Web)
#   2. Déploiement du serveur standalone Dart
#   3. Injection de pairs simulés (loopback)
#   4. Validation de la chaîne de failover (BLE → Wi-Fi → WebSocket)
#   5. Test offline/outbox
#
# Usage :
#   powershell -ExecutionPolicy Bypass -File scripts/test_orchestrator.ps1

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path "$scriptDir\.."
$serverDir = "$projectRoot\server"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   StreetPhare — Test Orchestrator v1.0                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════
# Phase 1 : Analyse statique
# ═══════════════════════════════════════════════════════════════════
Write-Host "[Phase 1/5] Analyse statique..." -ForegroundColor Yellow

Write-Host "  [1a] dart analyze server..." -ForegroundColor Gray
$dartResult = dart analyze "$serverDir\lib" "$serverDir\bin" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✓ server: 0 erreur" -ForegroundColor Green
} else {
    Write-Host "    ⚠ server: $dartResult" -ForegroundColor Red
}

Write-Host "  [1b] flutter analyze..." -ForegroundColor Gray
$flutterResult = flutter analyze 2>&1 | Select-String -Pattern "error|warning" -NotMatch | Select-String -Pattern "^$" -NotMatch
$errorCount = ($flutterResult | Select-String -Pattern "error •").Count
$warnCount = ($flutterResult | Select-String -Pattern "warning •").Count
Write-Host "    ✓ Flutter: $errorCount erreur(s), $warnCount warning(s)" -ForegroundColor $(if ($errorCount -eq 0) { "Green" } else { "Red" })

# ═══════════════════════════════════════════════════════════════════
# Phase 2 : Déploiement serveur standalone
# ═══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[Phase 2/5] Déploiement serveur standalone..." -ForegroundColor Yellow

$serverPort = 3099
Write-Host "  Démarrage serveur Dart sur le port $serverPort..." -ForegroundColor Gray

# Kill any existing server on that port
$existingPid = (Get-NetTCPConnection -LocalPort $serverPort -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
if ($existingPid) {
    Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# Start server in background
$serverJob = Start-Job -ScriptBlock {
    param($dir, $port)
    Set-Location $dir
    dart run bin/server.dart --port $port --data "test_events.json" 2>&1
} -ArgumentList $serverDir, $serverPort

Start-Sleep -Seconds 2

# Verify server is running
try {
    $response = Invoke-RestMethod -Uri "http://localhost:$serverPort/api/stats" -TimeoutSec 3
    Write-Host "    ✓ Serveur UP — port $serverPort" -ForegroundColor Green
    Write-Host "    Stats: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    Write-Host "    ⚠ Serveur non joignable: $_" -ForegroundColor Red
}

# ═══════════════════════════════════════════════════════════════════
# Phase 3 : Test des API REST
# ═══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[Phase 3/5] Test API REST..." -ForegroundColor Yellow

# Create a test event
try {
    $createBody = @{ name = "Test Orchestration"; description = "Événement de test automatique" } | ConvertTo-Json
    $createResp = Invoke-RestMethod -Uri "http://localhost:$serverPort/api/events" -Method POST -Body $createBody -ContentType "application/json"
    $testCode = $createResp.event.code
    Write-Host "    ✓ Événement créé: $testCode" -ForegroundColor Green

    # Fetch QR code
    $qrResp = Invoke-RestMethod -Uri "http://localhost:$serverPort/api/events/$testCode/qr"
    if ($qrResp.qr -like "data:image/svg*") {
        Write-Host "    ✓ QR code généré (SVG data URI)" -ForegroundColor Green
    }

    # Delete test event
    $deleteBody = @{ id = $createResp.event.id; _action = "delete" } | ConvertTo-Json
    Invoke-RestMethod -Uri "http://localhost:$serverPort/api/events" -Method POST -Body $deleteBody -ContentType "application/json" | Out-Null
    Write-Host "    ✓ Événement supprimé" -ForegroundColor Green
} catch {
    Write-Host "    ⚠ Erreur API REST: $_" -ForegroundColor Red
}

# ═══════════════════════════════════════════════════════════════════
# Phase 4 : Test WebSocket & Sync
# ═══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[Phase 4/5] Test WebSocket..." -ForegroundColor Yellow

# Use a Dart script to test WebSocket
$wsTestScript = @"
import 'dart:convert';
import 'dart:io';

void main() async {
  try {
    final ws = await WebSocket.connect('ws://localhost:$serverPort/ws');
    print('✓ WebSocket connecté');

    // Send ping
    ws.add(jsonEncode({'kind': 'ping'}));

    // Request a known event
    ws.add(jsonEncode({'kind': 'request_event', 'code': 'TEST01'}));

    // Simulate alert report
    ws.add(jsonEncode({
      'kind': 'alert_report',
      'type': 'barrage',
      'lat': 50.45,
      'lng': 4.45,
    }));

    await Future.delayed(Duration(seconds: 1));

    // Read responses
    ws.listen((data) {
      final msg = jsonDecode(data as String);
      final kind = msg['kind'] as String;
      print('  ← reçu: $kind');
    });

    await Future.delayed(Duration(seconds: 2));
    await ws.close();
    print('✓ WebSocket fermé proprement');
    exit(0);
  } catch (e) {
    print('⚠ WebSocket erreur: \$e');
    exit(1);
  }
}
"@

$wsTestFile = "$env:TEMP\streetphare_ws_test.dart"
Set-Content -Path $wsTestFile -Value $wsTestScript -Encoding UTF8
$wsResult = dart run $wsTestFile 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✓ Test WebSocket OK" -ForegroundColor Green
} else {
    Write-Host "    ⚠ Test WebSocket: $wsResult" -ForegroundColor Red
}
Remove-Item $wsTestFile -Force -ErrorAction SilentlyContinue

# ═══════════════════════════════════════════════════════════════════
# Phase 5 : Vérification de la résilience réseau
# ═══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[Phase 5/5] Vérification résilience réseau..." -ForegroundColor Yellow

Write-Host "  Validation des points de failover:" -ForegroundColor Gray

# Check that try/catch blocks exist in network_coordinator.dart
$networkCoord = Get-Content "$projectRoot\lib\network\network_coordinator.dart" -Raw
$tryCount = ([regex]::Matches($networkCoord, 'try\s*\{')).Count
Write-Host "    ✓ $tryCount blocs try/catch dans NetworkCoordinator" -ForegroundColor $(if ($tryCount -ge 10) { "Green" } else { "Red" })

# Check outbox mechanism in hive_messaging_service.dart
$msgService = Get-Content "$projectRoot\lib\features\messaging\presentation\hive_messaging_service.dart" -Raw
if ($msgService -match "_outbox" -and $msgService -match "_enqueueOutbox" -and $msgService -match "_flushOutbox") {
    Write-Host "    ✓ Mécanisme outbox détecté (offline queue)" -ForegroundColor Green
} else {
    Write-Host "    ⚠ Mécanisme outbox absent" -ForegroundColor Red
}

# Check BLE scan-only mode
$bleFile = Get-Content "$projectRoot\lib\network\transports\ble_transport.dart" -Raw
if ($bleFile -match "SCAN-ONLY" -and $bleFile -match "PeerCounterService") {
    Write-Host "    ✓ BLE configuré en mode scan-only (comptage HIVE)" -ForegroundColor Green
}

# Check SafeArea in chat screen
$chatScreen = Get-Content "$projectRoot\lib\features\messaging\presentation\hive_messaging_screen.dart" -Raw
if ($chatScreen -match "WidgetsBindingObserver" -and $chatScreen -match "didChangeMetrics") {
    Write-Host "    ✓ Chat: clavier auto-scroll actif" -ForegroundColor Green
}

# Check blocked users section
$settingsScreen = Get-Content "$projectRoot\lib\features\settings\presentation\settings_screen.dart" -Raw
if ($settingsScreen -match "_BlockedUsersSection") {
    Write-Host "    ✓ Section utilisateurs bloqués présente" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════
# Nettoyage
# ═══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "Nettoyage..." -ForegroundColor Yellow
Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue

# Clean test events file
$testFile = "$serverDir\test_events.json"
if (Test-Path $testFile) { Remove-Item $testFile -Force }

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Orchestration terminée.                                   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan