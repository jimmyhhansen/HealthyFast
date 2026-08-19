# Play Console — de fire «anbefales»-varslene på 2210 (2.0.0)

Undersøkt 2026-08-05. Alle fire står som **anbefalinger**, ikke blokkere.
Ingen av dem hindrer utgivelse.

Konklusjonen opp front, fordi den er kontraintuitiv: **tre av fire kan ikke
fikses fra appkoden.** Kallene Play flagger ligger i Flutter-motoren og i
Google-biblioteker. Den ene som er din egen kode gjør allerede det riktige.

Dette dokumentet finnes for at undersøkelsen ikke skal gjøres om igjen ved
neste utgave. Sjekk «Når skal dette vurderes på nytt» nederst.

---

## Handlingsplan (lagt til 2026-08-05, etter undersøkelsen)

**Utgangspunkt: endringene under «Hva som faktisk ble endret» er ikke sendt
ut ennå.** `pubspec.yaml` står på `version: 2.0.0+221`, og phone-versionCode
er `flutter.versionCode * 10` = **2210** — nøyaktig utgaven Play advarer om.
Advarslene du ser gjelder altså en bundle bygget *før* `activity-ktx` ble
løftet til 1.11.0. Ingen av dem har blitt testet mot den nye koden.

Det gir én reell handling og tre ikke-handlinger.

### Steg 1 — Send ut det som allerede er fikset

Bump build-nummer og bygg begge flavorene på nytt:

```
pubspec.yaml:  version: 2.0.0+222      # phone 2220, watch 2221
.\build_production.ps1
```

Dette er den eneste måten å måle effekten av `activity-ktx` 1.11.0. Forventet
utfall, basert på bundle-analysen:

| Varsel | Forventning etter 2220 | Sikkerhet |
|---|---|---|
| 1 + 2 heldekkende | står fortsatt (Flutter-motoren kaller dem) | høy |
| 3 punktgrafikk | står fortsatt (bibliotekkode) | høy |
| 4 R8 | bør forsvinne — men gjorde det ikke på 2210 med samme R8-oppsett | lav |

Varsel 4 er det eneste som kan bevege seg. Står det fortsatt på 2220, er det
Play-side støy, og du har `~~R8{"r8-mode":"full"}`-markøren som bevis.

### Steg 2 — Verifiser mot den nye bundlen, ikke mot Play

Etter bygg, før opplasting:

```bash
unzip -q build/app/outputs/bundle/phoneRelease/*.aab -d /tmp/aab
strings /tmp/aab/base/dex/*.dex | grep -c setNavigationBarDividerColor
```

Går treffene ned mot null i `classes.dex` (androidx-halvparten), virket
oppgraderingen — uavhengig av hva Play sier. Blir de stående, er
`activity-ktx` 1.11.0 ikke det som trekkes inn, og da er *det* feilen å jakte
på, ikke varselet.

### Steg 3 — Ikke gjør (begrunnet i seksjonene under)

- **Ikke oppgrader Flutter for å fjerne varsel 1 og 2.** Oppstrømssaken er
  lukket som dokumentert oppførsel. Fiksen kommer ikke.
- **Ikke snevre inn keep-regelen for `flutter_local_notifications`.** Gevinst
  ≈ null, risiko = stille feilende varsler. Dokumentert regresjon.
- **Ikke rør `MealEstimator`.** Den gjør allerede nedskalering riktig.

`flutter_local_notifications` står på `^22.2.0`, altså allerede en fersk
versjon. Sjekk endringsloggen for «bitmap»/«downsample» ved neste
`flutter pub outdated` — det er den ene av de fire som kan lukke seg selv.

### Resultat av steg 1 og 2 (målt 2026-08-06 på 2.0.0+223)

Bygget er verifisert. **Oppgraderingen virket, men varselet forsvinner ikke —
og nå vet vi hvorfor det aldri kunne ha gjort det.**

`activity-ktx` 1.11.0 er inne: `EdgeToEdgeApi35` finnes i `mapping.txt`, og
den klassen eksisterer ikke før 1.10.0. Men R8 beholder samtidig
`EdgeToEdgeApi26`, `Api28`, `Api29` og `Api30`. Årsak: `minSdk = 26` gjør at
impl velges på `SDK_INT` ved kjøretid, og R8 kan ikke bevise at de gamle
grenene er døde. Det er nettopp de gamle impl-ene som kaller
`setStatusBarColor` / `setNavigationBarColor`.

**Forventningen i tabellen over var altså feil.** androidx-halvparten kan
ikke fjernes så lenge appen støtter API 26. Det er ikke en versjonssak.

`setDecorFitsSystemWindows`-treffene kommer dessuten fra
`androidx.core.view.WindowCompat`, et helt annet bibliotek — aldri berørt av
activity-oppgraderingen.

R8-status er ren: `"r8-mode":"full"` i alle dex, `mapping.txt` og
`resources.txt` skrevet.

Merk: `pg-map-id` er `e9c79ca`, identisk med det som ble notert for 2210. Det
tyder på at 2210 allerede hadde activity 1.11.0, og at «før»-målingen i
dokumentet ble tatt etter oppgraderingen. Konklusjonen endres ikke, men det
betyr at oppgraderingen sannsynligvis aldri var variabelen som ble testet.

### Realistisk sluttilstand

Tre av fire varsler blir sannsynligvis stående permanent. Alle fire er
**anbefalinger** — de påvirker ikke utgivelse, rangering eller synlighet.
Riktig beslutning er å sende ut 2220 og deretter slutte å bruke tid på dem.

---

## Metode

Konklusjonene under er lest ut av den faktiske bundlen, ikke gjettet ut fra
kildekoden:

```bash
unzip -q HealthyFast-phone-v221.aab -d /tmp/aab
```

- **Avviklede API-er:** `strings base/dex/*.dex | grep setStatusBarColor` osv.
- **Hvem kaller hva:** androguard xref-analyse mot
  `Landroid/graphics/BitmapFactory;`
- **Obfuskerte klassenavn slått opp i**
  `build/app/outputs/mapping/phoneRelease/mapping.txt`
- **R8-status:** `strings base/dex/*.dex | grep -o '~~R8{[^}]*}'`

Poenget med å gå via bundlen: Play skanner ferdig Java/Kotlin-bytecode. Det er
et annet univers enn Dart-koden din, og de to svarer ikke alltid på samme
spørsmål.

---

## 1 + 2. Heldekkende skjerm (to varsler, én årsak)

> «Det er ikke sikkert at heldekkende kan brukes for alle brukere»
> «Appen din bruker avviklede API-er eller parametere for heldekkende skjerm»

**Status: kan ikke lukkes fra appkoden. Delvis forbedret.**

De avviklede kallene finnes på to steder i bundlen:

| Dex | Klasse | Kall |
|---|---|---|
| `classes3.dex` | `io.flutter.plugin.platform.PlatformPlugin` | `setStatusBarColor`, `setNavigationBarColor`, `setStatusBarContrastEnforced` |
| `classes.dex` | androidx `EdgeToEdge` (fra `activity-ktx`) | de over + `setNavigationBarDividerColor`, `setDecorFitsSystemWindows` |

androidx-halvparten er fikset: `activity-ktx` er løftet 1.9.0 → 1.11.0. Fra
1.10.0 velger biblioteket `EdgeToEdgeApi35`, som overlater bar-fargene til
systemet i stedet for å sette dem.

Flutter-halvparten kan ikke fikses herfra. `PlatformPlugin` ligger i motoren.
Ingenting i `lib/` kaller `SystemChrome` i det hele tatt — sjekket, null treff
— så dette er ikke noe appen din ber om. Koden er der uansett, og skanningen
er statisk.

**Og det hjelper ikke å oppgradere Flutter.** Dette ble sjekket 2026-08-05:

- `pubspec.lock` krever `flutter: ">=3.44.0"`, altså bygges prosjektet
  allerede med en tilnærmet gjeldende Flutter. Bundlen fra 2026-08-02 har
  fortsatt kallene.
- Sporingssaken [#175262](https://github.com/flutter/flutter/issues/175262)
  ble lukket som duplikat av
  [#165327](https://github.com/flutter/flutter/issues/165327) — som er en
  **dokumentasjonsoppgave**: «update our Dart developer-facing documentation
  to tell users that these calls will not work on Android 15+». Den er merket
  `r: fixed`.

Flutter-teamet løste altså saken ved å dokumentere at kallene ikke virker på
Android 15+, ikke ved å fjerne dem fra motoren. Konsekvensen: dette varselet
står i Play Console for **alle** Flutter-apper, på ubestemt tid. Det er ikke
noe å vente på.

Relaterte rapporter, samme utfall:
[#183349](https://github.com/flutter/flutter/issues/183349),
[#169810](https://github.com/flutter/flutter/issues/169810).

Selve oppsettet er riktig: `enableEdgeToEdge()` kalles i `MainActivity`
(gated på ikke-watch), og `SafeArea` brukes gjennomgående. Appen håndterer
insets fint — det er bytecoden Play misliker, ikke oppførselen.

---

## 3. Nedskalert punktgrafikk

> «Forbedre appytelsen med nedskalert punktgrafikk»

**Status: kan ikke lukkes fra appkoden.**

Første antakelse var at `new icon.png` (512×512, vist 28×28 dp) var synderen.
**Det var feil.** Flutters `Image.asset` dekoder i Skia inne i
`libflutter.so` — C++, usynlig for en bytecode-skanner. Play kan ikke ha
flagget den.

xref-analysen på ekte `BitmapFactory.decode*`-kall:

| Kallsted | Antall | Din kode? |
|---|---|---|
| `FlutterLocalNotificationsPlugin` | 5 | nei |
| `com.google.mlkit.genai.prompt.ImagePart` | 2 | nei |
| `com.google.android.gms.wearable.internal.zzjc` | 2 | nei |
| `androidx.core.graphics.drawable.IconCompat` | 1 | nei |
| `com.google.android.gms.common.images.zaa` | 1 | nei |
| `io.flutter.embedding.engine.FlutterJNI` | 1 | nei |
| `io.flutter.embedding.engine.image.ImageDecoderHeifApi36Impl` | 1 | nei |
| **`MealEstimator.describeImage`** | 2 | **ja — og gjør det riktig** |

`MealEstimator.decodeAndDownscale()` gjør nøyaktig det Google ber om:
`inJustDecodeBounds` for å lese dimensjonene, `inSampleSize` som toerpotens,
`createScaledBitmap` til slutt. Ingen endring nødvendig.

Alt annet er bibliotekkode.

### Hvorfor keep-regelen ikke er løsningen

Nærliggende idé: `-keep class com.dexterous.flutterlocalnotifications.** { *; }`
freder hele pakken, så R8 får ikke strippe bildekodingsstiene. Snevre inn
regelen, så forsvinner de.

Det virker ikke. `createNotification` velger bildestil **datadrevet** fra
`NotificationDetails`. R8 kan ikke bevise at `BigPictureStyle`-grenen aldri
tas, og må konservativt beholde bitmap-hjelperne uansett hvor smal
keep-regelen er. Forventet gevinst ≈ null.

Samtidig er risikoen reell: den brede regelen ble lagt inn nettopp fordi
planlagte varsler feilet *stille* uten den — alarmen fyrer, ingen varsel
vises. Å bytte en garantert regresjonsrisiko mot en usannsynlig gevinst er
feil handel. **Regelen står urørt.**

Verdt å merke: `notification_service.dart` bruker ingen `StyleInformation` i
det hele tatt. Koden Play flagger kjører aldri i denne appen.

---

## 4. R8-optimalisering

> «Forbedre appens minne og ytelse med R8-optimalisering»

**Status: allerede oppfylt. Sannsynligvis støy fra Play.**

Verifisert i bundlen som faktisk ble lastet opp:

```
~~R8{"backend":"dex","compilation-mode":"release","min-api":26,
     "pg-map-id":"e9c79ca","r8-mode":"full","version":"8.11.18"}
```

`"r8-mode":"full"` i **alle** dex-filer, i både phone- og watch-bundlen.
`mapping.txt` og `resources.txt` skrives, altså kjørte både minifisering og
ressursshrinking. Konfigurasjonen Google ber om var på plass hele tiden.

`isMinifyEnabled` / `isShrinkResources` er nå satt eksplisitt i
`build.gradle.kts`. Det er en no-op for Play-skanneren — hensikten er at
byggene ikke skal avhenge av at Flutter-pluginens defaults holder seg
uendret ved neste SDK-oppgradering.

Eneste gjenværende hevarm: `seeds.txt` er ~100 000 linjer. De brede
`-keep class ... { *; }`-reglene (ML Kit, Firebase, protolayout/tiles, GSON,
Health Connect) friter store deler av bibliotekskoden fra optimalisering.
Å snevre dem inn er mulig, men hver enkelt regel står der fordi noe knakk
uten den. Ikke rør uten en dedikert testrunde per regel.

---

## Hva som faktisk ble endret

| Fil | Endring | Effekt på varselet |
|---|---|---|
| `android/app/build.gradle.kts` | `activity-ktx` 1.9.0 → **1.11.0** | fjerner ~halvparten av kallstedene for #2. Varselet blir stående. |
| `android/app/build.gradle.kts` | `isMinifyEnabled` / `isShrinkResources` eksplisitt | ingen. Forsikring mot fremtidige default-endringer. |
| `lib/widgets/app_bar_title.dart` | `cacheWidth`/`cacheHeight` fra `devicePixelRatioOf` | ingen — Play så aldri dette. Beholdt fordi det er en ekte gevinst: ~1 MB spart dekoding på fire skjermer. |

Forventet resultat i Play Console etter neste opplasting: **alle fire står
sannsynligvis fortsatt.** Endringene er gjort fordi de er riktige, ikke fordi
de fjerner merket.

---

## Når skal dette vurderes på nytt

Varsel 1 og 2 er **avsluttet sak**. Flutter-teamet har lukket den som
dokumentert oppførsel, ikke som en bug som skal fikses. Ikke vent på en
oppgradering som løser dem — den kommer ikke. Sjekk kun på nytt hvis Play
begynner å eskalere varselet fra «anbefales» til noe strengere.

- **Ved `flutter pub outdated`.** Får `flutter_local_notifications` en versjon
  som dekoder med bounds, forsvinner varsel 3. Sjekk endringsloggen for
  «bitmap» eller «downsample». Dette er den eneste av de fire som realistisk
  kan lukke seg av seg selv.
- **Hvis varsel 4 fortsatt står** etter en utgave bygget med denne
  konfigurasjonen: da er det Play-side støy, og du har R8-markøren over som
  bevis hvis du noen gang må argumentere for det.

Ikke bruk mer tid på disse mellom disse triggerne.

---

## Om Flutter-oppgradering (vurdert 2026-08-05)

Spørsmålet kom naturlig: er en Flutter-oppgradering løsningen? **Nei.**
Prosjektet er allerede på ≥ 3.44, og som vist over er ikke motorfiksen
planlagt. Så oppgradering må begrunnes på egne premisser.

Det finnes heller ingen tvang akkurat nå: Play krever `targetSdk` 36 fra
**31. august 2026** for nye apper og oppdateringer (Wear OS: 35). Prosjektet
står allerede på 36 for begge flavorene. Du er compliant.

Når en oppgradering en gang skal gjøres, ligger risikoen i dette prosjektet
konsentrert på fire steder — alle dokumentert som tidligere smertepunkter:

1. **`health: 13.3.1` er eksakt pinnet, og `connect-client` må matche.**
   Kommentaren i `build.gradle.kts` er eksplisitt: feil kombinasjon gir
   `NoSuchMethodError` på `ExerciseSessionRecord`-konstruktøren — en nativ
   krasj som **ikke kan fanges i Dart**. Verifiser mot
   `health-<ver>/android/build.gradle` før noe endres.
2. **ML Kit GenAI beta × R8 full mode.** Har knekt én gang (2026-07-02,
   Pixel 10 Pro). Beta-biblioteket har ufullstendige consumer-regler, så
   keep-reglene her er håndskrevne og skjøre.
3. **Wear OS: `tiles` 1.5.0 + `protolayout` 1.3.0 er et matchet par.** Feil
   kombinasjon gir `SecurityException` på Wear 5 når appen targeter 35+.
4. **`image_picker: 1.2.3` er også eksakt pinnet.** Eksakte pinner er alltid
   det som brekker først i en SDK-oppgradering.

Anbefalt fremgangsmåte når det blir aktuelt: oppgrader på egen branch, kjør
hele `RELEASE_TEST.md` del A på ekte enhet, og ikke slå sammen med andre
endringer i samme utgave. Da vet du hva som forårsaket en eventuell regresjon.
