# Release 0.9.13 — Die Baseline findet ihr Zuhause

🇬🇧 [English version](RELEASE_NOTES.md)

Vollstaendige Release-Notes: [docs/releases/v0.9.13_de.md](docs/releases/v0.9.13_de.md)
([english](docs/releases/v0.9.13.md)).

Ein grosses Release: Baselines, eine neue Regel, und die Standalone-EXE
zieht gleich.

- **Baselines wohnen jetzt im `.sca`-Ordner** neben Projekt/Gruppe, von
  CLI, EXE und Plugin identisch aufgeloest; `--baseline-scan y` bricht
  in der CI hart ab (Exit 99), wenn keine Baseline existiert. Der
  Nur-neue-Funde-Haken sitzt in beiden Hamburger-Menues und bietet an,
  eine fehlende Baseline sofort zu schreiben. Opt-in
  `[Baseline] PathInFingerprint=1` trennt gleichnamige Dateien.
- **Neue Regel SCA196 `ManagedResultUninit`**: `Result` gelesen vor dem
  ersten Schreiben bei verwalteten Rueckgabetypen - die versteckte
  var-Parameter-Falle, vor der W1035 nie warnt. 49/49 Korpus-Funde als
  echte Bugs verifiziert.
- **`SCA040`/`SCA042` waren in Produktion tot** (liefen vor dem
  Event-Binding-Aufbau) - wiederbelebt und am Korpus gehaertet; dazu
  eine Welle Detektor-FP-Fixes (Literal-Blanking in 16 Detektoren,
  DataModule-Schwarm, Schleifen-Fehlzuordnung, `SCA101` sieht endlich
  Folgezeilen-Zweige).
- **Die EXE zieht mit dem Plugin gleich**: Tastatur-Triage mit
  byte-treuem Datei-Editor, Kachel-Filter, ehrliche Sortierung,
  Fenster-Persistenz, externe Editoren, Crash-Diagnostik.
- **Der Dark Mode ist jetzt "SCA VSDark"** - die VS-Code-Dark-Modern-
  Palette statt des pechschwarzen Windows10 Dark.

---

# Vorher — Release 0.9.12 — Das Panel haelt Schritt

🇬🇧 [English version](RELEASE_NOTES.md)

Vollstaendige Release-Notes: [docs/releases/v0.9.12_de.md](docs/releases/v0.9.12_de.md)
([english](docs/releases/v0.9.12.md)).

Ein kleines Release, einen Tag nach 0.9.11.

- **Das Filescan-Panel folgt jetzt der Maus**: Rad und Klick navigieren den
  Editor mit 50 ms Einschwingzeit - vorher wanderte beim Rad die Auswahl,
  ohne dass der Editor ueberhaupt folgte. Die Liste selbst ist nicht mehr
  zaeh (ein COM-Aufruf pro gezeichneter Zelle, jetzt gecacht).
- **`SCA054` meldet Einzeiler wieder** - die v0.9.11-Quellpruefung zaehlte
  die Signatur als Nutzung, wenn sie sich die Zeile mit `begin` teilte.
  Baselines koennen ein paar Funde zurueckbekommen; die sind echt.
- **`WatchMode` stapelt keine Worker mehr**, und die Fund-Auswahl schreibt
  nicht mehr dreissigmal je Sekunde in die Zwischenablage.
- **`package-release.ps1`** raeumt Alt-Zips, und der Tag-Guard feuert jetzt
  wirklich.

---

# Vorher — Release 0.9.11 — Reparaturen

🇬🇧 [English version](RELEASE_NOTES.md)

Vollstaendige Release-Notes: [docs/releases/v0.9.11_de.md](docs/releases/v0.9.11_de.md)
([english](docs/releases/v0.9.11.md)).

Ein Fehlerbehebungs-Release, einen Tag nach 0.9.10. Keine neuen Regeln, keine
neuen Funktionen. Alles hier ist eine am Referenzkorpus belegte
Falschmeldung, eine mit 0.9.10 eingeschlichene Verschlechterung, oder eine
Versionsnummer, die still aufgehoert hatte zu stimmen.

- **Das Scrollen im IDE-Plugin ist wieder fluessig.** Drei Ursachen: die
  Gutter-Klammer aus 0.9.10 fragt fuer *jede* Zeile, wo der Code-Bereich bei
  unmarkierten sofort aussteigt; Fortsetzungszeilen sind jetzt Marken, ein
  Block ueber 21 Zeilen macht aus einer markierten einundzwanzig; und jedes
  Scroll-Ereignis erzwang einen Voll-Repaint zusaetzlich zu dem des Editors —
  jetzt ueber einen 90-ms-Einschwing-Timer gebuendelt.
- **Jede Zelle der Fundliste wurde zweimal gemalt** — der Renderer zeichnet
  alles selbst, `DefaultDrawing` war aber nie abgeschaltet.
- **`SCA028` meldet zwei Arten von Nicht-Funden nicht mehr**: ein
  ausdruecklich mit `nil` geleertes Ereignis, und einen Handler, der nur
  *scheinbar* fehlt, weil es den Namen der Ahnenklasse in zwei Units gibt
  (skia4delphi fuehrt `TfrmBase` im VCL- und im FMX-Beispielbaum).
- **`SCA054` fragt die Quelle**, bevor es behauptet, ein Parameter werde nie
  gelesen. Der AST-Text, gegen den gezaehlt wurde, ist eine verlustbehaftete
  Naeherung — ein Index-Ausdruck links einer Zuweisung und Argumente hinter
  einem `as`-Cast tauchen dort nie auf.
- **`SCA099 IfElseBegin` kommt ins `style`-Profil**, wo die anderen sechs
  Konventions-Regeln schon lagen.
- **Das IDE-Plugin nennt sich nicht mehr v0.9.8.**

---

# Vorher — Release 0.9.10 — Ein Befund je Block, ein leiserer Default

🇬🇧 [English version](RELEASE_NOTES.md)

Vollstaendige Release-Notes: [docs/releases/v0.9.10_de.md](docs/releases/v0.9.10_de.md)
([english](docs/releases/v0.9.10.md)).

Ein kleines Release, am selben Tag wie 0.9.9 getaggt. **Keine Regel hat
einen Fund gewonnen oder verloren** — der Referenzkorpus steht unveraendert
bei exakt **560.964** ueber alle **141** anschlagenden Regeln, Regel fuer
Regel geprueft statt ueber die Summe. Geaendert hat sich, *wie* Befunde
gemeldet werden.

- **`SCA021` nennt den echten Zeilenbereich** (`lines 513-533, 8 matched
  lines`). Der Meldetext gehoert zum SARIF-Fingerprint, jeder
  `SCA021`-Fund sieht gegen eine bestehende Baseline also neu aus —
  **Baseline neu schreiben**. Genau deshalb ist das eine neue Version und
  kein erneutes Bespielen von 0.9.9.
- **Das `default`-Profil ist leiser.** Sechs reine Konventions-Regeln —
  45,4 % aller Funde des Korpus, alle korrekt — sind in ein neues
  `style`-Profil gewandert. `strict` bedeutet weiterhin alles.
- **Die IDE zeichnet die Bereichs-Klammer im Gutter**, und man sieht sie
  jetzt: die Kappe wuchs von einem rechtsbuendigen Zwei-Pixel-Balken nach
  rechts, lag damit auf sich selbst und sieben Pixel ausserhalb.
- **Ein Marker im Bereich eines Fundes zaehlt**, als Treffer und als
  benutzt — der Migrationsschritt aus 0.9.9 entfaellt.
- **`--parallel` sagt, wenn es abgelehnt hat**, statt still seriell zu
  laufen.
- **Zwei veroeffentlichte Zahlen der 0.9.9-Notes waren falsch** und sind
  korrigiert: das Error-Tier ist **2.134**, nicht 2.172, und der
  Regelbestand wuchs **166 → 195**, nicht 183 → 195.

---

# Vorher — Release 0.9.9 — Weniger Falschmeldungen, zwei Projekt-Regeln

🇬🇧 [English version](RELEASE_NOTES.md)

Vollstaendige Release-Notes: [docs/releases/v0.9.9_de.md](docs/releases/v0.9.9_de.md)
([english](docs/releases/v0.9.9.md)).

In diesem Zyklus hat das Werkzeug gelernt, **weniger** zu melden. Auf dem
Referenz-Korpus aus 12.800 Dateien fiel die Fundzahl von **645.622 auf
560.964 — 84.658 weniger (−13,1 %)**, ohne wissentlich einen echten Fund zu
verlieren. Der Regelbestand wuchs von 166 auf **195 Regeln**.

- **−84.658 Funde**, in sieben einzeln gemessenen und abgesicherten
  Inkrementen.
- **`SCA194` / `SCA195`** — Dateien, die nicht zum Projekt gehoeren, und
  Units, die das Projekt uebersetzt, ohne sie zu fuehren. Beide brauchen
  eine projektweite Sicht und laufen nur im Projekt- oder
  Projektgruppen-Scan.
- **Die Regelseiten sagen jetzt, was eine Regel bewusst *nicht* meldet.**
- **`SCA080` sieht sich `Break` nicht mehr an** — wer dem Hinweis folgte,
  machte aus Such-Schleifen Vollscans und aus `while True`-Schleifen
  Endlosschleifen.
- **Die CLI nennt bei jedem Lauf ihr aktives Regelset**, samt Herkunft des
  Profils. Bisher schwieg sie, wenn das Profil aus der `analyser.ini` kam —
  und ein unerwartetes `ide-fast` dort sieht genauso aus wie ein kaputter
  Build.

Eine Version **0.9.4 gibt es nicht** — sie wurde uebersprungen. v0.9.5 bis
v0.9.7 waren ohne Release-Notes ausgeliefert worden; der CHANGELOG deckt
sie jetzt ab.

---

# Vorher — Release 0.9.8

## Update 2026-06-08 / 2026-06-09 — Hardening v3/v4 + FP-Reduktion

- **DFM Resource-Wrapper-Format (`$FF $0A $00`) unterstuetzt** — die 83
  GExperts-DFMs sprangen von 0 auf 1.084 Findings. JVCL-DFM-Coverage
  hat sich etwa verdoppelt.
- **AST `Destroy` Reentrancy-Bug** behoben — `EInvalidPointer` /
  SARIF SCA006 bei `gAstFileCache.Evict` nach dem ersten File im Scan
  beseitigt.
- **`uFixHint` Memoize-Cache** — fixt Win32-`EOutOfMemory` im IDE-
  Plugin-Pfad `HighlightAllFindingsInFile` bei grossen Scans
  (≥100k Findings).
- **scan.log Phase-Tracking + Skip-Log** — jeder `Analyseabbruch:`
  zeigt jetzt die letzte erfolgreiche Phase + das aktuelle File;
  ignorierte / ausgeschlossene Files erscheinen mit Grund, statt
  stillschweigend zu verschwinden.
- **FP-Reduktion-Sprint** — Self-Scan-FPs in `SCA017 DebugOutput`,
  `SCA070 CommentedOutCode`, `SCA019 TodoComment` und `SCA005
  FormatMismatch` um ~80% reduziert (67 → 12 ueber die drei
  Style-Detektoren). Nebenbei-Fix: `FreeAndNil(Self.Field)` mit
  `Self.`-Qualifier wird jetzt als Freigabe erkannt.
- **Konfiguration** — `[Detectors] MaxLineLength` und `MaxCaseBranches`
  hinzugefuegt.

## Frueherer Stand im 0.9.8-Zyklus

13 Commits seit v0.9.7. Phase 1 aus
[Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) ist komplett
(6/6 Quick-Wins); Phase 4 hat mit dem A.3-Minimal-Schritt fuer den
Cross-Unit-Sichtbarkeits-Check begonnen. Ein Multi-Persona-Review
(Architektur + Security + Performance) hat den Code zusaetzlich
gehaertet.

## Highlights

- **`--time-detectors` Markdown-Report** — kumulierte Wall-Time +
  Call-Count pro Detektor.
- **Test-Fixture-Auto-Detection** — Findings aus `uTest*.pas` /
  `*Sample.pas` / `*Demo.pas` / test/samples/demos/resources-Ordnern
  werden in den Profilen `default` und `selftest-quiet` ausgefiltert.
  Repo-Root-anchored gegen Silent-Drop-Angriffe.
- **SCA165 `UnusedSuppression`** — `// noinspection X`-Marker die nie
  ein Finding unterdrueckt haben, werden selbst geflaggt.
- **Golden-Corpus-FP-Regression-Suite** — 5 historische FP-Reproducer,
  PowerShell-Runner, CI-tauglicher Exit-Code.
- **SARIF + Baseline `contextHash/v1`** — SHA256 ueber ein whitespace-
  normalisiertes +/-3-Zeilen-Snippet. Baselines ueberstehen kleine
  Refactors. Backward-Compat mit alten Baselines.
- **Confidence-Audit (35 Kinds → `fcMedium`)** — heuristische /
  metrik-basierte / Style- / DFM-Schema- / no-data-flow-Security-Kinds
  getaggt. Per-Kind-Begruendungen in
  [`docs/ConfidenceAudit.md`](docs/ConfidenceAudit.md).
- **A.3-Minimal: SCA052 Cross-Unit reaktiviert** — `gSymbolRefIndex`
  wird jetzt fuer `fkUnusedPublicMember` konsultiert. Spot-Check zeigt
  44 % der Cross-Unit-Methoden korrekt erkannt; 56 % als Follow-Up im
  `Konzept_ScannerQualitaet.md §A.3+` dokumentiert.

## Security-Hardening (Multi-Persona-Review)

- **`// noinspection All`** schliesst Security-Critical-Kinds aus
  (`fkHardcodedSecret`, `fkSQLInjection`, `fkCommandInjection`,
  `fkDfmHardcodedDbCreds`, `fkDfmSqlFromUserInput`,
  `fkInsecureCryptoAlgorithm`, `fkUnusedSuppression`). Single-Marker-
  Backdoor-Bypass ausgehebelt.
- **`ParseMarkerLine`** nutzt `TDetectorUtils.ScanCodeLine` — String-/
  Block-Comment-Context-aware. Marker in String-Literalen werden nicht
  mehr als aktiv geparst.
- **Baseline-JSON** gehaertet mit `MAX_BASELINE_ENTRIES = 1_000_000`
  und `MAX_FINGERPRINT_LEN = 256` gegen OOM-Angriffe.

## Performance

- **`gFileTextCache` lebt durch die Post-Scan-Phase** — Suppression,
  ContextHash und SARIF/Baseline-Output nutzen den warmen Cache statt
  jede Datei neu zu lesen. Spart ~191k redundante `LoadFromFile`
  + UTF-8-Validierungen pro Real-World-Scan.
- **`TFileTextCache` ist mtime-aware** — stale Entries invalidieren
  sich selbst.
- **`uVisibilityCheck`** cacht `AllUnitMethods` + memoiziert
  `DescendantsOf` pro Unit statt pro Public-Member.

## Migration

Keine Breaking-Changes. Bestehende Baselines funktionieren wie bisher
(matched via Legacy-Fingerprint); neue Baselines tragen zusaetzlich
`contextHash`. Detector-Autoren mit `F.Confidence := xxx` NACH
`SetKind` sollten auf den neuen `SetKind(K, AConfidence)`-Overload
migrieren — das alte Pattern bleibt kompatibel.

## Commit-Log

```
1e7e193  fix(cache):       mtime-aware Cache-Invalidation
2b723f7  fix(build):       IsTestFixturePath Impl-Signatur
120894a  fix(review):      9 Review-Findings (Sec + Perf + API)
e18323d  refactor:         Clean-Code-Fixes (DRY, SRP, Naming)
3054630  fix(visibility):  A.3 OwnUnit-Pfad + Konzept-Roadmap
0ab0bf4  feat(visibility): A.3-Minimal — gSymbolRefIndex fuer SCA052
a8c7c35  feat(confidence): A.1 Audit — ~35 Kinds als fcMedium
91ae2ec  feat(baseline):   C.2 SARIF contextHash + Baseline-Match
7b957a8  test(corpus):     C.1 Golden-Corpus + Runner
c0234d7  feat(suppression):C.3 Unused-Suppression-Tracking (SCA165)
57a0b06  feat(filter):     A.2 Test-Fixture-Auto-Detection
1b5a145  fix(perf):        gDetectorTimings in INTERFACE-Section
79b4f56  feat(cli):        --time-detectors Flag
```
