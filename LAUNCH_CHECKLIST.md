# HealthyFast — Sjekkliste før lansering

Sist oppdatert: 2026-07-18. Punktene under er ting som bevisst står åpne i
testfasen og **må** håndteres før produksjonslansering på Play Store.

## v2.0.0 — punkter til neste lansering (logget 2026-07-18)

Stor runde: energiprofil (BMR/TDEE), Meals-dashboard, Insights (mønster- og
mikronæringsinnsikter), talelogging fra klokke, foto-scan (spike). Ingenting
av dette er kjørt på fysisk enhet ennå — kun kompilert/lest gjennom kode.

### Avklaring — premium-grenser for ny funksjonalitet

- [ ] **Energy profile-innstillingen i Settings er IKKE premium-gatet** (vanlig
  `ListTile`, ingen `PurchaseProvider`-sjekk). Avklar om dette skal være gratis
  eller låst — Meals-fanen (der guiden også tilbys) er allerede gatet via
  `RootScreen`, men en gratisbruker kan nå still nå åpne profilen direkte fra
  Settings og se estimert forbrenning der.
- [ ] Bekreft at mønster- og mikronæringskortene i Insights fortsatt arver
  premium-sjekken i `_StatsTab` (de er lagt til etter early-return for
  `!isPremium`, så de skal være dekket — men verifiser i praksis som
  gratisbruker).
- [ ] Bekreft at Meals-dashboardets FAB (registrering) fortsatt er
  premium-gatet på samme måte som gamle Meals-taben var.

### Kodefiks-kandidat — synk-rekkefølge ved oppstart

- [ ] `main.dart`: `profileProvider.init()` er `unawaited` og kjører parallelt
  med `fastingProvider.init().then(WatchSyncService(...).init())`. Hvis
  `WatchSyncService.init()` broadcaster før profilen er lastet ferdig, sendes
  `dailyBurn: 0` til klokka ved kald oppstart. Sannsynligvis ufarlig (neste
  endring re-broadcaster), men bør verifiseres eller sikres eksplisitt
  (`await profileProvider.init()` før watch-sync starter).

### Wear OS — må testes på ekte klokke

- [ ] Ny "Log meal"-tile: trykk på + åpner talelogging uten omvei via full
  app-UI. `MainActivity`-navigasjonshacket bruker en 300 ms delay
  (`Handler.postDelayed`) før `navChannel.invokeMethod` — juster eller gjør
  robust hvis Flutter-siden ikke alltid har lyttet i tide ved kald oppstart.
- [ ] Talelogging: `speech_to_text` på Wear OS krever systemets
  talegjenkjenning (nettverk/Google-app) — verifiser at det faktisk fungerer
  på klokka som brukes.
- [ ] Sender du et måltid mens telefonen er utilgjengelig, forsvinner det
  (ingen kø i denne versjonen) — "Sent"-bekreftelsen på klokka er optimistisk.
  Vurder om dette må hardnes før lansering eller kan leve som kjent begrensning.
- [ ] Ny `RECORD_AUDIO`-permission i watch-manifestet — sjekk Play Console
  permission-deklarasjon/rationale for denne.
- [ ] Meal AI-status til klokka: bekreft at "Enable meal AI on your phone"
  forsvinner fra tilen så snart modellen er lastet ned (statusen sjekkes nå på
  hver broadcast, ikke bare ved appstart).
- [ ] Tile-fonter (Roboto Flex, dempet skalering på store systemfonter) —
  visuell sjekk på ekte Pixel Watch og på en eldre Wear OS-versjon (fallback
  til standardfont).
- [ ] Programvalg lokalt på klokka (nytt): uten program synket fra telefonen
  viser WatchWorkoutFlow nå en programvelger (bundlede programmer,
  startvekter). Valget lagres i `program_json` på klokka; telefonens
  broadcast overskriver kun når den selv har et program (tom streng
  ignoreres). Test: fersk klokke uten telefonprogram → velg program → logg
  økt → synk til telefon. Merk: telefonens progresjon avanserer bare hvis
  tittelen matcher telefonens neste dag.
- [ ] Train-tilen viser nå "Pick a program" + plussknapp (åpner velgeren på
  klokka) i stedet for "on your phone"-teksten — visuell sjekk på rund skive.

### Telefon — aktiv økt overlever navigasjon (nytt, utestet)

- [ ] Øktstatus ligger nå i TrainingProvider (`active_session` i prefs):
  timer fortsetter etter back-navigasjon, "IN PROGRESS"-kort med
  Resume/Discard på Workout-fanen, gjenoppretting etter prosessdød.
  Test: start økt → back → vent → Resume (timer løper videre) → logg sett →
  drep appen → åpne igjen → Resume → Finish (progresjon oppdateres).
- [ ] Intensitet, sett-endringer og "Add set" persisteres fortløpende —
  verifiser at ingenting mistes ved prosessdød midt i økten.

### Matvaretabellen / næringsinnsikter (beta)

- [ ] Ny `INTERNET`-permission i telefon-manifestet (engangs nedlasting av
  Matvaretabellen) — oppdater Play Data Safety-skjemaet: nettverkskall gjøres,
  men ingen persondata sendes (kun offentlig matvaretabell lastes ned).
  Personvernerklæringen bør nevne dette eksplisitt.
- [ ] Kvaliteten på `MealEstimatorService.extractFoods()` (Nano-ekstraksjon av
  matvarer/gram fra fritekst) er ikke verifisert i praksis — hele
  mikronæringsanalysen står og faller på denne. Test med et par ukers ekte
  logging før "Nutrients · Beta"-seksjonen vises som noe mer enn beta.
- [ ] `MealRecord` fikk nytt felt `foodsJson` (HiveField 7). Bekreft at
  eksisterende installerte brukeres lokale data leses uten krasj (feltet er
  nullable og lagt til sist, skal være trygt, men verifiser på en oppgradert
  installasjon, ikke bare fersk).

### Foto-scanning av måltid (fortsatt spike)

- [ ] Ikke verifisert på fysisk enhet: `ImagePart` i ML Kit GenAI Prompt API.
  Kameraknappen i Meals vises kun når Nano er `available`, men selve
  bilde-til-tekst-kallet (`describeImage`) er utestet i praksis. Kjør spiken
  på en Pixel med multimodal Nano før dette nevnes i butikkoppføringen.

### Butikkoppføring

- [x] ~~Release notes v2.0.0~~ — utkast lagt inn i `store_assets/listing_text.md`
  (2026-07-18).
- [ ] `## Full description` nevner fortsatt "Stats" (nå "Insights") og sier
  ingenting om Energy Profile, talelogging fra klokke eller foto-scan. Må
  oppdateres samtidig som v2.0.0 sendes inn.
- [ ] Nye skjermbilder trengs: Meals-dashboard, Insights (mønster +
  næringskort), Energy profile-guiden, og "Log meal"-tilen på klokka.
- [ ] Bump `version:` i `pubspec.yaml` er gjort (2.0.0) — dobbeltsjekk
  byggnummeret ved faktisk innsending.

## Kritisk — monetisering / paywall (må endres)

- [x] ~~Reverter premium-overstyringen~~ — gjort 2026-07-02, `isPremium => _isPremium`.
- [x] ~~Fjern `// ignore: unused_field`~~ — gjort 2026-07-02.
- [ ] Bekreft at `TESTER_BUILD`-flagget (`kTesterBuild`) **ikke** settes i
  produksjonsbygget — kun i tester-bygg (`build_testers.ps1`).
- [x] ~~Opprett produkt-ID-ene i Play Console~~ — gjort 2026-07-02:
  `healthyfast_yearly` (standardplan `yearly-autorenew`, 200 NOK/år, aktiv) og
  `healthyfast_monthly` (standardplan `monthly-autorenew`, 25 NOK/mnd, aktiv).
  Gammelt abonnement `co.healthyfast` (plan `monthly-payment`, 3 mnd bindingstid
  med avdrag — matchet aldri appkoden) er deaktivert.
- [ ] Verifiser gating-punktene i freemium-modellen etter at premium-
  overstyringen er revertert: Meals-tab, Stats-tab i Journal, Custom fasts
  (begge innganger i home_screen), Install on Watch og Health Connect-bryteren
  i Settings skal alle vise paywall for gratisbrukere. Timer, soner, varsler
  og basis-journal skal være gratis.
- [x] ~~Fjern «LÅS OPP FOR TESTING (BYPASS)»-knappen~~ — gjort 2026-07-02:
  vises nå kun i debug-/tester-bygg (`kDebugMode || kTesterBuild`).
- [ ] Test hele kjøps-/restore-flyten på en ekte enhet med en lukket testkanal.

## Kritisk — varsler

- [x] ~~Fjern hardkodet tidssone~~ — gjort 2026-07-02: `flutter_timezone`
  henter enhetens IANA-tidssone, med Europe/Oslo som fallback ved feil.
- [ ] Verifiser at planlagte varsler faktisk trigger på enhet etter at
  receiverne ble lagt til i manifestet (Bug 1-fiksen). **Krever full rebuild +
  reinstall** — manifest-endringer plukkes ikke opp av hot reload.
- [ ] Play-review: appen bruker nå `SCHEDULE_EXACT_ALARM` (exact alarms med
  fallback til inexact). Vær forberedt på at Google kan be om begrunnelse for
  exact-alarm-bruk i review. Reminder/påminnelse er en gyldig brukssak, men
  hvis det blir avvist: fjern tillatelsen og lev med inexact-forsinkelse.

## Klokke / companion-app

- [ ] Regresjonstest av sync etter Bug 2-fiksen: start faste på telefon, stopp,
  åpne companion-app på klokka og bekreft at gammel faste **ikke** gjenoppstår.
- [ ] Test start/stopp begge veier (telefon→klokke og klokke→telefon) med
  klokka både online og offline.

## Opprydding av testkode

- [x] ~~Fjern DEBUG-seksjonen i `notification_settings_screen.dart` og
  `NotificationService.showNow()`/`testSchedule()`/`debugStatus()`~~ — fjernet
  2026-07-01 etter at varselfeilen ble løst (manglende ProGuard keep-regler for
  flutter_local_notifications/GSON i release-bygg; se `android/app/proguard-rules.pro`.
  Reglene MÅ beholdes, ellers slutter planlagte varsler å vises igjen).

## Reklame (AdMob)

- [ ] Per `PROJECT_NOTES.md` er `google_mobile_ads` midlertidig fjernet pga.
  Gradle 9-inkompatibilitet, og `AdBannerWidget` returnerer
  `SizedBox.shrink()`. Avklar forretningsmodell: hvis ads skal med, finn en
  Gradle-9-kompatibel versjon eller nedgrader til Gradle 8.7.

## Play Store-klargjøring

- [ ] Signeringsnøkkel: bekreft at `android/key.properties` peker på riktig
  release-keystore (ikke debug). Ikke sjekk inn passord/keystore i git.
- [ ] Butikkoppføring: tittel, beskrivelse, skjermbilder, feature-grafikk
  (se `store_assets/`).
- [ ] Personvernerklæring publisert og lenket — kreves spesielt pga.
  Health Connect (`WRITE_NUTRITION`) og IAP.
- [ ] Health Connect: bekreft permissions-rationale og data-bruk er korrekt
  beskrevet i butikkoppføringen.
- [ ] Bump `version:` i `pubspec.yaml` til riktig release-versjon.
- [ ] Kjør `flutter analyze` (forventet: rent) og en full `flutter build appbundle`.

## Wear OS — retting etter avvisning (2026-07-07)

Google avviste watch-bygget på fire punkter. Endringer gjort i koden:

- [x] **Branded splash** — watch-flavoren har nå `launch_background.xml`
  (drawable + drawable-v21) med 48dp app-ikon sentrert på svart, pluss svart
  `styles.xml`. `splash_icon.png` regenerert til 144px for skarp gjengivelse.
- [x] **Tekst kuttes / rullefelt mangler** — alle watch-skjermer bruker nå
  `WearScrollView` (Scrollbar med `thumbVisibility` + scrollbar/rotasjon).
  `_IdleView` og `_EditStartScreen` er scrollbare og sentrerte, tekst wrapper.
- [x] **Ongoing Activity** — `FastingOngoingNotifier` poster et vanlig
  ongoing-varsel (selvoppdaterende kronometer via `Status.StopwatchPart` +
  `androidx.wear:wear-ongoing`) som vises på urskive/Recents. **Ingen
  foreground-service** — dermed ingen `FOREGROUND_SERVICE_SPECIAL_USE` og
  ingen Play-granskning av FGS. Startes/stoppes fra `fasting_provider` via
  `healthyfast/wear` (`startOngoing`/`stopOngoing`), gated på `FEATURE_WATCH`.
- [x] **Tile** — `FastingTileService` (tiles + protolayout) refererer aktiv
  faste og åpner appen ved trykk.
- [x] ~~**Bruker-toggle** — `watch_ongoing_enabled` (default på), styres fra
  ny `WatchSettingsScreen` (gear på idle-view).~~ **REVERTERT 2026-07-07 i
  runde 2** — Google avviste nettopp denne togglen (indikatoren er påkrevd og
  kan ikke være valgfri). Se seksjonen under.
- [x] **Play-beskrivelse** — `store_assets/listing_text.md` omtaler nå
  eksplisitt tile, komplikasjoner og ongoing activity.

Gjenstår før resubmit (må gjøres manuelt / på enhet):

- [ ] **Bygg + test på Wear-enhet/emulator (API 30+ og en round 1.2"-enhet):**
  - `flutter build appbundle --flavor watch` (og `--flavor phone` for telefon).
  - Verifiser: branded splash (svart + ikon), ingen avkuttet tekst ved
    **største** systemfont, synlig rullefelt + rotasjonshjul-scroll.
  - Start faste → sjekk ongoing-indikator på urskive + riktig brikke i Recents.
  - Legg til tile i karusellen → viser aktiv faste, åpner app ved trykk.
  - Skru av toggle i Settings → indikator forsvinner; på igjen → kommer tilbake.
- [ ] **Oppdater selve Play Console-oppføringen** (ikke bare `listing_text.md`)
  med den nye Wear-beskrivelsen + oppdaterte watch-skjermbilder.
- [ ] **Verifiser bibliotekversjoner** ved bygg: `wear-ongoing:1.0.0`,
  `wear.tiles:tiles:1.4.1`, `protolayout*:1.2.1`. Juster hvis Gradle klager.

## Wear OS — retting etter avvisning nr. 2 (2026-07-07, 5 punkter)

Google avviste oppdateringen på nytt 7. juli 2026. Rotårsaker funnet og fikset:

- [x] **Manglende pågående aktivitet** — to rotårsaker:
  1. `POST_NOTIFICATIONS` ble aldri forespurt på klokka (kun telefon-stien via
     `RootScreen` ba om den), så ongoing-varselet ble stille droppet på
     Wear OS 4+. Fikset: `WatchScreen` er nå stateful og ber om tillatelsen
     ved oppstart (`NotificationService.requestNotificationsPermission()`,
     ny lettvekts-metode uten exact-alarm-skjermen), og re-poster indikatoren
     hvis en faste allerede kjører.
  2. Bruker-togglen lot indikatoren skrus av — direkte brudd på retningslinjen
     (Googles bevis-skjermdump viste togglen). Fikset: `watch_settings_screen.dart`
     slettet, Settings-knappen fjernet fra idle-view, all `isEnabled`-gating
     fjernet fra `OngoingActivityService`. Indikatoren vises nå alltid under
     aktiv faste.
- [x] **Klokkeformer (avkuttet tekst på rund skjerm)** — beviset viste
  «day 00:50» kuttet øverst i `_EditStartScreen`. Fikset: `WearScrollView`
  utvider nå all padding til en form-sikker inset (min. 10 % horisontalt /
  15 % vertikalt av korteste side) så innhold aldri havner i de klipte
  hjørnene. Gjelder alle skjermer. Fasteskjermen (ringen) bruker
  `shapeSafe: false` med egne innmarger (ringen skal følge kanten).
- [x] **Skriftstørrelse** — `_FastingView` låste høyden til `ringSize`; ved
  stor systemskrift vokste innholdet ut av boksen. Fikset: `ConstrainedBox`
  med `minHeight` i stedet for fast `SizedBox`-høyde, så kolonnen vokser og
  skyver innhold nedover (scrollbart) i stedet for å kuttes. Tekst/kontroller
  i ringen har fått egen padding (10 % horisontalt) som gir plass til
  Stop-raden også ved store fonter.
- [x] **Funksjonalitet ikke som beskrevet** — samme rotårsak som
  skriftstørrelse-punktet («tekst blir ikke avkuttet ved stor skrift»);
  dekket av fiksen over.
- [ ] **Wear-skjermdumper (Play Console, manuelt)** — skjermdumpene i
  oppføringen har transparent bakgrunn/rund maskering (beviset viste den
  runde, maskerte fasteskjermen). Krav: ta nye skjermdumper som er
  **firkantede, uten transparens og uten maskering** (ta rå emulator-/
  enhetsdumper på svart bakgrunn, ikke legg på rund ramme). Last opp under
  «Wear OS»-skjermdumper i butikkoppføringen.

Oppfølging 2026-07-08 etter test på emulator (chip vistes fortsatt ikke):

- [x] **Ongoing Activity — to reelle bugs funnet:** status-malen manglet
  avsluttende `#` (`"Fasting #time"` → `"Fasting #time#"`) og kastet exception
  FØR notify() — stille svelget av Flutter-sidens `catch (_)`, så varselet ble
  aldri postet. I tillegg var varselikonet fullfarge-launcher-PNG (byttet til
  monokrom vektor `ic_stat_fasting`). Løsningen er fortsatt et vanlig
  ongoing-varsel **uten** foreground service (API-et krever ikke FGS;
  codelabens FGS finnes fordi den appen gjør reelt bakgrunnsarbeid).
- [ ] **Verifiser chip på urskiven uten FGS.** Hvis den fortsatt uteblir på
  målenhetene: `FastingForegroundService` ligger klar som fallback —
  kommenter inn manifest-blokkene i watch/AndroidManifest.xml, bytt
  MainActivity til `FastingForegroundService.start/stop`, og fyll ut
  specialUse-deklarasjonen i Play Console (App content → Foreground service).
- [x] **Venstreskyvning på sentrerte skjermer** — `SingleChildScrollView`
  topp-venstre-justerte en Column som krympet til bredeste barn. Fikset med
  `minWidth` i ConstrainedBox. (Synlig i Googles egen bevis-skjermdump.)
- [x] **Edit-skjerm redesignet** — blyanten åpner nå «Adjust fast» med
  Start time (dag-chevrons + time/minutt-hjul, aldri frem i tid) og Goal
  (protokollvelger via `updateGoalDuringFast`) — som telefonappen.
  -1h/-15m-stepperen er fjernet.
- [x] **Rotary/krone-scrolling** — `wearable_rotary`-plugin +
  `onGenericMotionEvent` i MainActivity + `RotaryScrollController` i
  `WearScrollView`. Krever `flutter pub get`.
- [x] **Buet posisjonsindikator** — Material Scrollbar byttet ut med
  Wear-stil 60°-bue ved klokken 3; fremdriftsringen krympet så de ikke
  kolliderer.

Resubmit-prosedyre (fra Googles veiledning):

- [ ] Bygg ny AAB med **høyere versionCode** (bump `version:` i
  `pubspec.yaml`), `flutter build appbundle --flavor watch`.
- [ ] Test på rund emulator/enhet med **største systemfont**: ingen avkuttet
  tekst på idle-, picker-, edit-start- og fasteskjermen; ongoing-indikator
  vises på urskive/Recents/Tile uten toggle.
- [ ] Last opp ny AAB til samme spor, sørg for at den avviste versjonen
  ligger under «Ikke inkludert», bytt skjermdumpene, og send inn på nytt.
  Oppdater også eventuelle test-spor med samme fiks.

## Sikkerhet

- [ ] Ingen hemmeligheter (API-nøkler, keystore-passord) i versjonskontroll.
- [ ] Verifiser at `key.properties` og keystore er i `.gitignore`.

## Vedlikehold — firebase-functions SDK (logget 2026-08-06, ikke akutt)

- [ ] Oppgrader `firebase-functions` i `functions/package.json` fra `^4.5.0`
  (faktisk installert: 4.9.0) til nyeste (7.3.2 pr. 2026-08-06). Firebase CLI
  advarer selv ved hver deploy om at oppgraderingen har breaking changes.
  **Ikke** en rask side-fiks — gjør som egen økt:
  - `generateAiText` er deployet som **1st Gen**-funksjon med v1-API-et
    (`functions.https.onCall`, `functions.runWith`). Nyere versjoner dytter mot
    2nd Gen (`firebase-functions/v2/https`) — vurder å migrere samtidig.
  - Kjent GitHub-issue (firebase/firebase-functions#1622): v1-navnerommet
    (`functions.auth.user()`) brytes ved v6-oppgradering. Treffer ikke
    HealthyFast direkte (ingen auth-triggere i bruk), men indikerer at
    v1-API-overflaten ikke er trygg å anta uendret — les changelog for v5/v6/v7
    før oppgradering.
  - Test med `firebase emulators:start --only functions` før `firebase deploy`.
  - Fungerer fint på 4.9.0 i dag — ingen hastesak, bare ikke la den bli
    glemt på ubestemt tid.
