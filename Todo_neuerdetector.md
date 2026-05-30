# Default-TODO: Neuen Detektor implementieren

Checkliste für jeden neuen Detektor — abhakbar von oben nach unten.
Alle Touch-Points sind hier dokumentiert, damit nichts vergessen wird
(Compile-Fehler durch fehlende DCCReferences, Tests die den Detektor
nicht sehen, fehlende Combo-Einträge in nur einer der zwei Formen, ...).

Stand: 2026-05-30 — letzter Lauf SCA162 (InsecureCryptoAlgorithm) +
SCA163 (CommandInjection). Davor: SCA132/133-Rollout (2026-05-20).

---

## Aktueller Lauf — 2026-05-30: SCA162 + SCA163

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
