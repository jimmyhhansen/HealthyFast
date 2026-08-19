# Handoff til Claude på Mac

**Les denne først.** Den er skrevet for en Claude-sesjon som starter kald på Jimmys
Mac og skal fortsette iOS-utgivelsen av HealthyFast. Alt her er utledet fra
kodebasen 2026-08-19, før noe iOS-arbeid var påbegynt.

---

## Åpningsprompt til Claude

> Les `CLAUDE_MAC_HANDOFF.md` og `IOS_LAUNCH_CHECKLIST.md`. Jeg har kjørt
> `setup_ios_mac.sh`. Fortsett fra seksjon 4 i checklisten — kodeendringene som
> gjør appen faktisk funksjonell på iOS.

---

## 1. Hva er HealthyFast

Flutter-app for periodisk faste, kaloritelling og styrketrening. Prosjektmål (fra
prosjektinstruksjonene): bli den ledende appen i sin kategori og tjene penger.
Android-versjonen er live; iOS er ikke påbegynt.

- Versjon `2.0.0+226`
- Android applicationId `co.healthyfast`, namespace `com.northernappdev.healthyfast`
- Foreslått iOS bundle ID: `co.healthyfast`
- Firebase-prosjekt `healthyfast-f1f5a`
- Premium via abonnement: `healthyfast_yearly` (200 kr/år), `healthyfast_monthly` (25 kr/mnd)

---

## 2. Arkitektur i korte trekk

```
lib/
  main.dart                  Hive-init, watch-deteksjon, Firebase best-effort
  firebase_options.dart      ⚠️ kaster UnsupportedError for iOS til flutterfire kjøres
  models/                    fitness_goal.dart inneholder kCapabilities (se under)
  providers/                 provider-basert state; purchase_provider.dart = IAP
  screens/                   UI, inkl. watch_screen.dart (Wear OS)
  services/                  health_sync, notification, cloud_backup, meal_estimator,
                             training_ai, watch_sync, complication, ongoing_activity
  theme/  widgets/
android/app/src/main/kotlin/com/northernappdev/healthyfast/
                             10 Kotlin-filer: MethodChannels, tiles, complications,
                             foreground services, Gemini Nano-integrasjon
functions/                   Firebase Cloud Functions (Cloud AI-fallback)
```

Lagring: **Hive** lokalt, **Firestore** som premium-speil. Ingen server-of-record —
Hive er sannheten, Firestore er en kopi.

---

## 3. Det viktigste å forstå: hva som er Android-only

Appen kompilerer trolig på iOS, men **feiler stille** i kjernefunksjoner.
Dette er der arbeidet ligger.

### 3.1 Fire MethodChannels uten iOS-implementasjon

Alle definert i Dart, implementert kun i Kotlin (`MainActivity.kt`, `MealEstimator.kt`).
På iOS kaster de `MissingPluginException`.

| Kanal | Brukt av | Betydning på iOS |
|---|---|---|
| `healthyfast/meal` | `meal_estimator_service.dart`, `training_ai_service.dart` | 🔴 Kritisk — dette er AI-måltidsloggingen |
| `healthyfast/health` | `health_sync_service.dart` (`getDailySteps`) | 🟢 Allerede trygg — gated på linje 179, med fungerende `health`-pakke-fallback |
| `healthyfast/wear` | `complication_service.dart`, `ongoing_activity_service.dart`, `wear_install_service.dart` | ⚪ Wear OS — skal no-op'e |
| `healthyfast/nav` | `watch_screen.dart` | ⚪ Wear OS — skal no-op'e |

**Om `healthyfast/meal`:** på Android bruker appen Gemini Nano *på enheten* for
måltidsestimater. Nano finnes ikke på iOS. Alle iOS-brukere må gå via Cloud
AI-veien (Firebase Functions). Se `project_healthyfast_firebase_anonymous_auth.md`
i prosjektminnet — **anonym auth må være påslått i Firebase Console**, ellers
feiler Cloud AI. På Android gjelder det bare ikke-Nano-telefoner; på iOS gjelder
det 100 % av brukerbasen.

`screens/cloud_ai_settings_screen.dart` viser en «last ned on-device AI-modell»-rad
som er meningsløs på iOS. Skjul den bak `Platform.isAndroid`.

### 3.2 Notifikasjoner initialiseres aldri for iOS

`services/notification_service.dart:31`:

```dart
const settings = InitializationSettings(android: android);   // ingen darwin:
```

`requestPermissions()` (~linje 313) resolver kun `AndroidFlutterLocalNotificationsPlugin`
→ `null` på iOS → tillatelse spørres aldri om → ingen varsler.

Faste-milepælvarsler er en kjernefunksjon. Dette må fikses.
Merk også: iOS tillater **maks 64 planlagte lokale varsler** per app.

### 3.3 Firebase

`firebase_options.dart` har `case TargetPlatform.iOS: throw UnsupportedError(...)`.
`main.dart` fanger dette (Firebase-init er best-effort), så appen krasjer ikke —
men cloud sync, Cloud AI og Google-innlogging er døde til `flutterfire configure`
er kjørt.

### 3.4 Google Sign-In → utløser Apple-krav

`services/cloud_backup_service.dart` bruker `GoogleSignIn.instance.initialize(serverClientId:)`.
På iOS trengs også `clientId` og en `REVERSED_CLIENT_ID` URL scheme.

⚠️ **App Store-regel 4.8:** tilbyr du Google-innlogging må du også tilby
**Sign in with Apple**. Dette er ikke valgfritt og er den vanligste
avvisningsgrunnen for denne apptypen.

---

## 4. Konvensjoner i kodebasen — respekter disse

### `kCapabilities` er én kilde til sannhet

`lib/models/fitness_goal.dart` inneholder `kCapabilities`: listen over hva appen
kan, inkludert hvilke funksjoner som er premium. Både `welcome_screen.dart`,
`profile_wizard_screen.dart` (intro-modus) og `onboarding_summary_screen.dart`
rendrer fra den.

**Legger du til eller endrer en funksjon: rediger `kCapabilities`, ikke skjermteksten.**
(`paywall_screen.dart` er ennå ikke migrert til å lese fra den — den migreringen
står fortsatt åpen.)

### Watch-sesjoner er lokale til de er ferdige

Aktive treningsøkter skal aldri kringkastes midt i økta — kun ved fullføring.
Se `project_watch_session_sync_design.md` i prosjektminnet.

### Språk

Koden og commit-meldingene er på engelsk. Kommentarer er blandet norsk/engelsk.
Bruker-vendt tekst i appen er engelsk. Jimmy snakker norsk.

### Pubspec har låste versjoner med begrunnelse

Flere pakker er pinnet med kommentar om hvorfor (`package_info_plus` pga.
win32-konflikt via `device_info_plus`/`health`, `wearable_rotary` er discontinued
oppstrøms). **Ikke bump disse uten å lese kommentaren.**

---

## 5. Kjente fallgruver

- **HealthKit finnes ikke i simulatoren.** Kjernefunksjonalitet kan ikke testes
  uten fysisk iPhone.
- **`ios/Pods/` skal ikke i git.** `.gitignore` er oppdatert for dette.
- **`android/app/google-services.json` ligger sporet i git.** Repoet må være privat.
- **iOS-appikon kan ikke ha alfakanal.** `pubspec.yaml` har `flutter_launcher_icons:
  ios: false` i dag — sjekk `new icon.png` for gjennomsiktighet før du snur den til `true`.
- **Tidssone er hardkodet til `Europe/Oslo`** i `notification_service.dart:23`.
  Fungerer, men er en internasjonaliseringsbombe.
- **`wearable_rotary` og `watch_connectivity`** har ingen iOS-implementasjon.
  Hvis `pod install` eller bygget feiler, er de første mistenkt.
- **`HealthDataType.SLEEP_SESSION`** (`health_sync_service.dart:151`) er et Health
  Connect-begrep. Er den ikke støttet på iOS, feiler `requestAuthorization` for
  *hele* `_readTypes`-lista — ikke bare søvn. Verifiser tidlig.

---

## 6. Filer i repoet du bør lese

| Fil | Hva den gir deg |
|---|---|
| `IOS_LAUNCH_CHECKLIST.md` | Den operative planen — start der |
| `LAUNCH_CHECKLIST.md` | Android-utgivelsen, 0 iOS-referanser. Nyttig som mal for hva som må dekkes |
| `PROJECT_NOTES.md` | Generelle prosjektnotater |
| `CLOUD_SYNC_PLAN.md` | Hvordan Hive↔Firestore-speilingen er tenkt |
| `TRAINING_FEATURE_PLAN.md` | Styrketreningsdelen |
| `RELEASE_TEST.md` | Manuell testprotokoll — gjenbruk den for iOS |
| `PLAY_CONSOLE_WARNINGS.md` | Advarsler Google ga. Flere har App Store-paralleller |
| `WEAR_OS_LEARNINGS.md` | Wear OS-erfaringer |
| `build_all.ps1` / `build_production.ps1` / `build_testers.ps1` | Android-byggescript. iOS trenger tilsvarende senere |

Prosjektminnet (`project_memory_read`) har i tillegg:
`project_watch_session_sync_design.md`, `project_onboarding_capability_catalog.md`,
`project_healthyfast_firebase_anonymous_auth.md`.

---

## 7. Arbeidsrekkefølge jeg vil anbefale

1. `./setup_ios_mac.sh` — generer `ios/`, sett bundle ID, Info.plist, pods
2. `flutterfire configure` — fiks `firebase_options.dart` og hent `GoogleService-Info.plist`
3. Xcode: velg team, legg til HealthKit + In-App Purchase + Sign in with Apple
4. **Fiks notifikasjonstjenesten** (seksjon 4.1 i checklisten) — størst brukerverdi
5. **Gate alle fire MethodChannels** slik at ingenting kaster på iOS
6. **Verifiser Cloud AI-veien** ende-til-ende på iPhone (anonym auth må være på)
7. Legg til Sign in with Apple
8. `flutter run -d <iphone>` og gå gjennom testlista i checklisten seksjon 8
9. Appikon, deretter store-assets
10. TestFlight

Punkt 4–6 er den egentlige jobben. Resten er konfigurasjon.

---

## 8. Når du er ferdig med en bolk

Skriv til prosjektminnet (`project_memory_write`) det som ikke kan utledes fra
koden: beslutninger og hvorfor, ting som ikke virket, Apple-spesifikke krav dere
støtte på. Oppdater `MEMORY.md`-indeksen med én linje. Neste sesjon starter kald.

Kryss også av i `IOS_LAUNCH_CHECKLIST.md` etter hvert — den er ment som et levende
dokument, ikke en engangsplan.
