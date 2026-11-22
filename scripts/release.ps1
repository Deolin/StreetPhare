# scripts/release.ps1
#
# Publication d'une release StreetPhare.
#
# Ce script :
#   1. Lit la version actuelle dans pubspec.yaml.
#   2. Calcule la nouvelle version (bump patch/minor/major ou version explicite).
#   3. Met à jour pubspec.yaml (version X.Y.Z[-prerelease]+BUILD, numéro de
#      build incrémenté).
#   4. Commit + crée le tag `vX.Y.Z[-prerelease]` + pousse.
#
# Le tag poussé déclenche automatiquement le workflow GitHub Actions
# `.github/workflows/release.yml`, qui construit les exécutables
# (Windows EXE, Linux tar.gz, Android APK + AAB) puis crée la release GitHub
# consultée par le gestionnaire de mises à jour de l'application.
#
# Usage :
#   powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Bump patch
#   powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 2.3.0
#   powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.5.0-alpha
#   powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Bump minor -Prerelease beta
#
# Options :
#   -Bump patch|minor|major   Incrémente la composante correspondante (conserve
#                             le suffixe pré-release actuel, ex: 0.4.0-alpha
#                             -> 0.5.0-alpha).
#   -Version "X.Y.Z"          Force une version exacte. Accepte aussi un suffixe
#                             pré-release : "0.5.0-alpha", "0.5.0-beta.1",
#                             "v0.5.0-alpha".
#   -Prerelease "alpha"       Suffixe pré-release optionnel (ex: alpha, beta.1,
#                             rc.1). Prioritaire sur les autres sources. Passer
#                             "" supprime le suffixe (version stable).
#   -Message "..."            Message de commit (défaut : release: vX.Y.Z).
#   -DryRun                   Affiche les actions sans rien modifier.
#   -SkipPush                 Ne pousse pas (commit/tag locaux uniquement).

param(
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Bump = '',

    [string]$Version = '',

    # Suffixe pré-release optionnel (ex: alpha, beta.1, rc.1). Prioritaire.
    [string]$Prerelease = '',

    [string]$Message = '',

    [switch]$DryRun,

    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir '..')
$pubspec = Join-Path $projectRoot 'pubspec.yaml'

if (-not (Test-Path $pubspec)) {
    Write-Error "pubspec.yaml introuvable : $pubspec"
    exit 1
}

$content = Get-Content $pubspec -Raw

$match = [regex]::Match($content, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?\+(\d+)')
if (-not $match.Success) {
    Write-Error "Impossible de lire la version dans pubspec.yaml (attendu : version: X.Y.Z+BUILD ou version: X.Y.Z-prerelease+BUILD)."
    exit 1
}

$curMajor = [int]$match.Groups[1].Value
$curMinor = [int]$match.Groups[2].Value
$curPatch = [int]$match.Groups[3].Value
$curPrerelease = if ($match.Groups[4].Success) { $match.Groups[4].Value } else { '' }
$curBuild = [int]$match.Groups[5].Value

$newMajor = $curMajor
$newMinor = $curMinor
$newPatch = $curPatch
$newPrerelease = $curPrerelease   # par défaut : on conserve le suffixe actuel

if ($Version -ne '') {
    # Normalise un éventuel préfixe v/V (ex: v0.5.0-alpha -> 0.5.0-alpha).
    $normalized = $Version.Trim() -replace '^[vV]+', ''
    $vm = [regex]::Match($normalized, '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$')
    if (-not $vm.Success) {
        Write-Error "Le paramètre -Version doit être au format X.Y.Z[-prerelease] (ex: 2.3.0, 0.5.0-alpha, 0.5.0-beta.1)."
        exit 1
    }
    $newMajor = [int]$vm.Groups[1].Value
    $newMinor = [int]$vm.Groups[2].Value
    $newPatch = [int]$vm.Groups[3].Value
    $newPrerelease = if ($vm.Groups[4].Success) { $vm.Groups[4].Value } else { '' }
}
elseif ($Bump -ne '') {
    switch ($Bump) {
        'major' { $newMajor++; $newMinor = 0; $newPatch = 0 }
        'minor' { $newMinor++; $newPatch = 0 }
        'patch' { $newPatch++ }
    }
    # Le suffixe pré-release actuel est conservé (ex: 0.4.0-alpha -> 0.5.0-alpha).
}
else {
    Write-Error "Précisez -Bump patch|minor|major OU -Version X.Y.Z[-prerelease]."
    exit 1
}

# L'option -Prerelease (si explicitement fournie) écrase le suffixe résolu.
if ($PSBoundParameters.ContainsKey('Prerelease')) {
    $newPrerelease = $Prerelease
}

# Validation du suffixe pré-release final.
if ($newPrerelease -ne '' -and $newPrerelease -notmatch '^[0-9A-Za-z][0-9A-Za-z.-]*$') {
    Write-Error "Le suffixe pré-release '$newPrerelease' est invalide (autorisé : lettres, chiffres, point et tiret, ex: alpha, beta.1, rc.2)."
    exit 1
}

$newBuild = $curBuild + 1
$newVersionBase = "$newMajor.$newMinor.$newPatch"
$newVersion = if ($newPrerelease -ne '') { "$newVersionBase-$newPrerelease" } else { $newVersionBase }
$newVersionLine = "version: $newVersion+$newBuild"
$tag = "v$newVersion"

if (($newMajor -eq $curMajor) -and ($newMinor -eq $curMinor) -and ($newPatch -eq $curPatch) -and ($newPrerelease -eq $curPrerelease)) {
    Write-Warning "La nouvelle version ($newVersion) est identique à l'actuelle. Le tag $tag existe peut-être déjà."
}

$commitMessage = if ($Message -ne '') { $Message } else { "release: $tag" }

Write-Host ''
Write-Host '═══ Publication release StreetPhare ═══' -ForegroundColor Cyan
$curDisplay = if ($curPrerelease -ne '') { "$curMajor.$curMinor.$curPatch-$curPrerelease" } else { "$curMajor.$curMinor.$curPatch" }
Write-Host "  Version actuelle : ${curDisplay}+$curBuild"
Write-Host "  Nouvelle version : $newVersion+$newBuild"
Write-Host "  Tag               : $tag"
Write-Host "  Message de commit : $commitMessage"
Write-Host ''

if ($DryRun) {
    Write-Host '[DryRun] Aucune modification effectuée.' -ForegroundColor Yellow
    exit 0
}

Push-Location $projectRoot
try {
    # 1. Mise à jour de pubspec.yaml (écriture UTF-8 sans BOM, sans altérer
    #    le reste du fichier ni le retour à la ligne final).
    $content = [regex]::Replace(
        $content,
        '(?m)^version:\s*\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\+\d+',
        $newVersionLine
    )
    [System.IO.File]::WriteAllText($pubspec, $content)
    Write-Host "[1/4] pubspec.yaml -> $newVersionLine" -ForegroundColor Green

    # 2. Commit
    git add pubspec.yaml
    git commit -m "$commitMessage"
    if ($LASTEXITCODE -ne 0) {
        throw "Échec du commit git."
    }
    Write-Host "[2/4] Commit créé." -ForegroundColor Green

    # 3. Tag
    git tag "$tag"
    if ($LASTEXITCODE -ne 0) {
        throw "Échec de la création du tag $tag."
    }
    Write-Host "[3/4] Tag $tag créé." -ForegroundColor Green

    # 4. Push (commit + tag)
    if (-not $SkipPush) {
        git push
        if ($LASTEXITCODE -ne 0) {
            throw "Échec du git push."
        }
        git push origin "$tag"
        if ($LASTEXITCODE -ne 0) {
            throw "Échec du git push du tag $tag."
        }
        Write-Host "[4/4] Commit + tag poussés sur origin." -ForegroundColor Green
    }
    else {
        Write-Host "[4/4] -SkipPush : push ignoré (commit/tag locaux uniquement)." -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host '✅ Le tag a été poussé. Le workflow de release est déclenché :' -ForegroundColor Green
Write-Host '   https://github.com/Deolin/StreetPhare/actions/workflows/release.yml' -ForegroundColor Cyan
Write-Host '   La release apparaîtra ici une fois le build terminé :' -ForegroundColor Cyan
Write-Host '   https://github.com/Deolin/StreetPhare/releases' -ForegroundColor Cyan
