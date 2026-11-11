# scripts/sync_branding.ps1
#
# Wrapper PowerShell (Windows) autour de scripts/sync_branding.js.
# Utile car `node` n'est pas toujours dans le PATH sous Windows.
#
# Usage :
#   .\scripts\sync_branding.ps1           # copie assets/branding → web/ et web_vitrine/
#   .\scripts\sync_branding.ps1 -Check    # vérifie la synchronisation (exit 1 si divergence)

param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$node = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $node) {
    $nodePath = Join-Path $env:ProgramFiles "nodejs\node.exe"
    if (-not (Test-Path -LiteralPath $nodePath)) {
        Write-Error "Node.js introuvable. Installez Node.js ou ajoutez-le au PATH."
        exit 1
    }
    $nodeExe = $nodePath
} else {
    $nodeExe = "node"
}

$scriptPath = Join-Path $PSScriptRoot "sync_branding.js"
$nodeArgs = @($scriptPath)
if ($Check) {
    $nodeArgs += "--check"
}
& $nodeExe @nodeArgs
exit $LASTEXITCODE

