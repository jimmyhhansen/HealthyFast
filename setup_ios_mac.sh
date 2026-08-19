#!/usr/bin/env bash
#
# setup_ios_mac.sh — Bootstrapper iOS-plattformen for HealthyFast på Mac.
#
# HealthyFast har aldri hatt en ios/-mappe. Dette scriptet genererer den,
# setter bundle ID og deployment target, legger inn alle Info.plist-nøklene
# appen trenger, og kjører pod install.
#
# Scriptet er idempotent: det kan kjøres flere ganger. Eksisterende ios/-mappe
# blir ikke overskrevet (bruk --recreate hvis du vil starte på nytt).
#
# Bruk:
#   chmod +x setup_ios_mac.sh
#   ./setup_ios_mac.sh
#   ./setup_ios_mac.sh --recreate     # slett og regenerer ios/
#   ./setup_ios_mac.sh --check-only   # bare verifiser verktøykjeden
#
set -uo pipefail

BUNDLE_ID="co.healthyfast"          # samme som Android applicationId
DISPLAY_NAME="HealthyFast"
DEPLOYMENT_TARGET="15.0"            # Firebase iOS SDK 12.x krever iOS 15+
FIREBASE_PROJECT="healthyfast-f1f5a"

RECREATE=0
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --recreate)   RECREATE=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Ukjent flagg: $arg" >&2; exit 1 ;;
  esac
done

# --- Utskrift ---------------------------------------------------------------
BOLD=$(tput bold 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true); GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)

step() { echo ""; echo "${CYAN}${BOLD}=== $*${RESET}"; }
ok()   { echo "  ${GREEN}[OK]${RESET}   $*"; }
warn() { echo "  ${YELLOW}[!]${RESET}    $*"; }
err()  { echo "  ${RED}[FEIL]${RESET} $*" >&2; }
info() { echo "         $*"; }
die()  { err "$*"; exit 1; }

FAILED=0

cd "$(dirname "$0")" || die "Kunne ikke bytte til script-mappa"

# --- 0. Er vi i riktig prosjekt? -------------------------------------------

step "Verifiserer prosjekt"
[[ -f pubspec.yaml ]] || die "Fant ikke pubspec.yaml. Kjør scriptet fra rota av HealthyFast."
grep -q '^name: healthyfast' pubspec.yaml || die "pubspec.yaml er ikke HealthyFast."
ok "HealthyFast funnet i $(pwd)"

[[ "$(uname)" == "Darwin" ]] || die "Dette scriptet må kjøres på macOS."

# --- 1. Verktøykjede --------------------------------------------------------

step "Sjekker verktøykjeden"

need() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1 → $(command -v "$1")"
  else
    err "$1 mangler. $2"
    FAILED=1
  fi
}

need flutter "Installer: https://docs.flutter.dev/get-started/install/macos"
need xcodebuild "Installer Xcode fra App Store, og kjør: sudo xcode-select -s /Applications/Xcode.app"
need pod "Installer CocoaPods: sudo gem install cocoapods   (eller: brew install cocoapods)"
need git "xcode-select --install"

if command -v xcodebuild >/dev/null 2>&1; then
  if ! xcodebuild -version >/dev/null 2>&1; then
    err "xcodebuild feilet. Kjør: sudo xcodebuild -license accept"
    FAILED=1
  else
    ok "Xcode $(xcodebuild -version | head -1 | awk '{print $2}')"
  fi
fi

if command -v flutter >/dev/null 2>&1; then
  ok "Flutter $(flutter --version 2>/dev/null | head -1 | awk '{print $2}')"
fi

# FlutterFire CLI trengs for Firebase-oppsettet senere.
if command -v flutterfire >/dev/null 2>&1; then
  ok "flutterfire → $(command -v flutterfire)"
else
  warn "flutterfire mangler. Installer med:"
  info "dart pub global activate flutterfire_cli"
  info "og legg til i PATH:  export PATH=\"\$PATH:\$HOME/.pub-cache/bin\""
fi

[[ $FAILED -eq 0 ]] || die "Fiks manglene over og kjør på nytt."

if [[ $CHECK_ONLY -eq 1 ]]; then
  step "--check-only satt — stopper her."
  exit 0
fi

# --- 2. Dart-avhengigheter --------------------------------------------------

step "Henter Dart-pakker"
flutter pub get || die "flutter pub get feilet."
ok "pub get ferdig"

# --- 3. Generer ios/ --------------------------------------------------------

step "iOS-plattform"

if [[ -d ios && $RECREATE -eq 1 ]]; then
  BACKUP="ios.backup.$(date +%Y%m%d-%H%M%S)"
  warn "--recreate satt. Flytter eksisterende ios/ til $BACKUP"
  mv ios "$BACKUP"
fi

if [[ -d ios ]]; then
  ok "ios/ finnes allerede — hopper over generering."
else
  info "Genererer ios/ (rører ikke lib/ eller android/)…"
  flutter create --platforms=ios --project-name healthyfast --org com.northernappdev . \
    || die "flutter create feilet."
  ok "ios/ generert"
fi

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
PLIST="ios/Runner/Info.plist"
[[ -f "$PBXPROJ" ]] || die "Fant ikke $PBXPROJ"
[[ -f "$PLIST" ]]   || die "Fant ikke $PLIST"

# --- 4. Bundle ID + deployment target --------------------------------------

step "Setter bundle ID og deployment target"

if grep -q "PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;" "$PBXPROJ"; then
  ok "Bundle ID er allerede $BUNDLE_ID"
else
  # RunnerTests beholder sitt eget suffiks.
  /usr/bin/sed -i '' \
    -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.northernappdev\.healthyfast\.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}.RunnerTests;/g" \
    -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.northernappdev\.healthyfast;/PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID};/g" \
    "$PBXPROJ"
  ok "Bundle ID satt til $BUNDLE_ID"
fi

CURRENT_TARGET=$(grep -m1 'IPHONEOS_DEPLOYMENT_TARGET' "$PBXPROJ" | sed 's/.*= *//; s/;//' | tr -d ' ')
if [[ "$CURRENT_TARGET" == "$DEPLOYMENT_TARGET" ]]; then
  ok "Deployment target er allerede $DEPLOYMENT_TARGET"
else
  /usr/bin/sed -i '' "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = ${DEPLOYMENT_TARGET};/g" "$PBXPROJ"
  ok "Deployment target $CURRENT_TARGET → $DEPLOYMENT_TARGET"
fi

# --- 5. Info.plist ----------------------------------------------------------

step "Skriver Info.plist-nøkler"

PB=/usr/libexec/PlistBuddy

setstr() {  # setstr <nøkkel> <verdi>
  local key="$1" val="$2"
  if $PB -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    $PB -c "Set :$key $val" "$PLIST"
  else
    $PB -c "Add :$key string $val" "$PLIST"
  fi
  info "$key"
}

setbool() {
  local key="$1" val="$2"
  if $PB -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    $PB -c "Set :$key $val" "$PLIST"
  else
    $PB -c "Add :$key bool $val" "$PLIST"
  fi
  info "$key = $val"
}

setstr "CFBundleDisplayName" "$DISPLAY_NAME"
setstr "CFBundleName" "$DISPLAY_NAME"

# HealthKit — health-pakken leser/skriver NUTRITION, WEIGHT, WORKOUT, STEPS,
# SLEEP_SESSION (se lib/services/health_sync_service.dart).
setstr "NSHealthShareUsageDescription" \
  "HealthyFast reads your steps, workouts, weight and sleep so your fasting and calorie stats reflect your whole day."
setstr "NSHealthUpdateUsageDescription" \
  "HealthyFast writes the meals and workouts you log to Apple Health so your other apps stay in sync."

# speech_to_text — diktering av måltider
setstr "NSMicrophoneUsageDescription" \
  "HealthyFast uses the microphone so you can log a meal by speaking instead of typing."
setstr "NSSpeechRecognitionUsageDescription" \
  "HealthyFast transcribes your voice to turn a spoken meal description into a calorie estimate."

# image_picker — foto av måltid
setstr "NSCameraUsageDescription" \
  "HealthyFast uses the camera so you can photograph a meal and get a calorie estimate."
setstr "NSPhotoLibraryUsageDescription" \
  "HealthyFast lets you pick a meal photo from your library to get a calorie estimate."

# Slipper å svare på eksportspørsmålet ved hver TestFlight-opplasting.
setbool "ITSAppUsesNonExemptEncryption" "false"

ok "Info.plist oppdatert"

# --- 6. HealthKit-entitlement ----------------------------------------------

step "HealthKit-entitlement"

ENT="ios/Runner/Runner.entitlements"
if [[ -f "$ENT" ]] && grep -q 'com.apple.developer.healthkit' "$ENT"; then
  ok "Runner.entitlements har allerede HealthKit"
else
  cat > "$ENT" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
</dict>
</plist>
PLIST_EOF
  ok "Opprettet $ENT"
fi

if grep -q 'CODE_SIGN_ENTITLEMENTS' "$PBXPROJ"; then
  ok "CODE_SIGN_ENTITLEMENTS er allerede satt i prosjektfila"
else
  warn "Entitlements-fila er laget, men IKKE koblet til Xcode-targetet."
  info "Gjør dette i Xcode (kan ikke gjøres trygt med sed):"
  info "  open ios/Runner.xcworkspace"
  info "  Runner → Signing & Capabilities → + Capability → HealthKit"
  info "  Legg også til: In-App Purchase, og Sign in with Apple (se checklist)"
fi

# --- 7. CocoaPods -----------------------------------------------------------

step "CocoaPods"

# Podfile-en Flutter genererer har platform-linja kommentert ut.
PODFILE="ios/Podfile"
if [[ -f "$PODFILE" ]]; then
  if grep -qE "^platform :ios, '${DEPLOYMENT_TARGET}'" "$PODFILE"; then
    ok "Podfile står på iOS $DEPLOYMENT_TARGET"
  else
    /usr/bin/sed -i '' "s/^# *platform :ios.*/platform :ios, '${DEPLOYMENT_TARGET}'/" "$PODFILE"
    /usr/bin/sed -i '' "s/^platform :ios, '[0-9.]*'/platform :ios, '${DEPLOYMENT_TARGET}'/" "$PODFILE"
    ok "Podfile satt til iOS $DEPLOYMENT_TARGET"
  fi
fi

info "Kjører pod install (kan ta noen minutter første gang)…"
( cd ios && pod install --repo-update )
if [[ $? -ne 0 ]]; then
  warn "pod install feilet."
  info "Vanlige fikser:"
  info "  cd ios && pod repo update && pod install"
  info "  På Apple Silicon uten Rosetta: sudo gem install ffi && arch -x86_64 pod install"
  info "  Hvis en pakke krever høyere iOS-versjon: øk DEPLOYMENT_TARGET øverst i dette scriptet"
else
  ok "Pods installert"
fi

# --- 8. Firebase -----------------------------------------------------------

step "Firebase"

if [[ -f ios/Runner/GoogleService-Info.plist ]]; then
  ok "GoogleService-Info.plist finnes"
else
  warn "GoogleService-Info.plist mangler — Firebase (cloud sync + Cloud AI) vil ikke virke."
  info "Fiks:"
  info "  flutterfire configure --project=${FIREBASE_PROJECT} --platforms=ios --ios-bundle-id=${BUNDLE_ID}"
  info ""
  info "Dette registrerer iOS-appen i Firebase, laster ned plist-en OG oppdaterer"
  info "lib/firebase_options.dart (som i dag kaster UnsupportedError for iOS)."
fi

if grep -q "have not been configured for ios" lib/firebase_options.dart 2>/dev/null; then
  warn "lib/firebase_options.dart mangler fortsatt iOS-konfigurasjon."
fi

# --- 9. Prøvebygg -----------------------------------------------------------

step "Prøvebygg (uten signering)"

info "flutter build ios --no-codesign --debug"
if flutter build ios --no-codesign --debug 2>&1 | tail -30; then
  ok "Bygget kompilerte."
else
  warn "Bygget feilet — se loggen over."
  info "Dette er forventet før HealthKit-capability og Firebase er på plass."
fi

# --- 10. Oppsummering -------------------------------------------------------

step "Status"

check() { if eval "$2"; then ok "$1"; else warn "$1 — GJENSTÅR"; fi; }

check "ios/-mappe generert"            "[[ -d ios ]]"
check "Bundle ID = $BUNDLE_ID"         "grep -q 'PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID};' '$PBXPROJ'"
check "Info.plist-nøkler"              "$PB -c 'Print :NSHealthShareUsageDescription' '$PLIST' >/dev/null 2>&1"
check "HealthKit-entitlement fil"      "[[ -f '$ENT' ]]"
check "Pods installert"                "[[ -d ios/Pods ]]"
check "GoogleService-Info.plist"       "[[ -f ios/Runner/GoogleService-Info.plist ]]"

echo ""
echo "${BOLD}Neste steg — se IOS_LAUNCH_CHECKLIST.md${RESET}"
echo ""
echo "  Kort versjon:"
echo "    1. flutterfire configure --project=${FIREBASE_PROJECT} --platforms=ios --ios-bundle-id=${BUNDLE_ID}"
echo "    2. open ios/Runner.xcworkspace → Signing & Capabilities:"
echo "       velg team, legg til HealthKit + In-App Purchase + Sign in with Apple"
echo "    3. Fiks koden som er Android-only (notifikasjoner, MethodChannels) — checklist seksjon 4"
echo "    4. flutter run -d <iphone>"
echo ""
echo "  Åpne Claude Code i denne mappa og si:"
echo "    \"Les CLAUDE_MAC_HANDOFF.md og fortsett fra der jeg slapp.\""
echo ""
