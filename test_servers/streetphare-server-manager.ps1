<#
.SYNOPSIS
    StreetPhare Server Manager — Gestionnaire Windows des serveurs Node.js
    
.DESCRIPTION
    Script PowerShell autonome pour gérer les serveurs StreetPhare sur Windows.
    Fonctionnalités :
      - Démarrer / Arrêter / Redémarrer les serveurs
      - Surveiller le statut en temps réel
      - Ouvrir le Dashboard Admin dans le navigateur
      - Interface CLI interactive
      
.USAGE
    .\streetphare-server-manager.ps1              → Menu interactif
    .\streetphare-server-manager.ps1 start        → Démarrer tous les serveurs
    .\streetphare-server-manager.ps1 stop         → Arrêter tous les serveurs
    .\streetphare-server-manager.ps1 status       → Afficher le statut
    .\streetphare-server-manager.ps1 restart      → Redémarrer tous les serveurs
    .\streetphare-server-manager.ps1 dashboard    → Ouvrir le dashboard admin

.NOTES
    Auteur  : StreetPhare DevOps
    Version : 1.0
    Requires: Node.js installé, fichiers serveurs dans test_servers/
#>

param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status','dashboard','','help')]
    [string]$Command = ''
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:LogDir    = Join-Path $ScriptDir "logs"
$Script:PidFile   = Join-Path $ScriptDir ".server-pids.json"

$Script:Servers = @(
    @{
        Name    = "Serveur Principal"
        Script  = "server_primary_v2.js"
        Port    = 3000
        EnvVars = @{
            PORT                   = "3000"
            ROLE                   = "primary"
            NEXT_BACKUP_URL        = "http://localhost:3001"
            STREETPHARE_MASTER_KEY = "streetphare-dev-key-CHANGE_ME_IN_PROD"
            STREETPHARE_LOG        = "1"
            NODE_ENV               = "development"
        }
    },
    @{
        Name    = "Serveur Backup"
        Script  = "server_secondary_v2.js"
        Port    = 3001
        EnvVars = @{
            PORT                   = "3001"
            ROLE                   = "secondary"
            PRIMARY_URL            = "http://localhost:3000"
            STREETPHARE_MASTER_KEY = "streetphare-dev-key-CHANGE_ME_IN_PROD"
            STREETPHARE_LOG        = "1"
            NODE_ENV               = "development"
        }
    },
    @{
        Name    = "Admin Dashboard"
        Script  = "admin_dashboard.js"
        Port    = 4000
        EnvVars = @{
            ADMIN_PORT    = "4000"
            PRIMARY_URL   = "http://localhost:3000"
            SECONDARY_URL = "http://localhost:3001"
            NODE_ENV      = "development"
        }
    }
)

# ============================================================================
# COULEURS & AFFICHAGE
# ============================================================================

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║  🔦  StreetPhare Server Manager  v1.0            ║" -ForegroundColor Yellow
    Write-Host "  ║      Gestionnaire de serveurs Node.js Windows     ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
}

function Write-OK    { param($msg) Write-Host "  ✅  $msg" -ForegroundColor Green }
function Write-ERR   { param($msg) Write-Host "  ❌  $msg" -ForegroundColor Red }
function Write-WARN  { param($msg) Write-Host "  ⚠️   $msg" -ForegroundColor Yellow }
function Write-INFO  { param($msg) Write-Host "  ℹ️   $msg" -ForegroundColor Cyan }
function Write-STEP  { param($msg) Write-Host "  ▶   $msg" -ForegroundColor White }

# ============================================================================
# GESTION DES PIDS
# ============================================================================

function Save-Pids($pidMap) {
    $pidMap | ConvertTo-Json | Set-Content $Script:PidFile -Encoding UTF8
}

function Get-Pids {
    if (Test-Path $Script:PidFile) {
        try {
            return Get-Content $Script:PidFile -Raw | ConvertFrom-Json -AsHashtable
        } catch { }
    }
    return @{}
}

function Remove-PidFile {
    if (Test-Path $Script:PidFile) { Remove-Item $Script:PidFile -Force }
}

# ============================================================================
# VÉRIFICATION DU PORT
# ============================================================================

function Test-Port($port) {
    try {
        $conn = New-Object System.Net.Sockets.TcpClient
        $conn.Connect("127.0.0.1", $port)
        $conn.Close()
        return $true
    } catch {
        return $false
    }
}

# ============================================================================
# DÉMARRAGE D'UN SERVEUR
# ============================================================================

function Start-Server($server) {
    $scriptPath = Join-Path $Script:ScriptDir $server.Script
    
    if (-not (Test-Path $scriptPath)) {
        Write-ERR "Script introuvable : $scriptPath"
        return $null
    }
    
    if (Test-Port $server.Port) {
        Write-WARN "$($server.Name) déjà en cours sur :$($server.Port)"
        return $null
    }
    
    # Prépare le répertoire de logs
    if (-not (Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir | Out-Null
    }
    $logFile = Join-Path $Script:LogDir "$($server.Script -replace '\.js$','').log"
    
    # Lance le processus Node.js en arrière-plan
    $proc = Start-Process -FilePath "node" `
        -ArgumentList $scriptPath `
        -WorkingDirectory $Script:ScriptDir `
        -RedirectStandardOutput $logFile `
        -RedirectStandardError "$logFile.err" `
        -Environment ($server.EnvVars) `
        -PassThru `
        -WindowStyle Hidden
    
    Start-Sleep -Milliseconds 800
    
    if ($proc -and -not $proc.HasExited) {
        Write-OK "$($server.Name) démarré (PID=$($proc.Id), :$($server.Port))"
        return $proc.Id
    } else {
        Write-ERR "Échec démarrage $($server.Name)"
        return $null
    }
}

# ============================================================================
# ARRÊT D'UN SERVEUR
# ============================================================================

function Stop-Server($server, $pids) {
    $pida = $pids[$server.Name]
    $stopped = $false
    
    # Tentative via PID enregistré
    if ($pida) {
        try {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $pida -Force
                $stopped = $true
            }
        } catch { }
    }
    
    # Fallback : tue tout processus node sur ce port
    if (-not $stopped) {
        $netstat = netstat -ano 2>$null | Select-String ":$($server.Port)\s"
        if ($netstat) {
            $netstat | ForEach-Object {
                $parts = $_ -split '\s+'
                $pidFromNet = $parts[-1]
                if ($pidFromNet -match '^\d+$') {
                    try {
                        Stop-Process -Id ([int]$pidFromNet) -Force -ErrorAction SilentlyContinue
                        $stopped = $true
                    } catch { }
                }
            }
        }
    }
    
    if ($stopped) {
        Write-OK "$($server.Name) arrêté"
    } else {
        Write-WARN "$($server.Name) n'était pas démarré"
    }
    return $stopped
}

# ============================================================================
# AFFICHAGE DU STATUT
# ============================================================================

function Show-Status {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │              STATUT DES SERVEURS                 │" -ForegroundColor Cyan
    Write-Host "  ├─────────────────────────────────────────────────┤" -ForegroundColor Cyan
    
    foreach ($server in $Script:Servers) {
        $online = Test-Port $server.Port
        $status  = if ($online) { "🟢 EN LIGNE " } else { "🔴 HORS LIGNE" }
        $portStr = ":$($server.Port)".PadLeft(5)
        $name    = $server.Name.PadRight(20)
        Write-Host "  │  $status  $name  $portStr  │" -ForegroundColor $(if ($online) { 'Green' } else { 'Red' })
    }
    
    Write-Host "  └─────────────────────────────────────────────────┘" -ForegroundColor Cyan
    
    if (Test-Port 4000) {
        Write-Host ""
        Write-INFO "Dashboard Admin → http://localhost:4000/admin"
    }
    Write-Host ""
}

# ============================================================================
# ACTIONS PRINCIPALES
# ============================================================================

function Start-AllServers {
    Write-STEP "Démarrage de tous les serveurs StreetPhare…"
    $pids = @{}
    foreach ($server in $Script:Servers) {
        $pida = Start-Server $server
        if ($pida) { $pids[$server.Name] = $pida }
        Start-Sleep -Milliseconds 400
    }
    Save-Pids $pids
    Write-Host ""
    Show-Status
    
    if (Test-Port 4000) {
        Write-OK "Dashboard Admin accessible → http://localhost:4000/admin"
    }
}

function Stop-AllServers {
    Write-STEP "Arrêt de tous les serveurs StreetPhare…"
    $pids = Load-Pids
    foreach ($server in $Script:Servers) {
        Stop-Server $server $pids
    }
    Remove-PidFile
    Write-Host ""
}

function Restart-AllServers {
    Stop-AllServers
    Start-Sleep -Seconds 1
    Start-AllServers
}

function Open-Dashboard {
    if (Test-Port 4000) {
        Write-INFO "Ouverture du Dashboard Admin…"
        Start-Process "http://localhost:4000/admin"
    } else {
        Write-WARN "Dashboard Admin non démarré. Lancez 'start' d'abord."
    }
}

# ============================================================================
# MENU INTERACTIF
# ============================================================================

function Show-Menu {
    Write-Header
    Show-Status
    
    Write-Host "  COMMANDES :" -ForegroundColor White
    Write-Host "  [1] Démarrer tous les serveurs" -ForegroundColor Cyan
    Write-Host "  [2] Arrêter tous les serveurs" -ForegroundColor Cyan
    Write-Host "  [3] Redémarrer tous les serveurs" -ForegroundColor Cyan
    Write-Host "  [4] Rafraîchir le statut" -ForegroundColor Cyan
    Write-Host "  [5] Ouvrir le Dashboard Admin" -ForegroundColor Cyan
    Write-Host "  [6] Afficher les logs (Serveur Principal)" -ForegroundColor Cyan
    Write-Host "  [Q] Quitter" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "  Votre choix"
    switch ($choice.ToUpper()) {
        '1' { Start-AllServers; Wait-And-Return }
        '2' { Stop-AllServers;  Wait-And-Return }
        '3' { Restart-AllServers; Wait-And-Return }
        '4' { Show-Menu }
        '5' { Open-Dashboard; Wait-And-Return }
        '6' { Show-Logs; Wait-And-Return }
        'Q' { Write-Host ""; Write-OK "Au revoir !"; exit 0 }
        default { Show-Menu }
    }
}

function Wait-And-Return {
    Write-Host ""
    Write-Host "  Appuyez sur Entrée pour revenir au menu…" -ForegroundColor Gray
    Read-Host | Out-Null
    Show-Menu
}

function Show-Logs {
    $logFile = Join-Path $Script:LogDir "server_primary_v2.log"
    if (Test-Path $logFile) {
        Write-Host ""
        Write-Host "  ── Dernières lignes du log serveur principal ──" -ForegroundColor Yellow
        Get-Content $logFile -Tail 30 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkGray
        }
    } else {
        Write-WARN "Aucun log disponible. Démarrez les serveurs d'abord."
    }
}

# ============================================================================
# POINT D'ENTRÉE
# ============================================================================

switch ($Command.ToLower()) {
    'start'     { Write-Header; Start-AllServers }
    'stop'      { Write-Header; Stop-AllServers }
    'restart'   { Write-Header; Restart-AllServers }
    'status'    { Write-Header; Show-Status }
    'dashboard' { Open-Dashboard }
    'help'      {
        Write-Host ""
        Write-Host "StreetPhare Server Manager — Usage :" -ForegroundColor Yellow
        Write-Host "  .\streetphare-server-manager.ps1 start     → Démarrer"
        Write-Host "  .\streetphare-server-manager.ps1 stop      → Arrêter"
        Write-Host "  .\streetphare-server-manager.ps1 restart   → Redémarrer"
        Write-Host "  .\streetphare-server-manager.ps1 status    → Statut"
        Write-Host "  .\streetphare-server-manager.ps1 dashboard → Ouvrir Admin"
        Write-Host "  .\streetphare-server-manager.ps1           → Menu interactif"
        Write-Host ""
    }
    default     { Show-Menu }
}
