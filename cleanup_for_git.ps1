<#
.SYNOPSIS
    Rydder HealthyFast-repoet slik at det kan pushes til GitHub og klones på Mac.

.DESCRIPTION
    Repoet inneholder i dag ~12 600 filer fra functions/node_modules som ligger
    sporet i git fordi .gitignore mangler node_modules-regler. Dette scriptet:

      1. Utvider .gitignore med reglene som mangler (node_modules, ios/Pods,
         build-artefakter, .env, keystores).
      2. Untracker filer som ikke skal ligge i git (git rm --cached — filene
         blir liggende urørt på disk).
      3. Flagger store filer og filer som ser ut som hemmeligheter.
      4. Rapporterer størrelsen på repoet før/etter.

    Filer slettes ALDRI fra disk. Kjør med -DryRun først for å se hva som skjer.

.PARAMETER DryRun
    Vis hva som ville blitt gjort, uten å endre noe.

.PARAMETER NoCommit
    Utfør endringene, men ikke lag commit. Standard er å committe.

.EXAMPLE
    .\cleanup_for_git.ps1 -DryRun
    .\cleanup_for_git.ps1
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoCommit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell 7.4+ gjør ellers exit-kode != 0 fra git til en terminerende feil.
# Vi sjekker $LASTEXITCODE selv der det er relevant. (Ukjent variabel i 5.1 —
# assignment er harmløs der.)
$PSNativeCommandUseErrorActionPreference = $false

# Testet på Windows PowerShell 5.1 og PowerShell 7.x.
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "Krever PowerShell 5.1 eller nyere. Du kjører $($PSVersionTable.PSVersion)."
}

# git skriver rutinemessig statustekst til stderr (ikke bare feil). I Windows
# PowerShell 5.1 pakker $ErrorActionPreference='Stop' DENNE teksten inn som en
# terminerende feil, selv om kommandoen lyktes. Alle git-kall går derfor via
# Invoke-Git, som midlertidig slår av 'Stop' og selv sjekker $LASTEXITCODE.
function Invoke-Git {
    # Bevisst UTEN [Parameter(ValueFromRemainingArguments)]: det gjør
    # funksjonen "advanced" og gir den skjulte fellesparametre som -Debug —
    # og siden -D er en entydig forkortelse av -Debug, ville PowerShell da
    # stille og rolig SPIST "-D" (f.eks. i 'git branch -D gammelgren') før
    # git noensinne fikk se det. Den automatiske $args-variabelen unngår
    # parameterbinding helt og sender alt videre uendret.
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

# --- Hjelpefunksjoner -------------------------------------------------------

function Write-Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  [!]    $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Would($msg){ Write-Host "  [DRY]  $msg" -ForegroundColor DarkYellow }

function Get-DirSizeMB($path) {
    if (-not (Test-Path $path)) { return 0 }
    $bytes = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { return 0 }
    return [math]::Round($bytes / 1MB, 1)
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

# --- 0. Sanity: står vi i riktig repo? --------------------------------------

Set-Location -LiteralPath $PSScriptRoot

Write-Step "Sjekker at vi står i HealthyFast-repoet"

if (-not (Test-Path '.\pubspec.yaml')) {
    throw "Fant ikke pubspec.yaml i $PSScriptRoot. Kjør scriptet fra rota av HealthyFast-prosjektet."
}
$pubspecName = (Select-String -Path '.\pubspec.yaml' -Pattern '^name:\s*(\S+)' | Select-Object -First 1)
if (-not $pubspecName -or $pubspecName.Matches[0].Groups[1].Value -ne 'healthyfast') {
    throw "pubspec.yaml sier ikke 'name: healthyfast'. Avbryter for sikkerhets skyld."
}
if (-not (Test-Path '.\.git')) {
    throw "Fant ingen .git-mappe. Kjør 'git init' først, eller kjør setup_github.ps1."
}
Assert-NoGitLock $PSScriptRoot
Write-Ok "HealthyFast-repo funnet i $PSScriptRoot"

if ($DryRun) { Write-Warn2 "DRY RUN — ingenting blir endret." }

# --- 1. Status før ----------------------------------------------------------

Write-Step "Status før rydding"

$trackedBefore = @((Invoke-Git ls-files).Output).Count
$gitSizeBefore = Get-DirSizeMB '.\.git'
Write-Info "Sporede filer i git : $trackedBefore"
Write-Info ".git-mappe          : $gitSizeBefore MB"

# --- 2. Utvid .gitignore ----------------------------------------------------

Write-Step "Oppdaterer .gitignore"

# Regler som MÅ inn. ios/Flutter/* og Podfile.lock er med fordi Mac-en kommer
# til å generere dem, og vi vil ikke ha Pods-kildekode (hundretusenvis av filer)
# i repoet.
$requiredRules = @(
    '# --- Node (Cloud Functions) ---'
    'node_modules/'
    'functions/node_modules/'
    'functions/lib/'
    ''
    '# --- iOS (genereres på Mac) ---'
    'ios/Pods/'
    'ios/.symlinks/'
    'ios/Flutter/Flutter.framework'
    'ios/Flutter/Flutter.podspec'
    'ios/Flutter/App.framework'
    'ios/Flutter/ephemeral/'
    'ios/Runner/GeneratedPluginRegistrant.*'
    '**/xcuserdata/'
    '*.xcworkspace/xcuserdata/'
    ''
    '# --- Byggeartefakter / utgivelser ---'
    'build/'
    'release/'
    'build_logs/'
    '*.aab'
    '*.apk'
    '*.ipa'
    '*.app.dSYM.zip'
    ''
    '# --- Hemmeligheter (skal ALDRI i git, heller ikke privat repo) ---'
    '*.jks'
    '*.keystore'
    'key.properties'
    '.env'
    '.env.*'
    '*-service-account*.json'
    'ios/Runner/GoogleService-Info.plist.bak'
    ''
    '# --- Diverse ---'
    '.gitignore.bak'
    'ios.backup.*/'
)

$gitignorePath = '.\.gitignore'
$existing = if (Test-Path $gitignorePath) { Get-Content $gitignorePath } else { @() }

# Bare legg til regler som ikke allerede finnes (ignorer kommentarer/tomme).
$existingSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]($existing | ForEach-Object { $_.Trim() }),
    [System.StringComparer]::OrdinalIgnoreCase
)

$toAdd = @()
foreach ($rule in $requiredRules) {
    $t = $rule.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { $toAdd += $rule; continue }
    if (-not $existingSet.Contains($t)) { $toAdd += $rule }
}

# Fjern header-blokker der alle reglene under allerede fantes.
$meaningful = @($toAdd | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') })

if ($meaningful.Count -eq 0) {
    Write-Ok ".gitignore er allerede komplett — ingen nye regler."
} else {
    Write-Info "Legger til $($meaningful.Count) nye regler:"
    $meaningful | ForEach-Object { Write-Info "    $_" }
    if (-not $DryRun) {
        Copy-Item $gitignorePath "$gitignorePath.bak" -Force -ErrorAction Stop
        $block = @('', '# ============================================================', "# Lagt til av cleanup_for_git.ps1 $(Get-Date -Format 'yyyy-MM-dd')", '# ============================================================') + $toAdd
        # Add-Content -Encoding UTF8 skriver BOM i Windows PowerShell 5.1.
        # .NET-veien gir UTF-8 uten BOM på alle versjoner.
        $full = (Resolve-Path -LiteralPath $gitignorePath).ProviderPath
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($full, ($block -join "`r`n") + "`r`n", $utf8NoBom)
        Write-Ok "Skrev til .gitignore (backup: .gitignore.bak)"
    } else {
        Write-Would "Ville skrevet reglene til .gitignore"
    }
}

# --- 3. Untrack filer som ikke skal ligge i git -----------------------------

Write-Step "Untracker filer som ikke hører hjemme i git"

# Mønstre vi vil ha ut av indeksen. git ls-files brukes for å telle først,
# slik at vi bare kjører 'git rm' der det faktisk er noe å fjerne.
$untrackPatterns = @(
    'functions/node_modules'
    'node_modules'
    'build'
    'release'
    'build_logs'
    '.dart_tool'
    '.flutter-plugins-dependencies'
    'ios/Pods'
)

$totalUntracked = 0
$untrackFailed = $false
foreach ($pattern in $untrackPatterns) {
    $files = @((Invoke-Git ls-files -- $pattern).Output)
    if ($files.Count -eq 0) { continue }
    Write-Info "$pattern → $($files.Count) filer"
    if (-not $DryRun) {
        # --cached = fjern fra git, behold på disk. -q = stille.
        $r = Invoke-Git rm -r --cached -q --ignore-unmatch -- $pattern
        if ($r.ExitCode -ne 0) {
            $r.Output | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkRed }
            Write-Warn2 "git rm feilet for '$pattern' (se feilmelding over) — IKKE untracket."
            $untrackFailed = $true
            continue
        }
    } else {
        Write-Would "git rm -r --cached -- $pattern"
    }
    $totalUntracked += $files.Count
}

if ($untrackFailed) {
    throw "En eller flere 'git rm' feilet (se over — ofte '.git/index.lock'). Ingenting ble committet. Fiks problemet og kjor scriptet på nytt."
}

if ($totalUntracked -eq 0) {
    Write-Ok "Ingenting å untracke — indeksen er allerede ren."
} else {
    Write-Ok "$totalUntracked filer fjernet fra git-indeksen (fortsatt på disk)."
}

# --- 4. Sikkerhetssjekk: hemmeligheter og store filer -----------------------

Write-Step "Sikkerhetssjekk av det som fortsatt er sporet"

$stillTracked = @((Invoke-Git ls-files).Output)

# 4a. Filer som kan inneholde hemmeligheter eller privat data.
$secretPatterns = @(
    @{ Pattern = '\.jks$';                 Why = 'Android signing keystore' }
    @{ Pattern = '\.keystore$';            Why = 'Android signing keystore' }
    @{ Pattern = 'key\.properties$';       Why = 'keystore-passord' }
    @{ Pattern = '\.env';                  Why = 'miljøvariabler' }
    @{ Pattern = 'service-account.*\.json$'; Why = 'Firebase admin-nøkkel' }
    @{ Pattern = 'fakturagrunnlag';        Why = 'fakturadata — hører neppe hjemme i kodebasen' }
    @{ Pattern = '\.p8$|\.p12$|\.mobileprovision$'; Why = 'Apple-signeringsmateriale' }
)

$flagged = @()
foreach ($sp in $secretPatterns) {
    $hits = @($stillTracked | Where-Object { $_ -match $sp.Pattern })
    foreach ($h in $hits) { $flagged += [pscustomobject]@{ File = $h; Why = $sp.Why } }
}

if ($flagged.Count -eq 0) {
    Write-Ok "Ingen åpenbare hemmeligheter sporet."
} else {
    Write-Warn2 "Følgende sporede filer bør du vurdere å fjerne manuelt:"
    $flagged | ForEach-Object { Write-Host "         $($_.File)  ← $($_.Why)" -ForegroundColor Yellow }
    Write-Info "Fjern med:  git rm --cached `"<fil>`"   (og legg mønsteret i .gitignore)"
}

# 4b. google-services.json er OK i et PRIVAT repo — Mac-en trenger den.
if ($stillTracked -contains 'android/app/google-services.json') {
    Write-Info "android/app/google-services.json er sporet — det er riktig for et PRIVAT repo (Mac-en trenger den). Ikke gjør repoet offentlig."
}

# 4c. Store filer (GitHub advarer >50 MB, avviser >100 MB).
Write-Step "Ser etter store filer"
$big = @()
foreach ($f in $stillTracked) {
    if (Test-Path -LiteralPath $f) {
        $len = (Get-Item -LiteralPath $f -Force).Length
        if ($len -gt 20MB) { $big += [pscustomobject]@{ File = $f; MB = [math]::Round($len/1MB,1) } }
    }
}
if ($big.Count -eq 0) {
    Write-Ok "Ingen sporede filer over 20 MB."
} else {
    $big | Sort-Object MB -Descending | ForEach-Object {
        $color = if ($_.MB -gt 100) { 'Red' } elseif ($_.MB -gt 50) { 'Yellow' } else { 'Gray' }
        Write-Host "         $($_.MB) MB  $($_.File)" -ForegroundColor $color
    }
    Write-Warn2 "GitHub advarer over 50 MB og AVVISER over 100 MB per fil."
}

# --- 5. Commit --------------------------------------------------------------

Write-Step "Commit"

if ($DryRun) {
    Write-Would "Ville committet ryddingen."
} elseif ($NoCommit) {
    Write-Info "-NoCommit satt. Kjør selv:  git commit -m `"Rydd repo for iOS-overføring`""
} elseif (@((Invoke-Git diff --cached --name-only).Output).Count -eq 0 -and $meaningful.Count -eq 0 -and $totalUntracked -eq 0) {
    Write-Ok "Ingenting å committe."
} else {
    $addR = Invoke-Git add .gitignore
    if ($addR.ExitCode -ne 0) {
        $addR.Output | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkRed }
        throw "git add .gitignore feilet."
    }
    $commitR = Invoke-Git commit -q -m "Rydd repo for iOS-overforing: ignorer node_modules og byggeartefakter"
    if ($commitR.ExitCode -ne 0) {
        $commitR.Output | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkRed }
        throw "git commit feilet."
    }
    Write-Ok "Commit laget."
}

# --- 6. Status etter --------------------------------------------------------

Write-Step "Resultat"

$trackedAfter = @((Invoke-Git ls-files).Output).Count
Write-Info "Sporede filer  : $trackedBefore  →  $trackedAfter"
Write-Info ".git-mappe     : $gitSizeBefore MB (krymper ikke automatisk — historikken beholdes)"
Write-Info ""
Write-Info "Merk: .git krymper ikke av dette, fordi node_modules fortsatt ligger i"
Write-Info "historikken. Med bare 1 commit er det enkleste å starte historikken på"
Write-Info "nytt hvis .git er stor. setup_github.ps1 -FreshHistory gjør det for deg."
Write-Host ""
Write-Host "Neste steg:  .\setup_github.ps1 -RepoName healthyfast" -ForegroundColor Cyan
Write-Host ""
