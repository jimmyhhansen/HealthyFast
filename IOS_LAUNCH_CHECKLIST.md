# HealthyFast — iOS Launch Checklist

**Status per 2026-08-20:** `ios/` er generert, appen bygger og har kjørt på en
fysisk iPhone. Seksjon 4 (kodefiks) er nå gjort i Dart-koden. Gjenstår:
`flutterfire configure` må kjøres på nytt (firebase_options.dart manglet
fortsatt ekte iOS-config og krasjet appen ved oppstart), `pod install` for den
nye `sign_in_with_apple`-pakken, ikongenerering, og all manuell verifisering på
enheten (seksjon 8's TestFlight-liste er ikke rørt).

**Motstykket til [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md)** (som er 100 % Play Console).

> Konvensjon: `[ ]` = ikke gjort, `[x]` = ferdig. Kryss av mens du går.
> Rekkefølgen er tilsiktet — seksjon 4 (kodefiks) må gjøres før du kan teste noe.

---

## Fakta om prosjektet (til referanse)

| | |
|---|---|
| Flutter-app | `healthyfast`, versjon `2.0.0+226` |
| Android applicationId | `co.healthyfast` |
| Android namespace | `com.northernappdev.healthyfast` |
| **Foreslått iOS bundle ID** | **`co.healthyfast`** (lik Android — enklest) |
| Firebase-prosjekt | `healthyfast-f1f5a` |
| Abonnements-ID-er | `healthyfast_yearly` (200 kr/år), `healthyfast_monthly` (25 kr/mnd) |
| Min. iOS-versjon | 15.0 (Firebase iOS SDK 12.x-krav) |

---

## 1. Forutsetninger — før du rører kode

- [ ] **Apple Developer Program**, ~$99/år — [developer.apple.com/programs](https://developer.apple.com/programs/)
      Enroll som **enkeltperson** (raskest, 24–48 t) eller **organisasjon** (krever
      D-U-N-S-nummer, kan ta 1–2 uker). Enkeltperson viser ditt eget navn som
      utvikler i App Store; organisasjon viser firmanavnet. Velg bevisst — å bytte
      etterpå er tungvint.
- [ ] Xcode installert og lisens akseptert: `sudo xcodebuild -license accept`
- [ ] Kommandolinjeverktøy: `sudo xcode-select -s /Applications/Xcode.app`
- [ ] Flutter SDK på Mac: `flutter doctor` uten røde kryss for iOS-delen
- [ ] CocoaPods: `sudo gem install cocoapods` (eller `brew install cocoapods`)
- [ ] FlutterFire CLI: `dart pub global activate flutterfire_cli`
- [ ] En fysisk iPhone. **HealthKit finnes ikke i simulatoren** — kjernefunksjonen
      i appen kan ikke testes uten ekte enhet.

---

## 2. Få koden over fra Windows-PC-en

På **Windows-maskinen**, i `D:\Appdev\Android\HealthyFast`:

```powershell
.\cleanup_for_git.ps1 -DryRun     # se hva som skjer
.\cleanup_for_git.ps1             # rydd .gitignore + untrack node_modules
.\setup_github.ps1 -RepoName healthyfast -FreshHistory -RenameToMain
```

- [ ] Ryddet (12 600+ node_modules-filer ut av git-indeksen)
- [ ] Privat GitHub-repo opprettet og pushet
- [ ] Repoet er **privat** — `android/app/google-services.json` ligger sporet

På **Mac-en**:

```bash
git clone https://github.com/<bruker>/healthyfast.git
cd healthyfast
chmod +x setup_ios_mac.sh && ./setup_ios_mac.sh
```

- [ ] Klonet
- [ ] `setup_ios_mac.sh` kjørt uten feil

**Ting som IKKE ligger i git og må håndteres separat:**

| Fil | Hvordan skaffe den på Mac |
|---|---|
| Android keystore (`*.jks`) | Trengs ikke på Mac |
| `ios/Runner/GoogleService-Info.plist` | Genereres av `flutterfire configure` (seksjon 5) |
| Apple-sertifikater / provisioning | Xcode automatic signing ordner det |

---

## 3. iOS-plattform (`setup_ios_mac.sh` gjør dette)

- [ ] `ios/`-mappe generert med `flutter create --platforms=ios`
- [ ] `PRODUCT_BUNDLE_IDENTIFIER = co.healthyfast`
- [ ] `IPHONEOS_DEPLOYMENT_TARGET = 15.0` (både i `project.pbxproj` og `ios/Podfile`)
- [ ] `Info.plist`-nøkler skrevet (se seksjon 6)
- [ ] `ios/Runner/Runner.entitlements` opprettet
- [ ] `pod install` fullført
- [ ] **Kun iPhone:** sett `TARGETED_DEVICE_FAMILY = 1` i Xcode (Runner → Build
      Settings). Da slipper du å levere iPad-skjermbilder og å teste iPad-layout.
      Kan utvides senere.

---

## 4. Kodeendringer som MÅ gjøres 🔴

Dette er den reelle jobben. Appen kompilerer sannsynligvis på iOS, men flere
kjernefunksjoner er stille Android-only og vil feile uten synlig feilmelding.

### 4.1 Notifikasjoner — virker ikke i det hele tatt på iOS

`lib/services/notification_service.dart:31`

```dart
const android = AndroidInitializationSettings('@mipmap/ic_launcher');
const settings = InitializationSettings(android: android);   // ← ingen iOS
```

- [x] Lagt til `DarwinInitializationSettings` i `InitializationSettings`
- [x] `requestPermissions()` og `requestNotificationsPermission()` har nå en
      `IOSFlutterLocalNotificationsPlugin`-gren (`requestPermissions(alert:
      badge: sound:)`)
- [x] `AndroidNotificationChannel`-oppsettet er allerede trygt på iOS
      (`resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()`
      returnerer `null` der og short-circuiter med `?.`) — ingen egen guard
      nødvendig
- [x] `scheduleMilestones()` har nå et budsjett på 62 varsler på iOS (holder
      1 slot ledig til den daglige påminnelsen, under Apples grense på 64)
- [ ] Tidssonen er hardkodet til `Europe/Oslo` (linje ~23). Fungerer, men vurder
      `flutter_timezone` før internasjonal lansering.

**Faste-milepælvarsler er en kjernefunksjon.** Uten dette er iOS-appen halvferdig.

### 4.2 Firebase — kaster exception på iOS

`lib/firebase_options.dart` har `case TargetPlatform.iOS: throw UnsupportedError(...)`.

`main.dart` fanger dette i en `try`/`catch` (best-effort), så appen starter — men
**cloud sync, Cloud AI og Google-innlogging er døde**.

- [ ] Fikses av `flutterfire configure` i seksjon 5. **Status 2026-08-20:**
      filen var fortsatt på throw-stub-versjonen (`flutterfire configure` ble
      aldri kjørt ferdig med et gyldig resultat lagret) — appen krasjet ved
      oppstart på ekte iPhone med nettopp denne feilen. Kjør kommandoen i
      seksjon 5 på nytt.

### 4.3 MethodChannels — kun implementert i Kotlin

Alle fire kaster `MissingPluginException` på iOS:

| Kanal | Dart-fil | Hva den gjør | iOS-plan |
|---|---|---|---|
| `healthyfast/meal` | `services/meal_estimator_service.dart`, `services/training_ai_service.dart` | Gemini Nano på enheten | **Alle** iOS-enheter må bruke Cloud AI |
| `healthyfast/health` | `services/health_sync_service.dart` | `getDailySteps` | Bruk `health`-pakkens `getHealthDataFromTypes` |
| `healthyfast/wear` | `services/complication_service.dart`, `ongoing_activity_service.dart`, `wear_install_service.dart` | Wear OS tiles/complications | Ikke relevant — må no-op'e |
| `healthyfast/nav` | `screens/watch_screen.dart` | Wear OS-navigasjon | Ikke relevant — må no-op'e |

- [x] **`healthyfast/meal` er den kritiske.** Alle offentlige metoder i
      `meal_estimator_service.dart` og `training_ai_service.dart` returnerer nå
      trygt (`NanoStatus.unavailable`/`null`/`false`) på `!Platform.isAndroid`
      i stedet for å kalle den ikke-eksisterende native kanalen.
      🔗 Se `project_healthyfast_firebase_anonymous_auth.md` i prosjektminnet:
      **anonym auth må være påslått i Firebase Console**, ellers feiler Cloud AI.
      Det gjelder 100 % av iOS-brukerne, ikke bare noen telefoner. **Ikke
      verifisert ennå — sjekk Firebase Console.**
- [x] `screens/cloud_ai_settings_screen.dart` skjuler nå hele "On-device AI"-
      seksjonen når `!Platform.isAndroid`.
- [x] `health_sync_service.dart:179` er allerede trygg: den native kanalen er
      gated på Android, og fallbacken bruker `_health.getHealthDataFromTypes` med
      `HealthDataType.STEPS`. Denne virker som den skal på iOS. ✅
- [x] `HealthDataType.SLEEP_SESSION` byttet ut med en platform-betinget
      `_sleepTypes`-getter: `SLEEP_ASLEEP` + `SLEEP_DEEP` + `SLEEP_REM` på iOS,
      `SLEEP_SESSION` uendret på Android. Disse HealthKit-kategoriene overlapper
      ikke i tid innenfor én kilde (en natt er enten enkle "asleep"-prøver eller
      Core/Deep/REM-prøver, aldri begge), så summeringen i
      `readSleepMinutesPerDay()` bør ikke dobbelttelle — **ikke testet på ekte
      søvndata ennå**, verifiser tallene ser fornuftige ut når du tester.
- [x] Wear-tjenestene (`complication_service.dart`, `ongoing_activity_service.dart`,
      `wear_install_service.dart`) har nå tidlig `if (!Platform.isAndroid) return;`.
- [x] `wearable_rotary` og `watch_connectivity`: `pod install` og Xcode-bygget gikk
      gjennom uten feil relatert til disse — ingen endring nødvendig.

### 4.4 Google Sign-In

`lib/services/cloud_backup_service.dart:69` kaller
`GoogleSignIn.instance.initialize(serverClientId: ...)`.

- [ ] På iOS trengs også `clientId` (iOS OAuth-klienten fra `GoogleService-Info.plist`)
      — avhenger av at `flutterfire configure` er kjørt på nytt (seksjon 5)
- [ ] `CFBundleURLTypes` med `REVERSED_CLIENT_ID` i `Info.plist` (seksjon 5)
- [x] ⚠️ **App Store-regel 4.8:** tilbyr du tredjeparts-innlogging (Google), *må* du
      også tilby **Sign in with Apple**. `sign_in_with_apple` + `crypto` lagt til i
      `pubspec.yaml`, `CloudBackupService.signInWithApple()` (nonce-flyt mot
      Firebase `OAuthProvider('apple.com')`) lagt til, og en Google/Apple-velger
      vises nå før innlogging på iOS (`cloud_ai_settings_screen.dart` og
      `cloud_ai_consent_sheet.dart`). **Ikke kjørt `pod install` eller testet
      end-to-end ennå.** Husk også: "Sign in with Apple"-capability i Xcode
      (seksjon 6) og Apple-provider i Firebase Console (seksjon 5).

### 4.5 Appikon

- [x] `flutter_launcher_icons: ios: true` satt i `pubspec.yaml` (verifisert at
      `new icon.png` er opak/kvadratisk før dette ble slått på — IKKE bruk
      `assets_design/healthyfast_icon_1024.png`, den har gjennomsiktighet).
- [ ] `dart run flutter_launcher_icons` **ikke kjørt ennå** — gjør dette etter
      `flutter pub get` (se "Neste steg" nederst i denne seksjonen)
- [ ] Ikonet må være 1024×1024 uten avrundede hjørner (iOS runder selv)

### 4.6 Diverse

- [x] `main.dart:57` `_detectWatch()` returnerer `false` når `!Platform.isAndroid` — OK
- [x] UI-tekst gjennomgått i `settings_screen.dart` (Install on Watch skjult,
      "Rate on Google Play"/"Cloud & AI"-tekst platform-bevisst),
      `journal_screen.dart` (Sync-tooltip og bunnark-tittel) og
      `cloud_ai_settings_screen.dart` (`_healthAppName`: "Health Connect" vs
      "Apple Health") og `fitness_goal.dart` (Wear OS-capability skjult).
      Ikke uttømmende — resten av appen er ikke grepet gjennom for gjenværende
      "Wear OS"/"Google Fit"-referanser.
- [ ] `url_launcher` mot YouTube-formvideoer: legg til `LSApplicationQueriesSchemes`
      hvis du vil åpne YouTube-appen i stedet for Safari

**Neste steg nå (2026-08-20), i rekkefølge:**

```bash
flutter pub get                       # henter sign_in_with_apple + crypto
dart run flutter_launcher_icons       # genererer iOS-ikonsettet (4.5)
flutterfire configure \
  --project=healthyfast-f1f5a \
  --platforms=ios \
  --ios-bundle-id=co.healthyfast      # regenererer firebase_options.dart (4.2/5) — kjør fra prosjektroten
cd ios && pod install && cd ..        # ny pod: sign_in_with_apple
flutter run -d 00008101-001905D82628801E
```

Sjekk også Firebase Console → Authentication → Sign-in method: Anonymous,
Google **og Apple** påslått (seksjon 5) før du tester innlogging.

---

## 5. Firebase-oppsett for iOS

```bash
flutterfire configure \
  --project=healthyfast-f1f5a \
  --platforms=ios \
  --ios-bundle-id=co.healthyfast
```

Dette gjør tre ting: registrerer iOS-appen i Firebase, laster ned
`ios/Runner/GoogleService-Info.plist`, og skriver om `lib/firebase_options.dart`.

- [ ] Kjørt, og `firebase_options.dart` har nå en `static const FirebaseOptions ios`
- [ ] `GoogleService-Info.plist` ligger i `ios/Runner/` **og er lagt til i Xcode-targetet**
      (dra den inn i Xcode hvis den ikke vises i prosjekttreet — filsystemet alene holder ikke)
- [ ] Firebase Console → Authentication → Sign-in method:
      - [ ] **Anonymous er påslått** (kritisk — Cloud AI for alle iOS-brukere)
      - [ ] Google er påslått
      - [ ] Apple er påslått (for Sign in with Apple, seksjon 4.4)
- [ ] `REVERSED_CLIENT_ID` fra plist-en lagt inn som URL scheme i `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.NNNNNN-xxxxxxxx</string>
    </array>
  </dict>
</array>
```

- [ ] `firestore.rules` gjennomgått — samme regler gjelder iOS-klienter
- [ ] Cloud Functions (`functions/`) trenger ingen endring, men verifiser at
      AI-endepunktene svarer fra en iOS-klient

---

## 6. Info.plist og entitlements

`setup_ios_mac.sh` skriver disse. Kryss av at de faktisk står der:

| Nøkkel | Hvorfor |
|---|---|
| `NSHealthShareUsageDescription` | Leser STEPS, WORKOUT, WEIGHT, SLEEP_SESSION |
| `NSHealthUpdateUsageDescription` | Skriver NUTRITION, WEIGHT |
| `NSMicrophoneUsageDescription` | `speech_to_text` — diktering av måltid |
| `NSSpeechRecognitionUsageDescription` | `speech_to_text` — transkribering |
| `NSCameraUsageDescription` | `image_picker` — foto av måltid |
| `NSPhotoLibraryUsageDescription` | `image_picker` — velge bilde |
| `ITSAppUsesNonExemptEncryption = false` | Slipper eksportspørsmål ved hver opplasting |
| `CFBundleDisplayName = HealthyFast` | Navn under ikonet |

- [ ] Alle åtte på plass
- [ ] **Teksten er brukervendt.** Apple avviser generiske beskrivelser som
      "This app needs camera access". Forklar *hva brukeren får igjen for det*.

**Capabilities i Xcode** (`open ios/Runner.xcworkspace` → Runner → Signing & Capabilities → `+`):

- [ ] HealthKit
- [ ] In-App Purchase
- [ ] Sign in with Apple
- [ ] Push Notifications — *bare* hvis du skal ha remote push. Lokale varsler
      (`flutter_local_notifications`) trenger det ikke.

---

## 7. App Store Connect

- [ ] Bundle ID `co.healthyfast` registrert under Certificates, IDs & Profiles →
      Identifiers, med HealthKit + In-App Purchase + Sign in with Apple huket av
- [ ] Ny app opprettet i App Store Connect (navn, primærspråk, SKU)
- [ ] **Appnavn** — «HealthyFast» må være ledig. Sjekk tidlig; navnet reserveres
      når appen opprettes. Undertittel (30 tegn) er verdifull for søk:
      f.eks. «Fasting, Calories & Lifting»
- [ ] Kategori: Health & Fitness (primær), Lifestyle (sekundær)
- [ ] Aldersgrense-spørreskjema besvart

### 7.1 Abonnementer

- [ ] Subscription Group opprettet (f.eks. «HealthyFast Premium»)
- [ ] `healthyfast_yearly` — 200 kr/år, opprettet med **nøyaktig samme ID** som i
      `lib/providers/purchase_provider.dart:16`
- [ ] `healthyfast_monthly` — 25 kr/mnd, ID fra linje 17
- [ ] Priser satt for alle territorier du selger i
- [ ] Lokaliserte visningsnavn + beskrivelser
- [ ] Review-screenshot for hvert abonnement (obligatorisk)
- [ ] **Paywall-krav Apple håndhever** — mangler noe av dette blir du avvist:
      - [ ] Pris og periodelengde synlig *før* kjøp
      - [ ] Fungerende «Restore Purchases»-knapp
      - [ ] Lenke til personvernerklæring
      - [ ] Lenke til vilkår (Apples standard-EULA holder, men lenken må finnes)
      - [ ] Klart at abonnementet fornyes automatisk
- [ ] Sandbox-testbruker opprettet (App Store Connect → Users and Access → Sandbox)

### 7.2 App Privacy

- [ ] Spørreskjemaet fylt ut. HealthyFast samler: helse & trening, mat/kosthold,
      brukerinnhold (måltidsbilder), identifikatorer (Firebase UID), bruksdata
- [ ] **HealthKit-data kan ikke brukes til reklame eller selges** — bekreft at det
      stemmer i praksis
- [ ] Personvernerklæring publisert på en URL. Den må uttrykkelig nevne HealthKit
- [ ] Angi om data er koblet til brukeren (ja — cloud sync bruker Firebase UID)

### 7.3 Assets

- [ ] iPhone 6.9" skjermbilder (1320×2868 eller 1290×2796) — **obligatorisk**, 3–10 stk
- [ ] Ingen iPad-skjermbilder nødvendig hvis `TARGETED_DEVICE_FAMILY = 1`
- [ ] Beskrivelse (4000 tegn) — kan gjenbruke Play Store-teksten, men fjern alle
      Android-referanser («Wear OS», «Google Fit», «Health Connect»)
- [ ] Nøkkelord (100 tegn, kommaseparert, ingen mellomrom). Ikke gjenta ord fra
      tittel/undertittel — de indekseres allerede
- [ ] Support-URL og markedsførings-URL
- [ ] `store_assets/` og `screenshots/` i repoet har Android-materiale å gjenbruke

---

## 8. Bygg, signer, last opp

- [ ] Xcode → Runner → Signing & Capabilities → Team valgt, «Automatically manage
      signing» på
- [ ] `flutter build ipa --release`
- [ ] Last opp: `xcrun altool` eller Xcode Organizer, eller
      `flutter build ipa` + Transporter-appen
- [ ] Første opplasting utløser Export Compliance — dekket av
      `ITSAppUsesNonExemptEncryption = false`
- [ ] Bygget dukker opp i App Store Connect (kan ta 15–60 min prosessering)

### TestFlight

- [ ] Intern testing på egen enhet først
- [ ] **Test alle disse på ekte iPhone:**
      - [ ] HealthKit-tillatelse spørres om og innvilges
      - [ ] Måltid skrives til Apple Health
      - [ ] Steg leses fra Apple Health
      - [ ] Faste-milepælvarsel kommer mens appen er i bakgrunnen
      - [ ] Måltidslogging via tale (mikrofon + talegjenkjenning)
      - [ ] Måltidslogging via foto (kamera + galleri)
      - [ ] Cloud AI-estimat (ikke Nano — den finnes ikke)
      - [ ] Kjøp av abonnement i sandbox
      - [ ] Restore purchases
      - [ ] Google-innlogging + Sign in with Apple
      - [ ] Cloud sync opp og ned
      - [ ] Slett app → installer på nytt → data gjenopprettes
- [ ] Ekstern testing (opptil 10 000 testere, krever en lettvekts Apple-review)

---

## 9. App Review — fallgruver for denne appen spesielt

Faste- og kaloriapper granskes hardere enn snittet. Regn med minst én runde.

- [ ] **Sign in with Apple mangler** når Google-innlogging tilbys (regel 4.8) —
      den vanligste avvisningen for denne apptypen
- [ ] **Abonnementsinfo mangler på paywall** (regel 3.1.2)
- [ ] **Medisinske påstander.** Ikke lov å skrive at appen behandler, diagnostiserer
      eller kurerer noe. «Autofagi-sone» er greit som informasjon; «reverserer
      diabetes» er det ikke. Gå gjennom `kCapabilities` i
      `lib/models/fitness_goal.dart` og onboarding-teksten med dette blikket
      (den er én kilde til all funksjonskopi — se prosjektminnet)
- [ ] **Kaloriberegning fra AI.** Vurder en synlig ansvarsfraskrivelse om at
      estimatene er omtrentlige
- [ ] **HealthKit-formål.** Reviewer må forstå *hvorfor* appen trenger hver datatype.
      Bruk Review Notes-feltet til å forklare det
- [ ] **Demo-konto i Review Notes** hvis noe er innlogget bak
- [ ] **Testinstruksjoner** — beskriv hvordan reviewer starter en faste og logger
      et måltid, ellers gjetter de
- [ ] **Spiseforstyrrelser.** Kaloritelling + faste er et sensitivt område. En kort,
      synlig oppfordring om å konsultere lege, og ingen aggressiv «du ligger under
      målet»-gamification, reduserer risikoen betraktelig

---

## 10. Etter lansering

- [ ] App Store Connect → Analytics kobles opp
- [ ] Xcode Organizer → Crashes overvåkes
- [ ] Svar på anmeldelser (Apple lar deg svare direkte)
- [ ] Oppdater [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) og
      [`PROJECT_NOTES.md`](PROJECT_NOTES.md) med iOS-lærdommene
- [ ] Vurder Apple Watch-app. `watch_connectivity`-pakken er allerede inne, men
      selve watch-appen må skrives i SwiftUI (Wear OS-koden kan ikke gjenbrukes).
      **Ikke gjør dette til v1** — den kan komme i 1.1

---

## Estimert innsats

| Fase | Tid |
|---|---|
| Overføring + `ios/`-generering | 1–2 timer |
| Kodefiks (seksjon 4) | 1–3 dager |
| Firebase + Apple-oppsett | 2–4 timer |
| Assets + store-listing | 4–8 timer |
| TestFlight + fiksrunder | 2–5 dager |
| App Review | 1–3 dager per runde |

Realistisk fra dagens punkt til «live i App Store»: **2–4 uker**, forutsatt at
Apple Developer-medlemskapet er godkjent.
