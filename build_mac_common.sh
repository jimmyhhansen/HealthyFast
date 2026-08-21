#!/bin/bash
#
# Felles byggejobb for build_prod_mac.command og build_testers_mac.command.
# Kjøres via `source` fra en av dem, med $MODE satt til "prod" eller "testers".
# Mac-versjonen av build_production.ps1 / build_testers.ps1, med iOS i tillegg.
#
# Rekkefølge:
#   1. øker byggnummeret i pubspec.yaml ÉN gang — alle plattformer i samme
#      kjøring får samme nummer, så en release henger sammen på tvers
#   2. flutter clean + pub get + analyze (analyse stopper ikke bygget)
#   3. bygger Android phone-aab, Android watch-aab og iOS .ipa
#   4. samler alt i dist/<mode>-v<byggnummer>/ og åpner mappa i Finder
#
# Hele loggen havner i build_logs/. Vinduet lukker seg aldri av seg selv —
# heller ikke når bygget feiler, så feilmeldingen rekker å bli lest.
#
# Miljøvariabler:
#   SKIP_ANDROID=1   hopp over begge Android-bygg
#   SKIP_IOS=1       hopp over iOS-bygget
#   NO_BUMP=1        bygg på nåværende byggnummer uten å øke det
#                    (for å bygge om etter et bygg som feilte halvveis)

set -o pipefail

ROOT="$PWD"
STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/build_logs"
LOG="$ROOT/build_logs/build_${MODE}_${STAMP}.log"
exec > >(tee "$LOG") 2>&1

OK=0
STATUS_MSG=""
SEMVER=""
NEW_BUILD=""
DIST=""

fail() {
  STATUS_MSG="$1"
  exit 1
}

finish() {
  echo
  if [[ "$OK" == "1" ]]; then
    echo "=============================================================="
    echo " FERDIG — versjon ${SEMVER}+${NEW_BUILD}  (${MODE})"
    echo " Filene ligger i: ${DIST#$ROOT/}"
    if [[ "$MODE" == "testers" ]]; then
      echo
      echo " OBS: dette er et TESTERBYGG. Betalingsmuren kan omgås med"
      echo " knappen nederst på betalingsskjermen. Ikke last disse filene"
      echo " opp til produksjonssporet i Play eller til App Review."
    fi
    echo "=============================================================="
  else
    echo "=============================================================="
    echo " BYGGET STOPPET: ${STATUS_MSG:-ukjent feil}"
    echo "=============================================================="
  fi
  echo "Full logg: ${LOG#$ROOT/}"
  echo
  read -r -p "Trykk Enter for å lukke vinduet... "
}
trap finish EXIT

step() {
  local label="$1"
  shift
  echo
  echo "── $label ──────────────────────────────────────────"
  "$@" || fail "$label feilet. Se loggen over."
}

echo "=============================================================="
echo " HealthyFast — byggejobb (${MODE})"
echo " Prosjektmappe: $ROOT"
echo " Logg:          ${LOG#$ROOT/}"
echo "=============================================================="

# ── Forutsetninger ──────────────────────────────────────────────────
command -v flutter >/dev/null 2>&1 || fail "Fant ikke 'flutter' i PATH."

# Uten android/key.properties faller app/build.gradle.kts tilbake til
# DEBUG-signering for release-bygg. Det feiler ikke — du får en .aab som
# ser helt riktig ut og blir avvist av Play Console fordi opplastingsnøkkelen
# ikke stemmer. Stopp her i stedet for å bruke ti minutter på et ubrukelig bygg.
if [[ -z "$SKIP_ANDROID" && ! -f "$ROOT/android/key.properties" ]]; then
  echo
  echo "android/key.properties mangler."
  echo
  echo "  Release-bygget ville blitt signert med DEBUG-nøkkelen, og Play"
  echo "  avviser en slik .aab. Kopier keystore-fila (.jks) og key.properties"
  echo "  fra maskinen som publiserer til Play — de er gitignorert med vilje"
  echo "  og finnes ikke i repoet."
  echo
  echo "  Vil du bare bygge iOS herfra, kjør skriptet slik:"
  echo "      SKIP_ANDROID=1 ./$(basename "${BASH_SOURCE[1]}")"
  fail "Mangler Android-signeringsnøkkel."
fi

if [[ -z "$SKIP_IOS" ]]; then
  command -v xcodebuild >/dev/null 2>&1 || fail "Fant ikke 'xcodebuild'. Sett SKIP_IOS=1 for å bygge kun Android."
fi

# ── 1. Byggnummer ───────────────────────────────────────────────────
VERSION_LINE="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' "$ROOT/pubspec.yaml" | head -1)"
[[ -n "$VERSION_LINE" ]] || fail "Fant ikke 'version: x.y.z+n' i pubspec.yaml."

RAW="${VERSION_LINE#version:}"
RAW="${RAW// /}"
SEMVER="${RAW%%+*}"
OLD_BUILD="${RAW##*+}"

if [[ -n "$NO_BUMP" ]]; then
  NEW_BUILD="$OLD_BUILD"
  echo
  echo "Byggnummer: beholder $NEW_BUILD (NO_BUMP=1)."
else
  NEW_BUILD=$((OLD_BUILD + 1))
  # awk + temp-fil framfor `sed -i`: in-place-flagget har ulik syntaks på
  # macOS og GNU, og en tempfil kan uansett ikke etterlate pubspec.yaml
  # halvskrevet hvis noe ryker midtveis.
  awk -v ny="version: ${SEMVER}+${NEW_BUILD}" '
    !gjort && /^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[ \t]*$/ {
      print ny; gjort = 1; next
    }
    { print }
  ' "$ROOT/pubspec.yaml" > "$ROOT/pubspec.yaml.tmp" \
    || fail "Klarte ikke lese pubspec.yaml."
  mv "$ROOT/pubspec.yaml.tmp" "$ROOT/pubspec.yaml"
  grep -q "^version: ${SEMVER}+${NEW_BUILD}\$" "$ROOT/pubspec.yaml" \
    || fail "Klarte ikke skrive nytt byggnummer til pubspec.yaml."
  echo
  echo "Byggnummer: $OLD_BUILD -> $NEW_BUILD   (versjon ${SEMVER}+${NEW_BUILD})"
fi

if [[ "$MODE" == "prod" ]]; then
  echo "PRODUKSJONSBYGG — betalingsmuren er hard, ingen tester-bypass."
  DEFINES=()
  SUFFIX=""
else
  echo "TESTERBYGG — TESTER_BUILD=true, bypass-knapp synlig på betalingsskjermen."
  DEFINES=(--dart-define=TESTER_BUILD=true)
  SUFFIX="-testers"
fi

# ── 2. Rydd og hent pakker ──────────────────────────────────────────
step "flutter clean" flutter clean
step "flutter pub get" flutter pub get

echo
echo "── Dart-analyse (informativ) ───────────────────────"
flutter analyze || {
  echo
  echo "  Analysen ga advarsler eller feil — se over. Fortsetter uansett;"
  echo "  ekte kompileringsfeil stopper byggene under."
}

# ── 3. Bygg ─────────────────────────────────────────────────────────
if [[ -z "$SKIP_ANDROID" ]]; then
  step "Android · phone (.aab)" \
    flutter build appbundle --flavor phone --release "${DEFINES[@]}"
  step "Android · watch (.aab)" \
    flutter build appbundle --flavor watch --release "${DEFINES[@]}"
else
  echo
  echo "Hopper over Android (SKIP_ANDROID=1)."
fi

if [[ -z "$SKIP_IOS" ]]; then
  step "iOS (.ipa)" flutter build ipa --release "${DEFINES[@]}"
else
  echo
  echo "Hopper over iOS (SKIP_IOS=1)."
fi

# ── 4. Samle filene ─────────────────────────────────────────────────
# Egen dist/-mappe på rota, ikke inne i build/: neste kjørings
# `flutter clean` sletter hele build/, og da ville forrige release
# forsvunnet under føttene på deg.
DIST="$ROOT/dist/${MODE}-v${NEW_BUILD}"
mkdir -p "$DIST"

collect() {
  local src="$1" dst="$2"
  if [[ -f "$src" ]]; then
    cp "$src" "$DIST/$dst"
    echo "  ✓ $dst"
  else
    echo "  ✗ fant ikke $src"
  fi
}

echo
echo "── Samler filer i ${DIST#$ROOT/} ───────────────────"

if [[ -z "$SKIP_ANDROID" ]]; then
  collect "$ROOT/build/app/outputs/bundle/phoneRelease/app-phone-release.aab" \
          "HealthyFast-phone${SUFFIX}-v${NEW_BUILD}.aab"
  collect "$ROOT/build/app/outputs/bundle/watchRelease/app-watch-release.aab" \
          "HealthyFast-watch${SUFFIX}-v${NEW_BUILD}.aab"
fi

if [[ -z "$SKIP_IOS" ]]; then
  # Flutter navngir .ipa-en etter Xcode-schemet, så plukk det som ligger der
  # framfor å gjette på filnavnet.
  IPA="$(ls -t "$ROOT"/build/ios/ipa/*.ipa 2>/dev/null | head -1)"
  if [[ -n "$IPA" ]]; then
    collect "$IPA" "HealthyFast-ios${SUFFIX}-v${NEW_BUILD}.ipa"
  else
    echo "  ✗ fant ingen .ipa i build/ios/ipa/"
  fi
fi

OK=1
open "$DIST"
