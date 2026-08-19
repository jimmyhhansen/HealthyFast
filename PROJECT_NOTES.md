# HealthyFast — Project Notes & Learnings

Sist oppdatert 2026-07-19. Dette dokumentet er den løpende statusoversikten
for prosjektet — gammelt innhold er overskrevet, ikke lagt til under.

## Hva appen er

**HealthyFast** — Android (telefon + Wear OS), Flutter/Dart, én kodebase.
- Package: `co.healthyfast` (namespace i Gradle er fortsatt
  `com.northernappdev.healthyfast` — kun Kotlin-pakkenavn, ikke
  applicationId, ingen praktisk betydning).
- Versjon: 2.0.0+124 i pubspec.yaml.
- Fire faner: **Fast · Meals · Workout · Journal** (Settings er tannhjul i
  AppBar).
- Monetisering: gratis kjerne + ett premium-abonnement (årlig/månedlig) via
  `in_app_purchase`. Ingen annonser (AdMob-planen fra tidlig prototype er
  forlatt).

## Arkitektur

- **State**: Provider (`FastingProvider`, `ProfileProvider`,
  `TrainingProvider`, `PurchaseProvider`).
- **Lokal lagring**: Hive (fire bokser: `fasts`, `meals`, `weights`,
  `workouts`) + SharedPreferences for enkeltverdier/state-blobs
  (`training_state`, `program_json`, `profile_*`, `is_premium`,
  `health_sync_enabled`, `cloud_backup_enabled`).
- **Health Connect**: `health` v13-pakken. Skriver måltider/vekt/treningsøkter
  ut, leser dem tilbake fra andre apper (import). Premium-funksjon.
- **Wear OS**: samme Flutter-kodebase, egen entry point (`isWatch`-flagg i
  `main.dart` velger `WatchScreen()` vs `RootScreen()`), egen Android source
  set `android/app/src/watch/` (kun manifest/ressurser, ingen egen UI-kode).
  Klokken er delvis frittstående (kan logge treningsøkt selv uten telefon i
  nærheten) og synker via `watch_connectivity`.
- **AI (måltidslogging)**: on-device Gemini Nano via metodekanal
  (`meal_estimator_service.dart`). Tekst- og fotobasert — samme modell for
  begge. Kun på støttede enheter (Pixel 8/9+, Galaxy S25/S26/Fold/Flip).
  Fallback til manuell inntasting ellers.
- **Cloud backup** (nytt, se egen seksjon under): Firebase (Auth +
  Firestore), premium-gated.

## Fasteoner (uendret siden tidlig design)

| Sone | Timer | Farge | Kilde |
|---|---|---|---|
| Fed State | 0–4t | Grå | Cahill, Annual Review of Nutrition (2006) |
| Early Fast | 4–8t | Amber | Dr. Jason Fung, The Obesity Code (2016) |
| Glycogen Burning | 8–14t | Oransje | de Cabo & Mattson, NEJM (2019) |
| Metabolic Switch | 14–18t | Lyseblå | Mattson et al., Nature Reviews Neuroscience (2018) |
| Fat Burning | 18–24t | Teal | Veech, Annals of NYAS (2004) |
| Autophagy | 24–36t | Lilla | Yoshinori Ohsumi, Nobel Prize 2016 |
| Deep Renewal | 36t+ | Indigo | Ho KY et al., Journal of Clinical Investigation (1988) |

## Nylig fullført (denne økta, 2026-07-19)

1. **Wear-app**: Log workout-flyten starter nå alltid med programvalg
   (`_Stage.pickProgram`) før dagvalg — Program → Workout → Øvelser. Save
   set-knappen klippes ikke lenger på maks skjermstørrelse (bezel-safe
   innrykk lagt til, samme konvensjon som `WearScrollView._safePadding`).
2. **Insights-grafer** (`journal_screen.dart`): fjernet en hardkodet
   99999-cap på y-aksen som fikk søyler til å overflyte på Kvartal/År (der
   bøttesummer lett oversteg taket). Aksen er nå dynamisk. Redesignet fra
   loddrette til liggende søyler med full etikett + verdi per rad.
3. **Phone info-knapp** i aktiv workout: tydeligere (større, tonet
   sirkel-bakgrunn, tooltip "Click for guide").
4. **Screenshots**: rettet opp `wear1–4.png` som hadde gjennomsiktig
   alfakanal (Play Store krever flat RGB).
5. **Store listing** (`store_assets/listing_text.md`) og nytt feature
   graphic (`play_feature_1024x500.png`) — oppdatert til å dekke alle tre
   pilarer (faste, kalorier, styrketrening), ikke bare faste + AI-mat som
   før.
6. **Premium-modell omarbeidet**:
   - All faste (inkl. custom/14 dager) er nå **gratis**.
   - Meals- og Workout-fanene er browsbare for alle; **"+"-knappen**
     (logging) er premium.
   - Journal er gratis; **Insights** er fortsatt premium.
   - Health Connect is premium.
   - Energy Profile-wizarden trigges nå kun for premium-brukere (gir ikke
     mening uten Meals). Den har nå 7 steg og støtter både metriske (kg/cm) og
     britiske (lbs/ft) enheter.
7. **Workout-programmer**: `Full-body Basics` er default på fresh install,
   dagene heter nå **"Full body 1"** og **"Full body 2"** (var "Workout
   A/B"). Programvalg huskes fortsatt via `training_state`.
8. **Health Connect-sletting**: sletter man et meal/workout i appen, slettes
   nå også den speilede HC-posten (`HealthSyncService.deleteMeal/
   deleteWorkout`), ellers kom den tilbake ved neste import.

## Cloud backup — status (pågår)

**Mål**: premium cloud-backup av Hive-dataene (fasts/meals/weights/workouts)
via Firebase, gjenbruker mønster fra søsterprosjektet VinoKeep
(`D:\Appdev\Android\VinoKeep`).

**Designvalg**: ekte *backup*, ikke sanntids toveis-synk. "Back up" laster
opp alt lokalt (tildeler en stabil `syncId` per record hvis den mangler).
"Restore" henter sky-records og **fletter** dem inn lokalt, de-dupet på
`syncId` — sletter **aldri** noe lokalt (en backup skal ikke kunne slette
data). Per-record Firestore-dokumenter (ikke én stor snapshot-blob) unngår
1 MB-grensen uansett historikklengde.

**Firebase-prosjekt**: `healthyfast-f1f5a` (prosjektnummer 1093411081699),
opprettet som eget nytt prosjekt (ikke gjenbruk av VinoKeep sitt). Android-app
registrert som `co.healthyfast`.

**Gjort:**
- `pubspec.yaml`: lagt til `firebase_core`, `cloud_firestore`,
  `firebase_auth`, `google_sign_in`, `uuid` (versjoner speiler VinoKeep).
  SDK-grense bumpet til `>=3.4.0` (krav fra Firebase 4.x).
- `lib/firebase_options.dart` + `android/app/google-services.json`
  generert via `flutterfire configure`.
- `main.dart`: `Firebase.initializeApp()` (kun telefon, feiltolerant —
  kan ikke blokkere appstart).
- Alle fire Hive-modeller (`FastRecord`, `MealRecord`, `WeightRecord`,
  `WorkoutRecord`) har fått et `syncId`-felt (nytt `@HiveField`-nummer på
  slutten av hver klasse) — Firestore-dokument-id. Null på gamle records,
  tildeles lazy ved første backup.
- `lib/services/cloud_backup_service.dart` (ny): Google-innlogging +
  Firestore push/pull, se docstring i fila for full kontrakt.
- `fasting_provider.dart`: `mergeCloudRecords(...)` — de-dup på `syncId`,
  legger kun til, sletter aldri.
- `settings_screen.dart`: "Cloud backup"-seksjon (premium-gated): av/på med
  Google-innlogging, "Back up now", "Restore from cloud".
- SHA-1/SHA-256 for debug- og upload-nøkkel lagt inn i Firebase Console
  (Play App Signing-SHA gjenstår — legges inn ved første Play-opplasting).
- Google-provider aktivert i Firebase Authentication.
- `serverClientId` lagt inn eksplisitt i `cloud_backup_service.dart` (se
  Lærdommer under — google_sign_in v7 krever dette manuelt på Android).

**Gjenstår / ikke bekreftet:**
- Firestore Database er **ikke bekreftet opprettet** ennå, og
  sikkerhetsreglene (`users/{uid}/{col}/{doc}` — kun eier har tilgang) er
  ikke bekreftet publisert. Uten dette vil backup/restore feile med en
  permission-feil selv etter at innlogging virker.
- Google-innlogging feilet første testrunde med
  `clientConfigurationError: serverClientId must be provided on Android`.
  Rotårsak identifisert og fikset i koden — **venter på bekreftelse fra ny
  test** (`flutter run`, ingen `clean` nødvendig for denne spesifikke
  endringen siden det er en ren Dart-kodeendring).
- End-to-end ikke testet: sign-in → backup → restore på en ny/annen enhet.

## Lærdommer fra denne økta

### google_sign_in v7 krever eksplisitt `serverClientId` på Android
Fra og med `google_sign_in` v7 (Credential Manager-basert
Android-implementasjon) leses web-OAuth-klienten **ikke** lenger automatisk
fra `google-services.json` slik den gamle pluginen gjorde. Kaller man
`GoogleSignIn.instance.initialize()` uten `serverClientId`, feiler
`authenticate()` med
`GoogleSignInExceptionCode.clientConfigurationError: serverClientId must be
provided on Android`. Fix: hent web-klient-ID-en (`client_type: 3`-oppføringen
i `google-services.json`) og send den eksplisitt:
```dart
await GoogleSignIn.instance.initialize(serverClientId: '<web-client-id>');
```
Denne ID-en er ikke hemmelig (den identifiserer OAuth-klienten, ikke en
API-nøkkel) — trygg å ha i kildekoden. Denne fallgruven gjelder trolig også
VinoKeep (samme pakkeversjon) og er verdt å sjekke der.

### `google-services.json` må stå i `android/app/`, ikke prosjektroten
Nedlastede kopier fra Firebase Console havnet i prosjektroten under denne
økta i stedet for `android/app/google-services.json`, og den filen som
faktisk lå i `android/app/` ble stående igjen truncated/utdatert en periode.
Sjekk alltid at filen Gradle faktisk bruker (`android/app/google-services.json`)
er komplett (har en `client_type: 3`-oppføring hvis Google-innlogging skal
virke) og ikke en gammel kopi. Rydd bort duplikater i prosjektroten for å
unngå forvirring.

### `google-services`-pluginen cacher — kjør `flutter clean` etter ny JSON
Etter å ha byttet ut `google-services.json` regenereres ikke
`default_web_client_id`/andre Android-strengressurser før et rent bygg.
`flutter run` alene er ikke nok — kjør `flutter clean && flutter pub get`
først.

### PATH-verktøy i Windows PowerShell
`dart pub global activate` installerer ikke kommandoen på PATH automatisk.
Kjør via `dart pub global run <pakke>:<kommando>` i stedet for å anta at
kommandonavnet (f.eks. `flutterfire`) er tilgjengelig direkte. Samme gjelder
`java`/`gradlew` — krever `JAVA_HOME` satt manuelt til Android Studios
embedded JDK (`C:\Program Files\Android\Android Studio\jbr`) i miljøer uten
global Java-installasjon.

### Play Console har flyttet App Integrity-innstillinger
"Appintegritet" i venstremenyen er nå kun en henvisning til
**"Beskyttet med Play"**. Appsigneringsnøkkelen (Play App Signing SHA) ligger
under **Test og publiser → Oppsett → Appsignering**, ikke lenger under den
gamle "Appintegritet"-siden.

### Bar-chart y-akse: aldri hardkode et cap uten å sjekke bøttestørrelsen
99999-taket i `_BarChartPainter` var satt for å unngå NaN/uendelig ved tom
graf, men samme konstant ble brukt som *faktisk* skala-cap — noe som først
ble en synlig bug når bøttegranulariteten endret seg (uke-/månedssummer på
Kvartal/År kan lett bli store nok til at et vilkårlig tall blir for lavt).
Riktig mønster: skaler alltid til `max(data)`, bruk en `min`-gulv (f.eks.
1.0) kun for å unngå divisjon på null.

## Verktøy jeg (Claude) ikke har i sandkassen

Ingen Dart/Flutter-SDK i denne økta — kan ikke kjøre `flutter analyze`,
`flutter run` eller `dart run build_runner` selv. All verifisering av
Dart-endringer skjer ved nøye gjennomlesing + brukeren kjører kommandoene og
limer inn resultatet. Ha dette i mente ved fremtidige økter: be alltid om
`flutter analyze`-resultat etter en runde med kodeendringer, spesielt etter
strukturelle endringer (nye Hive-felt, omskrevne widget-trær).

## Neste steg

1. Bekreft Firestore Database er opprettet + reglene publisert (se
   `CLOUD_SYNC_PLAN.md` for eksakt regeltekst).
2. Re-test Google-innlogging etter `serverClientId`-fiksen.
3. Test full runde: back up → avinstaller/ny enhet (eller "Sign out" +
   "Sign in" på nytt) → restore → bekreft data kommer tilbake.
4. Legg til Play App Signing SHA i Firebase når appen er lastet opp til Play
   Console første gang.
5. Vurder om cloud backup skal kjøre automatisk (f.eks. ved app-lukking) i
   stedet for kun manuell "Back up now" — ikke besluttet ennå.
6. `flutter analyze` bør kjøres på nytt etter siste endring i
   `cloud_backup_service.dart` (serverClientId-fiksen) — ikke verifisert av
   meg siden jeg ikke har Dart/Flutter i sandkassen.
