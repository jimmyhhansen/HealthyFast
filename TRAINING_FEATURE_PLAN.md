# HealthyFast — Plan: Train-fane (styrketrening)

Skrevet 2026-07-18. Robust plan for en fjerde fane med styrketrening:
øktlogging, programforslag med veiledning, Wear-tile, Journal-integrasjon
og Health Connect begge veier. **Ikke bygget ennå.**

Fanerekkefølge: **Fast · Meals · Train · Journal** — Journal holdes helt
til høyre. (Settings ligger allerede som tannhjul i AppBar, så bunn-nav
har plass til fire.)

---

## 1. Datamodell (Hive, følger etablerte mønstre i appen)

**WorkoutRecord** (typeId 3, håndskrevet adapter som for WeightRecord):

| Felt | Type | Kommentar |
|---|---|---|
| startTime / endTime | DateTime | varighet avledes |
| title | String | "Push day", "5x5 A", eller fritekst |
| exercisesJson | String? | JSON, samme mønster som `foodsJson` på MealRecord |
| programId / programDayIdx | String? / int? | null ved quick-log |
| source | String | manual / watch / health |

`exercisesJson`-format:
```json
[{"n": "Bench press", "sets": [{"kg": 80, "reps": 5}, {"kg": 80, "reps": 5}]}]
```
Nested Hive-objekter unngås bevisst — JSON-string-mønsteret er allerede
bevist i kodebasen og krever ingen nye adaptere ved formatendringer.

**ProgramState** (SharedPreferences, ikke Hive): valgt programId, hvor i
syklusen brukeren er (dag-indeks), gjeldende arbeidsvekter per øvelse,
antall feilede forsøk per øvelse (for deload).

**Øvelseskatalog + programdefinisjoner**: bundlede JSON-assets
(`assets/exercises.json`, `assets/programs.json`) — ingen nettavhengighet,
enkelt å oversette/utvide. Katalog: ~40 øvelser med muskelgruppe og 2–3
tekstlige form-cues hver.

## 2. Programinnhold og kilder

Etablerte, veldokumenterte programmer med innebygd progresjon — ikke
egenkomponerte:

**3 dager/uke (nybegynner, anbefalt standard):**
- **StrongLifts 5x5** — A/B-veksling (Squat/Bench/Row vs Squat/OHP/
  Deadlift), 5×5, +2,5 kg per fullført økt, deload −10 % etter 3 feilede.
  Kilde: stronglifts.com (Mehdi Hadim).
- **GZCLP** (alternativ med mer variasjon) — T1/T2/T3-struktur med
  eksplisitte progresjons- og resettregler. Kilde: Cody Lefever (GZCL),
  r/Fitness-wikien.

**5 dager/uke (viderekommen):**
- **Reddit PPL** (Metallicadpa) — Push/Pull/Legs ×5–6, lineær progresjon
  på hovedløft. Kilde: r/Fitness-wikien (dokumentert og kvalitetssikret
  av et stort miljø).
- **5/3/1 for Beginners** (4 dager, nevnes som alternativ) — prosentbasert
  på treningsmaks, innebygde deloads. Kilde: Jim Wendler.

**Veiledning i appen:** per øvelse: form-cues som tekst + "hvorfor"-linje
(samme tone som sonetipsene på Fast-siden). Ingen innebygde videoer
(rettigheter/vedlikehold) — ev. "Search form video"-lenke som åpner
YouTube-søk eksternt. **Disclaimer** kreves (som fastedisclaimeren i
butikkteksten): ikke medisinsk råd, tilpass belastning, søk kyndig hjelp
ved smerte.

**Program-onboarding:** gjenbruk wizard-mønsteret fra energiprofilen
("1 of 4"): dager/uke → erfaring → utstyr (stang/manualer/maskiner) →
anbefalt program med begrunnelse. Startvekter: spør om 5RM eller start
tomt/lett (StrongLifts-tilnærmingen).

## 3. UI — Train-fanen

**Dashboard** (mønster fra Meals-dashboardet):
- "Next workout"-kort øverst: programnavn, dag (f.eks. "Workout A"),
  øvelsene med planlagte vekter. Stor Start-knapp.
- Ukesoversikt: økter gjennomført denne uka (mål fra programmet).
- Siste økter-liste (tittel · varighet · totalvolum kg).
- FAB (+): "Start next workout" / "Quick log" (fritekst + varighet, for
  økter utenfor program).

**Øktlogger** (kjerneskjermen):
- Én øvelse om gangen eller scrollbar liste; per sett: reps-teller og
  kg-stepper, forhåndsutfylt fra programstate, forrige økts tall som
  ghost-tekst.
- Hviletimer som starter automatisk når et sett hukes av (3 min for
  5x5-hovedløft, konfigurerbart).
- Fullfør økt → WorkoutRecord lagres, programstate oppdateres (+2,5 kg
  ved suksess, feiltelling/deload ellers), Health-eksport fyres.

## 4. Journal-integrasjon

- Dagvisningen får **Workouts**-seksjon (tittel, varighet, volum,
  øvelsesliste) med redigering, mellom Fasts og Meals.
- Pluss-menyen i Journal får fjerde valg: **Log a workout** på valgt dag
  (retrospektivt, samme mønster som Log a fast).
- Insights: fjerde toppfane **Training** — volum (kg) og økter per
  dag/uke/måned via eksisterende `_PeriodBarChart` + PR-liste. (Fase 4.)

## 5. Wear OS — Train-tile + øktlogging på klokka

- **Egen tile** (tredje): "Next: Workout A" + grønn pille med ukens
  fremdrift ("2 of 3 this week") + pluss/Start-knapp. Data via prefs som
  meal-tilen (`flutter.next_workout`, `flutter.week_done` osv.).
- Start fra tilen → øktskjerm på klokka: dagens øvelser som liste, hak
  av sett med kg/reps-steppere (forhåndsutfylt), WearScrollView +
  FittedBox-regime for store fonter (etablerte læringer).
- **Synk klokke→telefon:** generaliser `MealSyncQueue` →
  `WatchSyncQueue` med `type`-felt (meal/workout) — samme id + ack +
  context-persistens, bevist robust.
- Talefallback (fase 3+): "benkpress tre sett åtte reps åtti kilo" →
  Nano-parsing på telefonen (samme mønster som måltidsestimering).

## 6. Health Connect begge veier

- **Eksport:** `HealthDataType.WORKOUT` med
  `HealthWorkoutActivityType.STRENGTH_TRAINING` (health-pluginen støtter
  writeWorkoutData med aktivitetstype, start/slutt, tittel). Manifest:
  `WRITE_EXERCISE`.
- **Import (fetch-knappen):** utvid eksisterende "Fetch from Health
  Connect" til også å lese WORKOUT (siste 30 dager), filter på
  styrke-/vekttreningstyper, dedupe ±2 min mot eksisterende (samme
  mønster som meals/weight). Manifest: `READ_EXERCISE`.
- **Kjent begrensning:** HC-standarden via pluginen bærer ikke sett/reps
  (ExerciseSegment-støtten er mangelfull) — importerte økter blir "økt
  uten detaljer" (tittel + varighet), og eksporterte økter mister
  settdetaljer i HC. Detaljene bor i appen; HC får sammendraget.
  Dokumenter dette i UI ("Details stay in HealthyFast").

## 7. Premium-grense (beslutningspunkt)

Anbefaling: quick-log gratis (lav terskel, mater Journal), **programmer +
progresjon + Wear-økter = premium** — det er der den reelle verdien og
vedlikeholdskostnaden ligger. Konsistent med Meals-gatingen.

## 8. Faser

1. **Grunnmur:** WorkoutRecord + Train-fane med quick-log + Journal-
   seksjon + pluss-valg + Health eksport/import. (Størst verdi/kost.)
2. **Programmer:** assets, onboarding-wizard, øktlogger med progresjon
   og hviletimer, veiledningstekster. StrongLifts 5x5 først, så PPL.
3. **Wear:** Train-tile + øktlogging på klokka + generalisert synk-kø.
4. **Innsikt:** Training-fane i Insights, PR-sporing, deload-varsler,
   talelogging.

## 9. Risiko / må avklares

- HC exercise-detaljer (pkt. 6) — sett forventning i UI.
- Programinnhold: hold deg tett til kildene, ikke improviser vekter/
  volum; disclaimer i app og butikktekst.
- Play-review: treningsveiledning er ok, men unngå helsepåstander
  ("bygger muskler raskt" o.l.) i butikkteksten.
- Fanen gjør appen bredere enn "fasting tracker" — vurder ny
  butikk-kategorisering/beskrivelse ved lansering (2.1 eller 3.0).
- `_MonthGrid`-heatmapen i Journal er fastetimer-basert — trening bør
  ikke blandes inn der (egen markør-prikk kan vurderes).
