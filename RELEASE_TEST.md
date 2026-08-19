# HealthyFast — testrunde før opplasting til Play

Opprettet 2026-08-02, for utgaven som skal erstatte `2020 (2.0.0)` i produksjon.

Poenget med denne lista: **de fleste feilene under er usynlige i debug.** De
oppstår kun i signerte release-bygg (R8 minifiserer bort klasser) eller kun i
Play-distribuerte bygg (Play signerer om appen med en annen nøkkel). Å teste
med `flutter run` fanger ingen av dem.

Bygg med `.\build_production.ps1` (setter ikke `TESTER_BUILD`, så
betalingsmuren er ekte) og installer `.aab`-en via internt testspor — ikke
sidelast, siden flere av punktene i del B krever Play-signering.

---

## A. R8-risiko — må testes i signert release-bygg

`android.enableR8.fullMode=true` er på. Full mode har allerede knekt ML Kit én
gang i dette prosjektet (2026-07-02, Pixel 10 Pro). Keep-reglene i
`proguard-rules.pro` er skrevet for å dekke det, men kombinasjonen er så vidt
notatene viser ikke verifisert på enhet etterpå.

- [ ] **Meal AI / Gemini Nano.** Åpne måltidslogging → beskriv et måltid med
  tekst → få kalorier/makroer tilbake. Så: fotografer en tallerken → samme.
  Feilmodus å se etter: `Generation.getClient()` kaster NullPointerException,
  eller status faller til `unavailable` selv om modellen er lastet ned.
  *Ekstra viktig nå:* onboarding trigger nedlastingen aktivt, så en ødelagt
  ML Kit i release treffer hver eneste nye bruker på første kjøring.
- [ ] **Planlagte varsler.** Slå på daglig påminnelse, sett tidspunkt 2–3 min
  fram, lukk appen helt, vent. Feilmodus: alarmen fyrer, men *ingen* varsel
  vises (GSON-deserialisering strippet bort). Umiddelbare varsler rammes
  ikke — de er ikke en gyldig test.
- [ ] **Sonevarsler under faste.** Start en faste, sjekk at
  milepælsvarslene faktisk kommer. Samme GSON-sti som over.
- [ ] **Health Connect.** Logg et måltid og en treningsøkt → bekreft at de
  dukker opp i Health Connect. Så import den andre veien.
  `connect-client` er refleksjonstung og har ingen keep-regler i dag.
- [ ] **Firebase / cloud backup.** Logg inn med Google → "Back up now" →
  "Restore from cloud". Firestore- og Auth-klassene har heller ingen
  eksplisitte keep-regler.

Slår noe av dette feil: legg til keep-regler for den aktuelle pakken framfor
å skru av full mode — full mode er det Play anbefaler.

---

## B. Krever Play-signering — virker lokalt, feiler i produksjon

- [ ] **Play App Signing SHA-1 + SHA-256 inn i Firebase Console.**
  Dette står fortsatt åpent i `PROJECT_NOTES.md`. Play signerer appen om med
  sin egen nøkkel, så Google-innlogging som virker med upload-nøkkelen din
  **vil feile for ekte brukere** til Play-sertifikatets SHA er lagt inn.
  Finnes under *Test og publiser → Oppsett → Appsignering*.
  Konsekvens hvis glemt: cloud backup er dødt for alle betalende brukere.
- [ ] **Firestore Database opprettet + sikkerhetsregler publisert.**
  Også åpen i notatene. Uten reglene (`users/{uid}/{col}/{doc}`, kun eier)
  feiler backup/restore med permission-feil selv når innlogging virker.
  Eksakt regeltekst ligger i `CLOUD_SYNC_PLAN.md`.
- [ ] **Kjøp.** Test årlig og månedlig abonnement som lisenstester fra
  internt spor. Bekreft at `debugUnlock`-knappen **ikke** vises (den er
  no-op uten `TESTER_BUILD`, men bekreft at knappen er borte visuelt).
- [ ] **Restore purchases** på en ny enhet med samme konto.

---

## C. Nytt i denne runden — førstegangsopplevelsen

- [ ] **Fersk installasjon** (avinstaller først, ikke bare tøm data):
  velkomstskjerm → målvalg → 9 steg → planoppsummering → app.
  Sjekk at ringanimasjonen går rundt og at teksten ikke overflyter på en
  liten skjerm.
- [ ] **Oppgraderingsstien — viktigst.** Installer den *gamle* produksjons-
  utgaven, logg en faste, oppgrader til det nye bygget. Brukeren skal
  **ikke** se velkomstflyten. (Beskyttelsen leser `profile_age` i
  SharedPreferences og `fasts`-boksen i Hive.) Slår denne feil, blir hver
  eksisterende bruker kastet inn i en 9-stegs veiviser ved oppdatering.
- [ ] **Påminnelsessteget** → "Ja" → OS-dialogen for varsler skal komme mens
  det steget fortsatt er på skjermen. Deretter kobling mot punkt A2.
- [ ] **AI-steget** → "Last ned nå" → gå videre med én gang. Nedlastingen
  skal fortsette i bakgrunnen, og appen skal ikke henge. Kom tilbake via
  Innstillinger → Cloud & AI og bekreft at modellen faktisk ble installert.
- [ ] **AI-steget på en telefon uten Nano-støtte** → skal vise
  forklaringsboksen og kun tilby sky-AI.
- [ ] **Sky-AI fra onboarding** → samtykkearket skal åpne seg, og "Ikke nå"
  skal ikke skru på noe.
- [ ] **Innstillinger → "Kjør hele oppsettsguiden på nytt"** → full flyt,
  og den skal poppe tilbake til innstillinger (ikke til hjemskjermen).
- [ ] **Hopp over**-knappen på velkomstskjermen → rett inn i appen, og
  flyten skal ikke dukke opp igjen ved neste oppstart.

---

## D. Øvrige endringer denne runden

- [ ] **Øvelsesvelger:** "Legg til øvelse" åpner med lista synlig og tomt
  navnefelt. Lagre-knappen skal være grå til noe er valgt. Rediger en
  eksisterende øvelse → lista skal være sammenslått, navnet fylt ut.
- [ ] **Workout-programmer:** "My programs" er første fane. Tom tilstand
  viser ikon, tekst og to knapper. Eksisterende egendefinerte programmer
  skal fortsatt ligge der (lagringsnøkkelen `Custom` er uendret — hvis de er
  borte, er dette en datamigreringsfeil og en stopper).
- [ ] **Send tilbakemelding** i Innstillinger → åpner e-postappen med
  versjonsnummer i meldingsteksten. Testes i release-bygg: den nye
  `mailto`-oppføringen i manifestet er det som avgjør om Android finner
  e-postappen i det hele tatt.
- [ ] **Betalingsmuren:** funksjonene skal listes i riktig rekkefølge etter
  valgt mål (velg "Bygg styrke" i onboarding → trening skal ligge øverst).

---

## E. Play Console — før innsending

- [ ] `flutter analyze` uten feil (bygget stoppet sist på nettopp dette).
- [ ] **Edge-to-edge** visuelt sjekket på Android 15 eller 16: ingen tekst
  under statuslinja eller navigasjonslinja, spesielt på hjem, journal og
  under aktiv økt.
- [ ] **Heldekkende-varselet:** ikke bruk tid på det. Det kommer fra
  Flutter-motoren, ikke fra din kode, og Flutter har lukket saken som
  dokumentert oppførsel — en nyere Flutter fjerner det ikke. Bakgrunn i
  `PLAY_CONSOLE_WARNINGS.md`.
- [ ] **Datasikkerhet-skjemaet** oppdatert: Health Connect, on-device AI,
  valgfri sky-AI (tekst sendes til Google), Firebase Auth/Firestore, kjøp.
- [ ] **Health Connect-erklæring** sendt inn — de åtte helsetillatelsene i
  manifestet krever eget bruksområdeskjema, og dette er den vanligste
  årsaken til at en innsending blir liggende.
- [ ] **Personvernerklæringen** nevner sky-AI og Firebase (må stemme med
  datasikkerhet-skjemaet).
- [ ] **Wear OS-bygget** lastet opp med riktig versjonskode (phone × 10,
  watch × 10 + 1 — håndteres av gradle-flavorene).

---

## F. Play Console-endringene (2026-08-05) — regresjonstest

Bakgrunn og bevisføring: `PLAY_CONSOLE_WARNINGS.md`. Tre endringer ble gjort.
Ingen av dem er ment å endre oppførsel — **hele poenget med denne seksjonen er
å bekrefte at ingenting ble verre.** Går alt grønt, er runden vellykket selv
om varslene i Console fortsatt står.

### F0. Verifiser bygget før du installerer

Kjør etter `.\build_production.ps1`, før du laster opp. Bekrefter at
avhengigheten faktisk løste seg og at R8 fortsatt kjører i full mode:

```powershell
cd android
.\gradlew :app:dependencies --configuration phoneReleaseRuntimeClasspath | Select-String "androidx.activity"
```

- [ ] Løser til **1.11.0 eller høyere**. Ser du fortsatt 1.9.0, har en annen
  avhengighet låst versjonen, og resten av F2 er meningsløs.
- [ ] `build/app/outputs/mapping/phoneRelease/mapping.txt` finnes og er stor
  (titalls MB). Mangler den, kjørte ikke R8, og **hele del A må tas på nytt.**

### F1. App-bar-ikonet — `cacheWidth`/`cacheHeight`

Ikonet dekodes nå i skjermens fysiske pikselstørrelse i stedet for 512×512.
Feilmodus er visuell, ikke en krasj: for lav cache-verdi gir uskarpt ikon.

- [ ] Ikonet oppe til venstre er **skarpt, ikke grøtete**, på hjem, journal,
  måltider og trening. Sammenlign gjerne med et skjermbilde fra forrige
  bygg — forskjellen skal være null.
- [ ] Sjekk på telefonen med høyest oppløsning du har. Feilen, hvis den
  finnes, viser seg først der.
- [ ] Mørk modus også — ikonet ligger i en `ClipRRect` med avrundede hjørner,
  og kantene er det første som blir stygt ved feil skalering.

### F2. `activity-ktx` 1.9.0 → 1.11.0

Størst risiko i runden. Bumpen drar sannsynligvis med seg nyere `core`,
`fragment` og `lifecycle` transitivt. Alt som går via *activity result* er
eksponert — og det er mye i denne appen.

- [ ] **Appen starter i det hele tatt.** `FlutterFragmentActivity` arver fra
  `fragment`, som nå kan være en annen versjon. Krasjer den, krasjer den ved
  oppstart, ikke subtilt.
- [ ] **Health Connect-tillatelser.** Innstillinger → koble til Health
  Connect → OS-dialogen skal komme opp og svaret skal komme tilbake i appen.
  Dette går gjennom `ActivityResultContracts`.
- [ ] **Google-innlogging** (cloud backup). Credential Manager bruker samme
  mekanisme. Test både innlogging og utlogging.
- [ ] **Kamera / bildevelger** i måltidslogging → bildet skal komme tilbake
  og AI-estimatet skal kjøre.
- [ ] **Varselstillatelse** (fersk installasjon, Android 13+) → dialogen skal
  komme under påminnelsessteget, jf. C.
- [ ] **Heldekkende visuelt på Android 15 eller 16.** Dette er den endringen
  bumpen faktisk gjør: systemet styrer nå bar-fargene i stedet for androidx.
  Se etter statuslinje eller navigasjonslinje som plutselig har fått feil
  farge eller kontrast — spesielt overgangen lys/mørk modus.
- [ ] **Wear OS-bygget starter.** `MainActivity` deles mellom flavorene, og
  `enableEdgeToEdge()` er gated på `!isWatch()`. Klokka skal være uendret,
  men bekreft at appen i det hele tatt åpner.

### F3. Eksplisitt `isMinifyEnabled` / `isShrinkResources`

Skal være en no-op — begge kjørte allerede. Men *hvis* ressursshrinking ikke
var på før, slår den på nå, og da kan ressurser bli strippet. Feilmodusen er
manglende grafikk, ikke krasj.

- [ ] **Varselikonet vises** i statuslinja og i varselet selv (ikke en tom
  firkant). Dekkes av A2, men se spesifikt etter ikonet denne gangen.
- [ ] **Google-innloggingsknappen** har logo og bakgrunn.
- [ ] **Launcher-ikonet** på hjemskjermen er intakt etter installasjon.

Jeg sjekket at ingen Kotlin-kode bruker `getIdentifier()`, så det finnes
ingen ressurser som kun slås opp på navn og kan forsvinne usett. Punktene
over er likevel billige å ta.

### F4. Etter opplasting

- [ ] Noter i `PLAY_CONSOLE_WARNINGS.md` hvilke av de fire varslene som
  fortsatt står på den nye utgaven. Forventningen er **alle fire**. Blir noen
  borte, er det ny informasjon om hva Play faktisk måler, og verdt å skrive
  ned.

---

## Kjent risiko som ikke blokkerer

- Sender du et måltid fra klokka mens telefonen er utilgjengelig, forsvinner
  det — "Sent"-bekreftelsen på klokka er optimistisk. Ingen kø i denne
  versjonen.
- Velkomstflyten er 9 steg. Føles den lang i praksis, er kroppstype-steget
  (steg 7) det jeg ville kuttet — det justerer kun TDEE med ±6,5 %.
