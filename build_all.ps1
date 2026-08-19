# Bygger ALT i ett steg og BEHOLDER loggen:
#   1. setter riktig prosjektmappe (uansett hvor du starter fra)
#   2. rydder gammelt bygg (viktig etter native/Gradle-endringer)
#   3. henter pakker
#   4. kjorer Dart-analyse (bare et varsel, stopper ikke bygget)
#   5. oker byggnummeret og bygger BADE telefon og klokke (produksjon)
#   6. apner mappa med .aab-filene
#
# Hele konsoll-loggen lagres til build_logs\build_<dato>_<tid>.log
# Vinduet lukker seg IKKE av seg selv - det venter pa Enter til slutt,
# ogsa hvis bygget feiler.
#
# Bruk:  hoyreklikk -> "Run with PowerShell"
#   eller:  powershell -ExecutionPolicy Bypass -File "D:\Appdev\Android\HealthyFast\build_all.ps1"

# "Continue", ikke "Stop": med '2>&1 | Out-Host' blir stderr-linjer fra
# flutter/gradle til ErrorRecords, og "Stop" ville gjort en ufarlig
# advarsel (f.eks. ".dart_tool kunne ikke slettes") til byggstopp.
# Feilhaandtering skjer eksplisitt via $LASTEXITCODE-sjekkene under.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# --- Logg-oppsett ---
$logDir = Join-Path $root "build_logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "build_$stamp.log"

Start-Transcript -Path $logFile -Force | Out-Null
$ok = $false
try {
    Write-Host "Prosjektmappe: $root" -ForegroundColor Cyan
    Write-Host "Logg lagres til: $logFile" -ForegroundColor Cyan

    # MERK: native exe-output (flutter/gradle) gaar utenom transcriptet i
    # Windows PowerShell 5.1. '2>&1 | Out-Host' tvinger outputen gjennom
    # PowerShell-pipelinen slik at feilmeldinger faktisk havner i loggen.

    Write-Host "`n[1/5] flutter clean..." -ForegroundColor Yellow
    flutter clean 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter clean feilet." }

    Write-Host "`n[2/5] flutter pub get..." -ForegroundColor Yellow
    flutter pub get 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get feilet." }

    Write-Host "`n[3/5] flutter analyze (informativt)..." -ForegroundColor Yellow
    flutter analyze 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Analyse fant advarsler/feil - sjekk over. Fortsetter;" -ForegroundColor DarkYellow
        Write-Host "  ekte kompileringsfeil vil uansett stoppe bygget under." -ForegroundColor DarkYellow
    }

    Write-Host "`n[4/5] Bygger produksjon (phone + watch, oker byggnummer)..." -ForegroundColor Yellow
    # Kjores i egen prosess slik at 'exit' inne i build_production.ps1 ikke
    # river ned dette vinduet - da rekker vi alltid a lagre logg og pause.
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "build_production.ps1") 2>&1 | Out-Host
    $buildExit = $LASTEXITCODE
    if ($buildExit -ne 0) { throw "Produksjonsbygg feilet (exit $buildExit). Se loggen over." }

    Write-Host "`n[5/5] Apner output-mappa..." -ForegroundColor Yellow
    $out = Join-Path $root "build\app\outputs\bundle"
    if (Test-Path $out) { explorer $out }

    $ok = $true
}
catch {
    Write-Host "`nFEIL: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($ok) {
        Write-Host "`nFerdig. .aab-er ligger direkte i build\-mappa på rot." -ForegroundColor Green
    } else {
        Write-Host "`nBygget stoppet uten a fullfore. Les loggen over / i fila." -ForegroundColor Red
    }
    Write-Host "Full logg: $logFile" -ForegroundColor Cyan
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host "`nVinduet blir staaende. Trykk Enter for a lukke..." -ForegroundColor Cyan
    [void](Read-Host)
}
