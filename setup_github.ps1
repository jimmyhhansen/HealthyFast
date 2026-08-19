<#
.SYNOPSIS
    Oppretter et privat GitHub-repo for HealthyFast og pusher koden, slik at
    Mac-en kan klone i stedet for at du må kopiere filer manuelt.

.DESCRIPTION
    HealthyFast har i dag ingen git-remote — repoet er kun lokalt med én commit.
    Dette scriptet:

      1. Verifiserer at repoet er ryddet (kjør cleanup_for_git.ps1 først).
      2. Oppretter et PRIVAT GitHub-repo via gh CLI hvis den er installert,
         ellers skriver den ut nøyaktig hva du må gjøre manuelt.
      3. Legger til 'origin' og pusher.

    Repoet MÅ være privat: android/app/google-services.json og Firebase-nøkler
    ligger sporet i git.

.PARAMETER RepoName
    Navn på GitHub-repoet. Standard: healthyfast

.PARAMETER Public
    Opprett offentlig repo. IKKE bruk denne uten å ha fjernet nøkler først.

.PARAMETER RemoteUrl
    Hvis du har opprettet repoet manuelt i nettleseren, oppgi URL-en her
    (f.eks. https://github.com/dittbrukernavn/healthyfast.git) så hopper
    scriptet over gh CLI.

.PARAMETER FreshHistory
    Start git-historikken på nytt (sletter den ene eksisterende commiten og
    lager én ny "clean" commit). Bruk denne hvis .git-mappa er stor fordi
    node_modules ligger i historikken. Lager backup-branch først.

.PARAMETER RenameToMain
    Døp om branchen fra 'master' til 'main' (GitHub-standard).

.EXAMPLE
    .\setup_github.ps1 -RepoName healthyfast -FreshHistory -RenameToMain

.EXAMPLE
    .\setup_github.ps1 -RemoteUrl https://github.com/jimmyh/healthyfast.git
#>

[CmdletBinding()]
param(
    [string]$RepoName = 'healthyfast',
    [switch]$Public,
    [string]$RemoteUrl,
    [switch]$FreshHistory,
    [switch]$RenameToMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell 7.4+ gjør ellers exit-kode != 0 fra git/gh til en terminerende
# feil. Vi sjekker $LASTEXITCODE selv der det er relevant. (Ukjent variabel i
# 5.1 — assignment er harmløs der.)
$PSNativeCommandUseErrorActionPreference = $false

# Testet på Windows PowerShell 5.1 og PowerShell 7.x.
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "Krever PowerShell 5.1 eller nyere. Du kjører $($PSVersionTable.PSVersion)."
}

function Write-Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  [!]    $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Gray }

# git og gh skriver rutinemessig statustekst til stderr (git push sin
# "Enumerating objects...", gh sin "Creating repository..." osv.) — dette er
# IKKE feil. I Windows PowerShell 5.1 pakker $ErrorActionPreference='Stop'
# likevel denne teksten inn som en terminerende feil, selv når kommandoen
# lykkes. Alle native kall går derfor via disse to hjelperne, som midlertidig
# slår av 'Stop' og lar oss selv sjekke $LASTEXITCODE — det tallet lyver aldri.
# Begge er bevisst UTEN [Parameter(ValueFromRemainingArguments)]: det gjør
# funksjonen "advanced" og gir den skjulte fellesparametre som -Debug — og
# siden -D er en entydig forkortelse av -Debug, ville PowerShell da stille og
# rolig SPIST "-D" (f.eks. i 'git branch -D gammelgren') før git noensinne
# fikk se det. Den automatiske $args-variabelen unngår parameterbinding helt.
function Invoke-Git {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @args 2>&1
    } finally {
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{
        Output   = @($output | ForEach-Object { "$_" })
        ExitCode = $LASTEXITCODE
    }
}

function Invoke-Gh {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & gh @args 2>&1
    } finally {
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{
        Output   = @($output | ForEach-Object { "$_" })
        ExitCode = $LASTEXITCODE
    }
}

function Write-NativeOutput($lines) {
    $lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
}

function Assert-NoGitLock($repoRoot) {
    $lockFile = Join-Path $repoRoot '.git\index.lock'
    if (Test-Path -LiteralPath $lockFile) {
        Write-Warn2 "'.git\index.lock' finnes fra et tidligere avbrutt git-kall."
        Write-Info "Lukk VS Code / Android Studio / GitHub Desktop / andre git-verktøy som har denne mappa åpen, sjekk så om noe fortsatt kjører:"
        Write-Info "  Get-Process | Where-Object { `$_.Name -match 'git|code|studio64|GitHubDesktop' }"
        Write-Info "Fjern deretter selve låsfila:"
        Write-Info "  Remove-Item `"$lockFile`" -Force"
        throw "Avbryter — index.lock må fjernes manuelt før scriptet kan kjøre trygt."
    }
}

Set-Location -LiteralPath $PSScriptRoot

# --- 0. Forutsetninger ------------------------------------------------------

Write-Step "Sjekker forutsetninger"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git er ikke installert eller ikke på PATH."
}
if (-not (Test-Path '.\pubspec.yaml')) {
    throw "Kjør scriptet fra rota av HealthyFast-prosjektet."
}
if (-not (Test-Path '.\.git')) {
    Write-Info "Ingen .git-mappe — initialiserer."
    $r = Invoke-Git init -q
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "git init feilet." }
    $r = Invoke-Git add -A
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "git add feilet." }
    $r = Invoke-Git commit -q -m "HealthyFast"
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Første commit feilet." }
}
Assert-NoGitLock $PSScriptRoot
Write-Ok "git funnet: $((Invoke-Git --version).Output)"

# Identitet må være satt, ellers feiler commit.
$userName  = (Invoke-Git config user.name).Output  | Select-Object -First 1
$userEmail = (Invoke-Git config user.email).Output | Select-Object -First 1
if (-not $userName -or -not $userEmail) {
    Write-Warn2 "git user.name / user.email er ikke satt. Sett dem nå:"
    Write-Info '  git config --global user.name "Jimmy Hansen"'
    Write-Info '  git config --global user.email "jimmyhhansen@gmail.com"'
    throw "Avbryter — sett git-identitet og kjør på nytt."
}
Write-Ok "Committer som $userName <$userEmail>"

# --- 1. Er repoet ryddet? ---------------------------------------------------

Write-Step "Verifiserer at repoet er ryddet"

$nodeModulesTracked = @((Invoke-Git ls-files -- 'functions/node_modules').Output).Count
if ($nodeModulesTracked -gt 0) {
    Write-Warn2 "$nodeModulesTracked filer fra functions/node_modules ligger fortsatt i git."
    Write-Info "Kjør .\cleanup_for_git.ps1 først — ellers blir pushen unødvendig tung."
    $answer = Read-Host "  Fortsette likevel? (j/N)"
    if ($answer -notmatch '^[jJyY]') { throw "Avbrutt." }
} else {
    Write-Ok "node_modules er ikke sporet."
}

$trackedCount = @((Invoke-Git ls-files).Output).Count
Write-Info "Sporede filer: $trackedCount"

# --- 2. Fersk historikk (valgfritt) ----------------------------------------

if ($FreshHistory) {
    Write-Step "Starter git-historikken på nytt"

    $currentBranch = ((Invoke-Git rev-parse --abbrev-ref HEAD).Output | Select-Object -First 1).Trim()
    $backup = "backup-pre-fresh-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    Write-Info "Nåværende branch: $currentBranch"
    Write-Info "Lager backup-branch: $backup"
    $r = Invoke-Git branch $backup
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Kunne ikke lage backup-branch '$backup'." }

    # Orphan branch = ny historikk uten forelder.
    $r = Invoke-Git checkout -q --orphan __fresh
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "git checkout --orphan feilet." }
    $r = Invoke-Git add -A
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "git add -A feilet under fresh history." }
    $r = Invoke-Git commit -q -m "HealthyFast 2.0.0+226 - Android-utgivelse, klar for iOS-oppsett"
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Commit av ny historikk feilet." }
    $r = Invoke-Git branch -D $currentBranch
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Kunne ikke slette gammel branch '$currentBranch'." }
    $r = Invoke-Git branch -m $currentBranch
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Kunne ikke gi __fresh navnet '$currentBranch' tilbake." }

    Write-Ok "Ny historikk laget. Gammel commit ligger i branch '$backup' (lokalt)."
    Write-Info "Kjør 'git gc --aggressive --prune=now' etterpå for å faktisk krympe .git."
}

# --- 3. Branch-navn ---------------------------------------------------------

$branch = ((Invoke-Git rev-parse --abbrev-ref HEAD).Output | Select-Object -First 1).Trim()
if ($RenameToMain -and $branch -ne 'main') {
    Write-Step "Døper om branch"
    $r = Invoke-Git branch -M main
    if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Kunne ikke døpe om branch til 'main'." }
    $branch = 'main'
    Write-Ok "Branch heter nå 'main'."
}
Write-Info "Pusher branch: $branch"

# --- 4. Opprett/koble remote -----------------------------------------------

Write-Step "Setter opp GitHub-remote"

$r = Invoke-Git remote get-url origin
if ($r.ExitCode -eq 0 -and $r.Output) {
    $existingRemote = ($r.Output | Select-Object -First 1).Trim()
    Write-Ok "'origin' finnes allerede: $existingRemote"
    $RemoteUrl = $existingRemote
}

if (-not $RemoteUrl) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue

    if ($gh) {
        Write-Ok "gh CLI funnet — oppretter repo automatisk."

        # Er vi innlogget?
        $r = Invoke-Gh auth status
        if ($r.ExitCode -ne 0) {
            Write-Warn2 "Ikke innlogget i gh. Kjører 'gh auth login' — følg instruksjonene."
            # Interaktiv — kjøres direkte (uten output-capture) slik at prompter vises normalt.
            # 'Continue' lokalt hindrer at gh sin egen statustekst på stderr avbryter scriptet.
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & gh auth login
            $loginExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($loginExit -ne 0) { throw "gh auth login feilet." }
        }

        $visibility = if ($Public) { '--public' } else { '--private' }
        if ($Public) {
            Write-Warn2 "Du har valgt OFFENTLIG repo. android/app/google-services.json er sporet."
            $answer = Read-Host "  Er du sikker? (j/N)"
            if ($answer -notmatch '^[jJyY]') { throw "Avbrutt." }
        }

        Write-Info "gh repo create $RepoName $visibility --source=. --remote=origin"
        $r = Invoke-Gh repo create $RepoName $visibility --source=. --remote=origin --description "HealthyFast - fasting, calorie tracking and strength training (Flutter)"
        if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "gh repo create feilet." }

        $r = Invoke-Git remote get-url origin
        if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Repo ble opprettet, men fant ikke 'origin' etterpå." }
        $RemoteUrl = ($r.Output | Select-Object -First 1).Trim()
        Write-Ok "Repo opprettet: $RemoteUrl"
    }
    else {
        Write-Warn2 "gh CLI er ikke installert. Gjør dette manuelt:"
        Write-Host ""
        Write-Host "  1. Gå til https://github.com/new" -ForegroundColor White
        Write-Host "  2. Repository name : $RepoName" -ForegroundColor White
        Write-Host "  3. Visibility      : PRIVATE  (viktig — Firebase-nøkler ligger i repoet)" -ForegroundColor White
        Write-Host "  4. IKKE huk av for README, .gitignore eller lisens" -ForegroundColor White
        Write-Host "  5. Klikk 'Create repository'" -ForegroundColor White
        Write-Host "  6. Kjør så dette scriptet på nytt med URL-en:" -ForegroundColor White
        Write-Host ""
        Write-Host "     .\setup_github.ps1 -RemoteUrl https://github.com/<bruker>/$RepoName.git" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  (Alternativt: installer gh CLI med 'winget install GitHub.cli' og kjør på nytt.)" -ForegroundColor Gray
        Write-Host ""
        return
    }
}
else {
    $r = Invoke-Git remote get-url origin
    if ($r.ExitCode -ne 0) {
        $r = Invoke-Git remote add origin $RemoteUrl
        if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "git remote add feilet." }
        Write-Ok "La til origin → $RemoteUrl"
    } else {
        $current = ($r.Output | Select-Object -First 1).Trim()
        if ($current -ne $RemoteUrl.Trim()) {
            $r = Invoke-Git remote set-url origin $RemoteUrl
            if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "git remote set-url feilet." }
            Write-Ok "Oppdaterte origin → $RemoteUrl"
        }
    }
}

# --- 5. Push ----------------------------------------------------------------

Write-Step "Pusher til GitHub"
Write-Info "Dette kan ta noen minutter første gang."

# Kjøres direkte (ikke via Invoke-Git) slik at du ser fremdriften live i
# stedet for å vente i stillhet til hele pushen er ferdig. 'Continue' lokalt
# hindrer at git sin egen "Enumerating objects..."-tekst på stderr avbryter
# scriptet, selv om pushen faktisk lykkes.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
git push -u origin $branch
$pushExit = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

if ($pushExit -ne 0) {
    Write-Warn2 "Push feilet."
    Write-Info "Vanlige årsaker:"
    Write-Info "  - Repoet er ikke tomt  → git push -u origin $branch --force"
    Write-Info "  - Fil over 100 MB      → kjør cleanup_for_git.ps1 og se 'store filer'"
    Write-Info "  - Autentisering        → gh auth login, eller bruk en Personal Access Token"
    throw "Push feilet."
}

Write-Ok "Pushet."

# --- 6. Neste steg ----------------------------------------------------------

$r = Invoke-Git remote get-url origin
if ($r.ExitCode -ne 0) { Write-NativeOutput $r.Output; throw "Push OK, men fant ikke 'origin' etterpå." }
$cloneUrl = ($r.Output | Select-Object -First 1).Trim()

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " FERDIG. Kjør dette på Mac-en:" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  git clone $cloneUrl" -ForegroundColor White
Write-Host "  cd $RepoName" -ForegroundColor White
Write-Host "  chmod +x setup_ios_mac.sh && ./setup_ios_mac.sh" -ForegroundColor White
Write-Host ""
Write-Host " Åpne så Claude Code i mappa og si:" -ForegroundColor Green
Write-Host '   "Les CLAUDE_MAC_HANDOFF.md og IOS_LAUNCH_CHECKLIST.md, og fortsett iOS-oppsettet."' -ForegroundColor White
Write-Host ""
Write-Host " Husk at følgende IKKE ligger i repoet og må håndteres separat:" -ForegroundColor Yellow
Write-Host "   - Android signing keystore (trengs ikke på Mac)" -ForegroundColor Gray
Write-Host "   - GoogleService-Info.plist (genereres av flutterfire configure)" -ForegroundColor Gray
Write-Host "   - Apple-sertifikater (håndteres av Xcode automatic signing)" -ForegroundColor Gray
Write-Host ""
