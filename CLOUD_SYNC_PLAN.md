# HealthyFast — Cloud Sync / Backup Plan

Skrevet 2026-07-19. Bygger på det ferdige oppsettet i VinoKeep, som allerede
har cloud sync i produksjon.

## Hva VinoKeep gjør (referansearkitektur)

VinoKeep har **to uavhengige mekanismer**:

1. **BackupService** (`lib/services/backup_service.dart`) — eksporterer hele
   databasen til én fil (XML) via systemets filvelger / delingsmeny. Brukeren
   velger selv en synk-mappe (Drive/OneDrive/iCloud). **Ingen egne sky-API-
   nøkler, ingen konto, ingen løpende kostnad.**

2. **CloudSyncService** (`lib/services/cloud_sync_service.dart`, premium) —
   sanntids toveis-synk via Firebase:
   - Firebase Auth med **Google Sign-In** (varig innlogging).
   - Firestore speiler den lokale databasen: `users/{uid}/{samling}/{id}`,
     hvert dokument = rad + `updatedAt` (server-timestamp).
   - Lokal DB er kilden; en `SyncSink`-abstraksjon (`sync_sink.dart`) kalles
     etter hver lokal mutasjon. Kjernen importerer aldri Firebase direkte.
   - Fjernendringer dras inn via realtime-lyttere og skrives med
     `applyWithoutMirror` for å unngå ekko-loop.
   - Firebase-prosjekt: `vinokeep-56196` (flere Android-apper registrert).

## Hva som kan gjenbrukes direkte

- **Firebase-konto/console** (din) og eventuelt **samme GCP-prosjekt** — vi
  registrerer bare en ny Android-app for `com.northernappdev.healthyfast`.
- **Kodemønsteret**: `SyncSink` + `CloudSyncService` + `BackupService` som mal.
- **Pakkene**: `firebase_core`, `cloud_firestore`, `firebase_auth`,
  `google_sign_in` (samme versjoner som VinoKeep bruker i dag).

## Forskjellen som må håndteres

VinoKeep bruker **SQLite** (én `AppDatabase` med rader). HealthyFast bruker
**Hive** + litt SharedPreferences. Det vi må sikkerhetskopiere:

Hive-bokser:
- `fasts` (FastRecord)
- `meals` (MealRecord)
- `workouts` (WorkoutRecord)
- `weights` (WeightRecord)

SharedPreferences (state, ikke rådata):
- `training_state`, `program_json`, `active_session` — treningsprogram/framgang
- `profile_*` — energiprofil (alder, kjønn, høyde, vekt, aktivitet, TDEE)

Utelates bevisst fra backup:
- `is_premium` — kjøp/entitlement gjenopprettes via Google Play, ikke fra sky.
- `health_sync_enabled` — enhetsspesifikk innstilling.

## To alternativer

## VALGT LØSNING (2026-07-19)

**Full Firebase cloud sync (Alternativ B), nytt Firebase-prosjekt, ingen
fil-backup.** Premium-gated som i VinoKeep (konsistent med at Meals/Insights/
Health Connect allerede er premium) — si fra hvis den heller skal være gratis.

Firestore-struktur: `users/{uid}/fasts|meals|workouts|weights/{id}`, hvert
dokument = record-feltene + `updatedAt` (server-timestamp).

## Kodearbeid jeg gjør (når Firebase-konfig er på plass)

1. Legg til `firebase_core`, `cloud_firestore`, `firebase_auth`,
   `google_sign_in` i `pubspec.yaml`.
2. `SyncSink`-abstraksjon (ren Dart, `NoopSyncSink` som standard) + hooks i
   `FastingProvider`/`TrainingProvider` etter hver add/update/delete.
3. `CloudSyncService` (Firebase) tilpasset Hive — speiler de fire boksene,
   realtime-lyttere med "apply uten å speile tilbake" (unngår ekko).
4. **Stabil sync-id på modellene:** de fire Hive-modellene mangler i dag en
   unik id (Firestore-dok trenger en). Jeg legger til et `syncId`-felt (uuid)
   med oppdaterte håndskrevne Hive-adaptere. Nødvendig for pålitelig
   upsert/delete på tvers av enheter.
5. Enkel "Cloud sync"-seksjon i Settings: logg inn med Google, vis konto,
   på/av, "sync nå".
6. `firebase.initializeApp` i `main.dart`.

Punkt 1–6 kan jeg ikke fullføre før prosjektet er opprettet, fordi
`lib/firebase_options.dart` genereres av `flutterfire configure`.

## Oppskrift — det bare du kan gjøre (Firebase-innlogging)

Kjør i rekkefølge. Alle kommandoer setter deg i riktig mappe først.

**0) Verktøy (én gang):**
```powershell
npm install -g firebase-tools ; dart pub global activate flutterfire_cli
```

**1) Logg inn:**
```powershell
firebase login
```

**2) Opprett nytt prosjekt** (bytt `healthyfast-XXXX` til noe globalt unikt):
```powershell
firebase projects:create healthyfast-XXXX --display-name "HealthyFast"
```

**3) Registrer appen + generer konfig** (skriver `lib/firebase_options.dart`
og `android/app/google-services.json`):
```powershell
cd D:\Appdev\Android\HealthyFast ; flutterfire configure --project=healthyfast-XXXX --platforms=android --yes 2>&1 | Tee-Object -FilePath D:\Appdev\Android\HealthyFast\build_logs\flutterfire.log
```

**4) Signeringsnøkler for Google Sign-In** (kopier SHA-1 og SHA-256 inn i
Firebase Console → Project settings → din Android-app → Add fingerprint):
```powershell
cd D:\Appdev\Android\HealthyFast\android ; .\gradlew signingReport 2>&1 | Tee-Object -FilePath D:\Appdev\Android\HealthyFast\build_logs\signingreport.log
```
Legg også til **Play App Signing**-SHA fra Play Console → Setup → App signing.

**5) I Firebase Console:**
- Authentication → Sign-in method → aktiver **Google**.
- Firestore Database → Create database → produksjonsmodus.
- Firestore → Rules → lim inn og publiser:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{col}/{doc} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

**6) Gi meg beskjed** når `lib/firebase_options.dart` og
`android/app/google-services.json` finnes — så skriver jeg punkt 1–6 over.
Send meg gjerne `build_logs\flutterfire.log` hvis noe feiler.
