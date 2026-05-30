# Default-TODO: Neuen Detektor implementieren

Checkliste für jeden neuen Detektor — abhakbar von oben nach unten.
Alle Touch-Points sind hier dokumentiert, damit nichts vergessen wird
(Compile-Fehler durch fehlende DCCReferences, Tests die den Detektor
nicht sehen, fehlende Combo-Einträge in nur einer der zwei Formen, ...).

Stand: 2026-05-30 — letzter Lauf SCA164 (UnusedRoutine, branch
`feat/sca164-unused-routine`). Davor: SCA162 + SCA163 (Security-Pair),
SCA132/133 (2026-05-20).

---

## Aktueller Lauf — 2026-05-30: SCA164 UnusedRoutine

Schliesst die Luecke zwischen SCA147 (UnusedPrivateMethod - nur class
private) und SCA148+ (UnusedPublicMember - nur class public). Bisher
durchfielen top-level Procedures/Functions in der `implementation`-Sektion
ohne Aufruf alle Maschen.

Konzept-Dokument: [`Konzept_SCA164_UnusedRoutine.md`](Konzept_SCA164_UnusedRoutine.md).
Vorlage gespiegelt: SonarDelphi
[`UnusedRoutineCheck.java`](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/UnusedRoutineCheck.java).

### SCA164 — UnusedRoutine

- **Was**: Standalone procedure/function im `implementation`-Teil ohne
  Aufruf irgendwo in der Unit, ohne Forward-Decl im `interface`.
- **Scope**: Single-file. Cross-Unit-Konsumenten via Bare-Call werden
  in v1 nicht getrackt (`gSymbolRefIndex` indexiert nur `Obj.Member`).
  Interface-Forward-Deklarierte Routinen werden daher uebersprungen.
- **Severity**: `lsHint` · **Type**: `ftCodeSmell` · **Confidence**: `fcHigh`
  (Implementation-only, kein Cross-Unit-Confound).
- **Self-/Recursive-Calls**: zaehlen NICHT als Use (Mirror SonarDelphi
  `testUnusedRecursiveRoutineShouldAddIssue` 2). Range-Tracking ueber
  Linien-Bereich [Start..NextRoutineStart-1].
- **FP-Guards (MVP)**: Konstruktor/Destruktor, Methoden-Direktiven
  `override`/`virtual`/`abstract`/`message`/`dynamic`, `Register`
  Top-Level-Prozedur, Enumerator-Trio
  (`MoveNext`/`GetEnumerator`/`Current`), Forward-Decl in
  `interface`-Sektion (potenzieller Cross-Unit-Caller).

### Touch-Points (abgehakt)

- [x] **uSCAConsts.pas** — `fkUnusedRoutine` ans Enum-Ende + KIND_META
  (`ftCodeSmell` / `lsHint`).
- [x] **uUnusedRoutine.pas** — neu in
  [`StaticCodeAnalyserForm/sources/Detectors/`](StaticCodeAnalyserForm/sources/Detectors/uUnusedRoutine.pas).
  Boilerplate inspiriert von SCA147; eigene `StripStringsAndCommentsLn`-
  Kopie (Suffix `Ln` damit Symbol-Name-Konflikt mit dem SCA147-Helper
  vermieden ist). Wenn der Detektor laenger lebt, beides nach
  `uDetectorUtils` hochziehen.
- [x] **uStaticAnalyzer2.pas** — uses-Klausel + `AddD('UnusedRoutine', ...)`
  nach `CommandInjection`.
- [x] **uTestFindingHelper.pas** — uses + `TUnusedRoutineDetector`-Eintrag
  in **`FindingsOfFile`** (NICHT `FindingsOf`, weil der Detektor
  `AcquireLines` zum File-Body-Scan braucht; siehe Pattern bei SCA147).
- [x] **uTestUnusedRoutine.pas** — 13 Tests (4 positiv + 3 negativ
  caller-existiert + 5 negativ FP-Guards + 1 Finding-Inhalt). Alle Tests
  nutzen `FindingsOfFile`.
- [x] **rules/sca-rules.json** — SCA164-Eintrag mit
  `cleanCodeAttribute: CLEAR` + `impacts.MAINTAINABILITY=LOW`. Korrekte
  Reihenfolge (nach SCA163).
- [x] **uFixHint.pas** — `case fkUnusedRoutine` mit 4 Fix-Optionen
  (Routine loeschen / Caller hinzufuegen / ins interface verschieben /
  Suppression-Marker).
- [x] **i18n/de.po** — `'Top-level routine appears unused (dead code)'`
  Description-String.
- [x] **Build-Files** alle sechs: Standalone-`.dpr`/`.dproj`,
  IDE-Plugin-`.dpk`/`.dproj`, Test-`.dpr`/`.dproj`.

### Bewusst weggelassen (Phase 2)

- **Bare-Call-Tracking im `gSymbolRefIndex`** — der jetzige Index sieht
  nur `Obj.Member`-Calls. Cross-unit-public-Routinen werden in v1 daher
  per `interface`-Forward-Decl-Guard ausgeschlossen, nicht via Index.
  Verbesserung ~50 LOC in `AddRefsFromNode`.
- **Klassen-Methoden-Implementierungen** (qualifizierte Namen
  `TFoo.Bar`) — fallen durch den `Pos('.', ...) = 0`-Filter raus, sind
  fuer SCA147 (private) und SCA148+ (public) zustaendig.
- **`[Attribute]`-Awareness**, **Interface-Implementierungs-Check** —
  als Suppression-Pfad belassen
  (`// noinspection UnusedRoutine`).
- **Forward-Decl + Impl in implementation-Sektion (beide tot)** — bekannter
  False-Negative: die Forward-Decl-Zeile zaehlt aktuell als externer
  Caller des Impls und umgekehrt. Selten in modernem Code. Full Fix
  wuerde Forward-Decl-Line-Positionen sammeln und vom external-Match-
  Counter ausnehmen. Suppression als Escape.

### Code-Review-Fixes (post-MVP, gleicher Branch)

Ein `/code-review` ueber den initialen Wurf hat 6 Findings geliefert,
alle eingearbeitet:

| # | Finding | Fix |
|---|---|---|
| 1 | `HasForwardDeclInInterface` ruft `FindAll(nkInterface)` pro Routine | `InterfaceMethods: TStringList` einmal vor der Loop befuellen, `IndexOf`-Lookup ist O(log N) |
| 2 | 8-Zeilen-toter-Kommentar in `HasExternalCaller` erklaerte nicht-implementierte Heuristik | Komplett geloescht; HasExternalCaller ist jetzt ~15 LOC |
| 3 | `StripStringsAndCommentsLn` war byte-identische Kopie von SCA147-Helper | Ersetzt durch `TDetectorUtils.StripStringsAndComments(Lines, LineForChar)` — Funktion existierte bereits in der zentralen Util-Unit |
| 4 | `LineOfPos` war O(n) pro Match | Eliminiert: das `LineForChar`-Array aus `TDetectorUtils.StripStringsAndComments` liefert O(1)-Lookup |
| 5 | `forward;`-Direktive nicht im Exempt-Filter | `;forward` in `HasExternalReferenceDirective` aufgenommen; Forward-Decl-Knoten wird nicht mehr separat verarbeitet (False-Negative-Restrisiko fuer dead forward+impl-Paare als Limit dokumentiert) |
| 6 | Standalones zweimal iteriert + `TArray.Sort` redundant | Parser-Order ist File-Order, also natuerlich sortiert — `TArray.Sort` entfernt, eine For-Loop fuer die Verarbeitung |

**Netto-Auswirkung**: Detector schrumpfte um ~75 LOC, hat eine
zentrale Helper-Abhaengigkeit weniger redundant. Verhalten der 13
Tests unveraendert (Code-Pfade gleich; Korrektheit der drei
PLAUSIBLE-Findings nicht messbar veraendert ohne Profiling).

### Offen (IDE-Sanity)

- [ ] IDE-Build der drei dproj-Dateien gruen.
- [ ] `TTestUnusedRoutine` (13 Tests) gruen.
- [ ] `TTestRuleCatalog.EveryFindingKindHasMqrMapping` gruen
  (`cleanCodeAttribute` + `impacts` sind im JSON-Eintrag).
- [ ] `TTestSuppressionCompleteness` gruen
  (`'UnusedRoutine'` als KIND_META.Name, identisch zu JSON-`kind`).
- [ ] Real-World-Run gegen ein groesseres Repo (z.B. das SCA-Projekt selbst!)
  um zu sehen ob es eigene tote Helper findet.

---

## Vorheriger Lauf — 2026-05-30: SCA162 + SCA163

Zwei Security-Detektoren in einer Welle, beide aus der "Top-5 fehlt im
Repo"-Analyse (siehe [`Todo_FalsePositiveReduction.md`](Todo_FalsePositiveReduction.md)
und Konversations-Kontext "welche Top-5 sind schon vorhanden"). Drei der
fünf Vorschläge waren bereits abgedeckt
([`uHardcodedSecret.pas`](StaticCodeAnalyserForm/sources/Detectors/uHardcodedSecret.pas),
[`uHardcodedPath.pas`](StaticCodeAnalyserForm/sources/Detectors/uHardcodedPath.pas),
[`uFormatMismatch.pas`](StaticCodeAnalyserForm/sources/Detectors/uFormatMismatch.pas));
die verbleibenden zwei werden mit diesem Lauf geschlossen.

### SCA162 — InsecureCryptoAlgorithm

- **Was**: Verwendung schwacher Krypto-Verfahren (MD5/SHA1/DES/3DES/RC4)
  oder veralteter TLS-Versionen (TLS1.0/TLS1.1/SSLv3) - per Stringliteral
  oder Klassen-Wrapper (THashMD5, TIdHashSHA1, …).
- **Severity**: `lsWarning` · **Type**: `ftVulnerability`
- **Confidence**: `fcHigh` (Default - die Token-Liste ist eindeutig).
- **CWE/OWASP**: CWE-327, CWE-328 · OWASP A02:2021.

### SCA163 — CommandInjection

- **Was**: `ShellExecute`/`CreateProcess`/`WinExec` aufgerufen mit
  String-Konkatenation (`+`) im Command-Argument. Heuristik ohne
  Taint-Tracking - Confidence default `fcLow`, damit das Finding im
  Standard-Profil (MinConfidence=fcMedium) zuerst versteckt bleibt.
- **Severity**: `lsError` · **Type**: `ftVulnerability`
- **Confidence**: `fcLow` (explizit gesetzt in `AnalyzeMethod`, weil
  Konkatenation mit Konstanten harmlos ist - ohne Taint-Analyse nicht
  unterscheidbar).
- **CWE/OWASP**: CWE-78 · OWASP A03:2021.

### Touch-Points (abgehakt)

- [x] **uSCAConsts.pas** — `fkInsecureCryptoAlgorithm` + `fkCommandInjection`
  ins `TFindingKind`-Enum + `KIND_META`-Array (Komma vor neuem
  letzten Eintrag korrigiert).
- [x] **uInsecureCryptoAlgorithm.pas** — neu in
  [`StaticCodeAnalyserForm/sources/Detectors/`](StaticCodeAnalyserForm/sources/Detectors/uInsecureCryptoAlgorithm.pas).
  Hybrid: Wortgrenz-Match auf `WEAK_ALGO_TOKENS` + Substring-Match auf
  `WEAK_CLASS_TOKENS`. Dedup pro `(line, hit)` damit
  `Hash := THashMD5.Create` nicht zweimal flaggt (einmal über
  `nkAssign.TypeRef`, einmal über `nkCall.Name`).
- [x] **uCommandInjection.pas** — neu in
  [`StaticCodeAnalyserForm/sources/Detectors/`](StaticCodeAnalyserForm/sources/Detectors/uCommandInjection.pas).
  AST-Scan auf `nkCall`, Method-Path-Suffix-Match gegen `SHELL_APIS`,
  Args-Scan mit Apostroph-State-Tracking damit `+` IM Literal nicht zählt.
- [x] **uStaticAnalyzer2.pas** — `uses`-Klausel erweitert, zwei
  `AddD(...)`-Aufrufe nach `PointerSubtraction`.
- [x] **uTestFindingHelper.pas** — uses-Klausel + zwei
  `T<Name>Detector.AnalyzeUnit(Root, 'test.pas', Result)`-Aufrufe in
  `FindingsOf` (AST-only, beide Detektoren brauchen kein File-IO).
- [x] **uTestInsecureCryptoAlgorithm.pas** — 15 Tests (6 positive Algo-
  Token, 2 positive Klassen-Wrapper, 3 negative starke Algorithmen,
  2 Wortgrenz-FP-Schutz, Kind/Severity, Dedup).
- [x] **uTestCommandInjection.pas** — 9 Tests (4 positive Shell-API-
  Varianten, 4 negative inkl. Plus-im-Literal, Kind/Severity/Confidence).
- [x] **rules/sca-rules.json** — zwei neue Rule-Einträge SCA162/SCA163,
  jeweils mit `cleanCodeAttribute: TRUSTWORTHY` + `impacts.SECURITY=HIGH`
  damit `EveryFindingKindHasMqrMapping` grün bleibt. Profil-Eintrag
  `security` um beide ergänzt.
- [x] **uFixHint.pas** — zwei `case`-Branches mit Before/After-Beispielen
  (MD5 → SHA256 für Crypto, `ShellExecuteEx` mit `SHELLEXECUTEINFO` für
  CommandInjection).
- [x] **i18n/de.po** — zwei neue msgid/msgstr-Paare für die Description-
  Strings. `i18n/en.po` ist Fallback-Identity (Source ist englisch) und
  braucht hier nichts.
- [x] **Standalone-App-Build**: `StaticCodeAnalyser.d12.dpr` +
  `StaticCodeAnalyser.d12.dproj` (uses + `<DCCReference>`).
- [x] **IDE-Plugin-Build**: `StaticCodeAnalyser.IDE.d12.dpk` +
  `StaticCodeAnalyser.IDE.d12.dproj` (contains + `<DCCReference>`).
- [x] **Test-Project-Build**: `tests/TestProject.dpr` +
  `tests/TestProject.dproj`.

### Bewusst weggelassen

- **`IsSonarDelphiKind`-Whitelist**: SCA162/163 sind SCA-native (kein
  SonarDelphi-Pendant), passen automatisch in den Sonst-Pfad der
  Funktion (`Ord(K) > Ord(fkMethodName)` und nicht in der Case-Liste).
- **Combo-Listen-Erweiterung**: beide Detektoren sind bereits über die
  vorhandenen Severity-Filter (Warning/Error) und Type-Filter
  (Vulnerability) erreichbar. Eigener `fmXxx`-Filter-Mode nicht nötig.
- **DETECTORS.md / README.md-Counter**: Bump erfolgt im nächsten Doku-
  Pass, nicht in diesem Code-Commit.

### Offen (IDE-Sanity)

- [ ] IDE bauen (msbuild/dcc32 ist im Delphi-Edition-CLI blockiert -
  siehe `feedback_delphi_pitfalls.md`).
- [ ] `TTestInsecureCryptoAlgorithm` + `TTestCommandInjection` grün im
  DUnitX-Runner.
- [ ] `TTestRuleCatalog.EveryFindingKindHasMqrMapping` grün (sollte
  durch die zwei JSON-Einträge mit `cleanCodeAttribute` + `impacts`
  automatisch passen).
- [ ] `TTestSuppressionCompleteness` grün (KIND_META.Name-Token sind
  `'InsecureCryptoAlgorithm'` + `'CommandInjection'`, identisch zum
  JSON-`kind`-Feld - sollte greifen).
- [ ] Echter Run gegen RHDInternalAPI_NextGen-Repo o.ä. um CommandInjection-
  FP-Rate empirisch zu messen (Confidence-Tuning ggf. nachschärfen).

---

## Vorlage / Default-Checkliste (für künftige Detektoren)

---

## Vorab klären

- [ ] **SCA-ID vergeben** — nächste freie Nummer aus
  [`rules/sca-rules.json`](rules/sca-rules.json) (`grep '"id":'`).
- [ ] **fk-Bezeichner**, **Kind-Name** (für JSON / KIND_META) und
  **fm-Bezeichner** festlegen. Konvention: PascalCase mit `fk`/`fm`-Präfix.
- [ ] **Severity** + **Type** entscheiden (`lsError`/`lsWarning`/`lsHint` ×
  `ftBug`/`ftCodeSmell`/`ftVulnerability`/`ftSecurityHotspot`/`ftCodeDuplication`).
- [ ] **SonarDelphi-Pendant?** Wenn ja: Whitelist in `IsSonarDelphiKind`
  (siehe [`uSCAConsts.pas`](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas)
  `case K of` am Ende). Wenn nein (z. B. Sonar-50): **nicht** in die
  Whitelist eintragen.
- [ ] **AST realistisch oder Regex?** Detektor-Klasse bestimmen:
  - AST: `class procedure AnalyzeUnit(UnitNode: TAstNode; ...)`
    Standard wenn die Pattern aus dem Parse-Baum lesbar ist
    (`nkCall`, `nkRaise`, `nkOnHandler`, `nkAssign`, `nkMethod`, …).
  - Regex / Code-Scan: über `AcquireLines` + `TRegEx`, siehe
    [`uConcurrencyExt.pas`](StaticCodeAnalyserForm/sources/Detectors/uConcurrencyExt.pas)
    als Vorlage. Nur wenn AST-Knoten nicht ausreichen (z. B. weil der
    Parser den interessierenden Teil verwirft).

---

## Detektor + Test schreiben

- [ ] **Detektor-Unit** `StaticCodeAnalyserForm/sources/Detectors/u<Name>.pas`.
  Boilerplate von einem ähnlichen Detektor abkopieren:
  - AST: [`uMissingRaise.pas`](StaticCodeAnalyserForm/sources/Detectors/uMissingRaise.pas)
  - AST + Kontext-Walker: [`uRaiseOutsideExcept.pas`](StaticCodeAnalyserForm/sources/Detectors/uRaiseOutsideExcept.pas)
  - Regex / Codetext: [`uConcurrencyExt.pas`](StaticCodeAnalyserForm/sources/Detectors/uConcurrencyExt.pas)
  - Klassen-Naming: `T<Name>Detector`.
  - Header-Doku: Pattern (Bug/Smell), Korrekt-Variante, Erkennungs-
    strategie, bewusste Limitierungen, Sonar-Pendant + URL.
- [ ] **Test-Unit** `StaticCodeAnalyserForm/tests/uTest<Name>.pas`.
  - `[TestFixture] TTest<Name>` mit `[Test]`-Methoden.
  - **Mindest-Coverage**: 1 positiver Fall, 1 negativer Fall,
    1 Finding-Kind/Severity-Smoke-Test. Bei Kontext-Detektoren
    zusätzlich Edge-Cases (nested try/except, finally-Block, …).
  - Test-Helper: `TFindingHelper.FindingsOf(SRC)` für AST,
    `TFindingHelper.FindingsOfFile(SRC)` wenn der Detektor die Datei
    selbst liest.

---

## Enum-Eintrag + Metadaten

- [ ] **`TFindingKind`** in [`uSCAConsts.pas`](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas)
  — `fk<Name>` an die nächste Position anhängen.
  ⚠ Komma vor dem neuen letzten Eintrag setzen.
- [ ] **`KIND_META`** in derselben Datei — Eintrag mit
  `Name`/`FindingType`/`DefaultSeverity` analog der Reihenfolge im Enum.
  ⚠ Komma vor dem neuen letzten Eintrag setzen.
- [ ] **`IsSonarDelphiKind`** (nur wenn SonarDelphi-Migration) — `case K of`
  am Ende der Funktion erweitern.

---

## Registrierung im Pipeline-Stack

- [ ] **`uses`-Klausel in [`uStaticAnalyzer2.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uStaticAnalyzer2.pas)**
  (implementation-Block) — neue Detektor-Unit anhängen.
- [ ] **`Add('<Name>', fk<Name>, ...)`-Aufruf** in derselben Datei
  innerhalb von `BuildDetectorList` (oder analoger Position).
- [ ] **Test-Helper-Registrierung** in
  [`uTestFindingHelper.pas`](StaticCodeAnalyserForm/tests/uTestFindingHelper.pas):
  uses + `T<Name>Detector.AnalyzeUnit(Root, 'test.pas', Result);`-Zeile in
  `FindingsOf`. Bei file-basierten Detektoren analog in `FindingsOfFile`.

---

## Filter + UI

- [ ] **`TFilterMode`** in [`uFindingFilter.pas`](StaticCodeAnalyserForm/sources/UI/uFindingFilter.pas)
  — `fm<Name>` ans Enum-Ende anhängen.
- [ ] **`Matches()`-Case** in derselben Datei — `fm<Name>: Result := F.Kind = fk<Name>;`.
- [ ] **`KindSearchKeywords`** in derselben Datei — englische + deutsche
  Stichworte für die Freitextsuche.
- [ ] **IDE-Plugin-Combo**: in
  [`uIDEAnalyserForm.pas`](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas)
  in der `FFilterCombo.Items.AddObject`-Sequenz unter die passende
  Severity-Sektion (`--- Errors ---` / `--- Warnings ---` / `--- Hints ---`).
- [ ] **Standalone-Form-Combo**: in
  [`uMainForm.pas`](StaticCodeAnalyserForm/sources/UI/uMainForm.pas)
  in der `SeverityFilterCombo.Items.AddObject`-Sequenz analog.

---

## Help-Panel + Rule-Katalog

- [ ] **FixHint** in [`uFixHint.pas`](StaticCodeAnalyserForm/sources/Output/uFixHint.pas)
  — neuen `case` mit `Description` (über `_()`) + `Before` + `After`-
  Codeblock. Vor / Nach-Beispiele müssen realistisch und einfach
  lesbar sein — sie landen 1:1 im Help-Panel.
- [ ] **`rules/sca-rules.json`** — neuen Eintrag am Ende mit den Feldern
  `id` (SCA…), `kind`, `name`, `shortDescription`, `fullDescription`
  (lang, beschreibt Erkennungs-Strategie + Sonar-Quelle),
  `defaultSeverity`, `type`, `tags`, `detectorUnit`, `examples` (bad/good),
  `cleanCodeAttribute`, `impacts`. JSON valide halten (Komma vor dem
  neuen Eintrag).

---

## Lokalisierung

- [ ] **Runtime-Pfad** in
  [`uLocalization.pas`](StaticCodeAnalyserForm/sources/UI/uLocalization.pas)
  (`BuildDeMap`) — Combo-Label-Übersetzung + ggf. FixHint-Description.
  Umlaute über `#$XX`-Notation (`'#$E4'` = ä, `'#$F6'` = ö, `'#$FC'` = ü,
  `'#$DF'` = ß).
- [ ] **dxgettext-Pfad** in [`i18n/de.po`](i18n/de.po) — `msgid` / `msgstr`-
  Paar. Vor Commit Pair-Count prüfen (`msgid` = `msgstr`).

---

## Projektdateien

- [ ] **`StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj`** —
  `DCCReference Include="sources\Detectors\u<Name>.pas"`
  alphabetisch zwischen die bestehenden Einträge.
- [ ] **`StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dproj`** —
  `DCCReference Include="..\StaticCodeAnalyserForm\sources\Detectors\u<Name>.pas"`
  alphabetisch zwischen die bestehenden Einträge.
- [ ] **`StaticCodeAnalyserForm/tests/TestProject.dproj`** —
  `DCCReference Include="uTest<Name>.pas"` für die Test-Unit. Der Detektor
  selbst wird über `DCC_UnitSearchPath` aufgelöst (keine separate
  DCCReference nötig).
- [ ] **Encoding-Check**: nach jedem dproj-Edit BOM (`EF BB BF`) + CRLF
  verifizieren — PowerShell-Snippet:
  ```powershell
  $b = [IO.File]::ReadAllBytes('PATH'); ('{0:X2} {1:X2} {2:X2}' -f $b[0],$b[1],$b[2])
  ```

---

## Doku

- [ ] **`DETECTORS.md` + `DETECTORS_de.md`** — Status ✅, Unit-Name in die
  passende Severity-Tabelle eintragen. Falls neue Kategorie:
  Cluster-Abschnitt aufnehmen (Vorbild: SonarDelphi-Migration-Cluster
  SCA120-131).
- [ ] **Summary-Zähler** in beiden Files aktualisieren wenn der Cluster
  einen Eintrag wachsen soll.
- [ ] **`README.md` + `README_de.md`** — Pascal-Detektor-Count im Header
  + im Feature-Block bumpen wenn merklich.

---

## Sanity-Checks vor Commit

- [ ] **Build**: `msbuild` über alle drei dproj-Dateien grün.
- [ ] **Tests**: DUnitX-Runner grün — neuer Detektor liefert die in den
  Tests asserteten Counts.
- [ ] **`git diff --stat`** scannen: betroffen sind typisch ~10 Files
  (siehe oben). Fehlt einer, hat das Boilerplate ein Loch und der
  Detektor zeigt zur Laufzeit Edge-Effekte (z. B. keine Combo-Filter-
  Option oder kein FixHint-Panel).

---

## Beispiel-Cluster

Letztes komplettes Rollout-Beispiel: **SCA132 ExceptionTooGeneral +
SCA133 RaiseOutsideExcept** (2026-05-20). Diff-Größe: ~10 Touch-Points
× 2 Detektoren = ~20 Datei-Änderungen.
