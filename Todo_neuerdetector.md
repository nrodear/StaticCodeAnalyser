# Default-TODO: Neuen Detektor implementieren

Checkliste für jeden neuen Detektor — abhakbar von oben nach unten.
Alle Touch-Points sind hier dokumentiert, damit nichts vergessen wird
(Compile-Fehler durch fehlende DCCReferences, Tests die den Detektor
nicht sehen, fehlende Combo-Einträge in nur einer der zwei Formen, ...).

Stand: 2026-05-20 — abgeleitet aus dem SCA132/133-Rollout
(uExceptionTooGeneral + uRaiseOutsideExcept).

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
