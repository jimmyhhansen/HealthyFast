# Bygger HealthyFast for lukket testing (phone + watch).
# Oker automatisk byggnummeret i pubspec.yaml hver gang, og setter
# TESTER_BUILD=true slik at testere kan lase opp appen uten a betale.
#
# Bruk:  .\build_testers.ps1
#
# IKKE bruk disse .aab-ene til produksjonssporet - de inneholder
# tester-opplasning (gratis tilgang).

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pubspec = Join-Path $scriptDir "pubspec.yaml"

# --- Les og ok byggnummeret (delen etter +) ---
$content = Get-Content $pubspec -Raw
$pattern = '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
$match = [regex]::Match($content, $pattern)
if (-not $match.Success) {
    Write-Error "Fant ikke 'version: x.y.z+n' i pubspec.yaml"
    exit 1
}
$semver = $match.Groups[1].Value
$oldBuild = [int]$match.Groups[2].Value
$newBuild = $oldBuild + 1
$newVersion = "$semver+$newBuild"

$content = [regex]::Replace($content, $pattern, "version: $newVersion")
Set-Content -Path $pubspec -Value $content -NoNewline

Write-Host "Byggnummer: $oldBuild -> $newBuild  (versjon $newVersion)" -ForegroundColor Cyan

# --- Bygg begge varianter med testerflagget ---
Write-Host "`nBygger phone..." -ForegroundColor Yellow
flutter build appbundle --flavor phone --release --dart-define=TESTER_BUILD=true
if ($LASTEXITCODE -ne 0) { Write-Error "Phone-bygg feilet."; exit 1 }

Write-Host "`nBygger watch..." -ForegroundColor Yellow
flutter build appbundle --flavor watch --release --dart-define=TESTER_BUILD=true
if ($LASTEXITCODE -ne 0) { Write-Error "Watch-bygg feilet."; exit 1 }

Write-Host "`nFerdig. Versjon $newVersion bygget for begge varianter." -ForegroundColor Green

# --- Kopier til rot build-mappe for enkel tilgang ---
$outRoot = Join-Path $scriptDir "build"
if (-not (Test-Path $outRoot)) { New-Item -ItemType Directory -Path $outRoot | Out-Null }

$phoneSrc = Join-Path $scriptDir "build\app\outputs\bundle\phoneRelease\app-phone-release.aab"
$watchSrc = Join-Path $scriptDir "build\app\outputs\bundle\watchRelease\app-watch-release.aab"

$phoneDst = Join-Path $outRoot "HealthyFast-phone-testers-v$newBuild.aab"
$watchDst = Join-Path $outRoot "HealthyFast-watch-testers-v$newBuild.aab"

if (Test-Path $phoneSrc) { Copy-Item $phoneSrc $phoneDst; Write-Host "Kopiert phone til: $phoneDst" -ForegroundColor Cyan }
if (Test-Path $watchSrc) { Copy-Item $watchSrc $watchDst; Write-Host "Kopiert watch til: $watchDst" -ForegroundColor Cyan }
