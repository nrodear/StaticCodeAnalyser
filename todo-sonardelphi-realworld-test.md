# TODO — SonarDelphi-Realworld-Test (False-Positive-Bekaempfung)

> **Status (2026-05-17)**: 47 SonarDelphi-Style-Detektoren aus Phase 1 sind
> implementiert (SCA060-SCA106) und produzieren auf realen Codebases
> deutlich mehr False Positives als auf den Unit-Tests. Dieser Plan
> sammelt die bekannten FP-Muster und sortiert die Mitigation nach
> Aufwand / Nutzen.

---

## Erkannte FP-Familien

### 1. Cross-Unit-Visibility (CanBeUnitPrivate / CanBeStrictPrivate / CanBeProtected / UnusedPublicMember)

**UPDATE (single-file-Refactor):** Der Detektor konsultiert seit dem Refactor
KEINEN globalen Symbol-Index mehr — alle Visibility-Findings sind single-file-
basiert. CanBePrivate wurde in zwei Varianten gesplittet:

- **CanBeUnitPrivate** (SCA050): Member wird im aktuellen Unit referenziert
  (Sibling-Klasse / Top-Level-Code) → Delphi-`private` (unit-scope) reicht.
- **CanBeStrictPrivate** (SCA107): Member wird AUSSCHLIESSLICH von Methoden
  der eigenen Klasse gerufen → `strict private` (class-scope, D2007+).

Die "Cross-Unit-FP-Familie" entfällt damit by-design: der Detektor BEHAUPTET
gar nicht mehr cross-unit Wissen zu haben; der Compiler verifiziert per
E2361 ob ein versteckter externer Konsument existiert. Die alten 4 FP-
Quellen unter dieser Sektion bleiben für die Historie sichtbar.

**Status**: Teil-fixed. `AnalyzeLeaks(FileName, ProjectRoot, ...)` baut den
Symbol-Index ueber das ganze Projekt auf, `TStaticFiles.FindProjectRoot`
walked zu `.dproj`/`.dpk`/`.dpr`/`.git`. Standalone-Form +
IDE-Plugin-Runner + Watch-Mode benutzen den Resolver.

**Restliche FP-Quellen**:
- [ ] Wenn der Walker keinen Projekt-Marker findet (z.B. einzelne .pas in
      einem nicht-Delphi-Repo), bleibt nur das Datei-Verzeichnis als
      Scope. -> Konfigurierbarer `analyser.ini [Scan] ProjectRoot=` als
      Override.
- [ ] DPK-Dateien: ein Plugin-Repo mit nur `.dpk` (kein `.dproj`) sollte
      schon abgedeckt sein — verifizieren.
- [ ] Cross-`type`-Hierarchie: wenn die public-Methode in `TBase` deklariert
      und nur in `TBaseSubclass.Run` benutzt wird, kann der bisherige
      Sub-Class-Refs-Pfad versagen wenn die Subklasse in einer anderen
      Unit liegt.
- [ ] **Cross-PROJECT-Referenzen** (neu, 2026-05-17): wenn ein Symbol nur
      in einem konsumierenden Plugin/Sibling-Projekt benutzt wird, sieht
      der Cross-Unit-Index die Referenz nicht (Index baut nur die
      angefragte Datei + Projekt-Root-Walk). Konkretes Beispiel: drei
      Methoden in `TSonarConfigResolver` (`LoadToken`, `DefaultIniPath`,
      `ProjectPropsPath`) wurden als private vorgeschlagen — nur die
      StaticCodeAnalyserIDE-DPK referenziert sie. -> Resolver muss bei
      `.groupproj` zusaetzlich Sibling-`.dproj`/`.dpk` einsammeln und
      deren Source-Dirs in den Symbol-Index aufnehmen. Workaround:
      Methoden public belassen mit `// cross-project: ...`-Hinweis.

### 2. `IsUtilityClass` zu eng / zu weit (CanBeUnitPrivate / CanBeStrictPrivate)

**Status**: Fixed in `5496fc5` — Utility-Klasse = nur class-methoden,
keine Felder, keine Properties, kein Konstruktor. Parser markiert
`class function`/`class procedure` im TypeRef mit `;class`.

**Restliche FP-Quellen**:
- [ ] `record` mit `class function` (z.B. `TFindingHelper = record class function ...`)
      — Parser-Pfad noch nicht angepasst. Pruefen.
- [ ] Abstrakte Basisklassen (`procedure DoIt; virtual; abstract;`) ohne
      Konstruktor und ohne Felder werden aktuell NICHT als Utility-Class
      klassifiziert (richtig), und die einzelnen Member werden durch
      `IsInheritanceHook` gefiltert. Spot-Check auf reale Cases.

### 3. `TautologicalBoolExpr` mit String-Argumenten

**Status**: Fixed in `2514f67` — Lhs/Rhs werden jetzt aus Line (nicht
Clean) extrahiert. String-Inhalt wird im Norm()-Vergleich erhalten.

**Restliche FP-Quellen**:
- [ ] Kommentare in String-Form (`'{$IFDEF}'`-Patterns) sollten
      durchlaufen, keine Operator-False-Matches geben.
- [ ] Multi-Line-Strings (heredoc-aehnliche Konstrukte ueber `+`-Konkatenation)
      — Detector setzt Norm() ueber den ganzen Lhs/Rhs ab; lange
      Konkatenations-Ketten koennten zu langen identischen Norms fuehren.

### 4. `Ctor/DtorWithoutInherited` auf Forward-Decls

**Status**: Fixed in `33a161c` — `FindBodyBlock(M) = nil` skippt
Klassen-Body-Signaturen. Nur echte Implementierungen werden geprueft.

**Restliche FP-Quellen**:
- [ ] Generische Klassen `TFoo<T> = class ... constructor Create; ...`
      — Generic-Body-Erkennung im Parser pruefen.
- [ ] Interposer-Klassen (`TButton = class(Vcl.StdCtrls.TButton)`)
      — Konstruktor optional, sollte nicht meckern.

### 5. `EmptyBlock` auf Methoden-Bodies

**Status**: Fixed in `690d883` — `IsRoutineBody` filtert `procedure`/
`function`/`constructor`/`destructor` als Vorgaenger. `EmptyMethod`
(SCA-original) ist alleine zustaendig.

**Restliche FP-Quellen**:
- [x] `try ... finally end;` mit leerem finally — kollidiert mit
      `EmptyFinallyBlock` (SCA083). **Geprueft 2026-05-17:** kein
      Overlap. `EmptyFinallyBlock` matcht ausschliesslich das Pattern
      `finally <ws> end` (kein `begin..end` dazwischen). `EmptyBlock`
      matcht nur `begin <ws> end` -- bei `try X finally begin end end`
      feuert nur `EmptyBlock` (nicht `EmptyFinallyBlock`, weil dort
      `begin` zwischen `finally` und `end` steht). Beide Detektoren
      sind syntax-partitioniert.

### 6. `ConsecutiveVisibility` Same-Line-Pattern

**Status**: Fixed in `bd71831` — `LineHasContentAfter` erkennt
`public procedure A;` als Section-mit-Member.

**Restliche FP-Quellen**:
- [ ] `strict private` als Section-Header (zwei-Wort-Keyword): wird das
      korrekt geparst und gegen `private` abgegrenzt?

### 7. Vermutete weitere FP-Klassen (zu pruefen)

#### 7a. `BeginEndRequired` (SCA101)
Heavy Style-Debatte. Code-Bases mit Konvention "if X then Y;" fuer Single-
Statement bekommen massenhaft Treffer.
- [ ] Profile-Default: aus.
- [ ] `analyser.ini [Detectors] EnforceBeginEnd=false` als Default.

#### 7b. `LowercaseKeyword` (SCA064)
Falls die Codebase ein Style-Guide hat der UpperCase-Keywords toleriert
(z.B. `BEGIN`/`END` in Legacy-Pascal), gibts hunderte Treffer.
- [ ] Profile-Default: nur aktiv im `strict`-Profile.

#### 7c. `TypeName` / `FieldName` / `MethodName` (SCA103/104/106)
Naming-Conventions sind projektabhaengig. T-/F-/I-Prefix ist Delphi-
RTL-Standard, aber FreePascal-Codebases und einzelne Frameworks
weichen ab.
- [ ] Profile-Default: aus.
- [ ] Phase-2-Framework: `[Naming] TypePrefix=T,P,I,E` konfigurierbar
      machen.

#### 7d. `CommentedOutCode` (SCA070)
Heuristik (>=2 Marker) macht Treffer auf legitime Doc-Kommentare die
zufaellig `:=` oder `;` enthalten.
- [ ] Strengere Heuristik: nur Treffer wenn der Inhalt eines
      `// `-Kommentars MIT TrailingSemicolon ENDS (`...;`) + mindestens
      einen Statement-Keyword enthaelt.
- [ ] XML-Doc-Style `/// <param>...</param>` skippen.

#### 7e. `NestedTry` (SCA090)
Heuristik via `try`-`end`-Depth ueberzaehlt `end` von case/record/class.
False positives bei tiefer Schachtelung.
- [ ] AST-basiert reimplementieren sobald der Parser nested `try`-Bloecke
      sauber tracken kann.

#### 7f. `DigitGrouping` (SCA069)
Schwellwert 5 ist aggressiv — `9999` ist OK, `10000` plopt sofort.
- [ ] Default-Schwelle auf 6 hoch (1_000_000 ist die kanonische
      Verbesserung; 5-stellig ist Grauzone).
- [ ] `[Detectors] DigitGroupingThreshold=N` konfigurierbar.

#### 7g. `GroupedDeclaration` (SCA076)
`A, B: Integer;` ist in Parameter-Listen die idiomatische Form
(`procedure Foo(const A, B: Integer)`). Aktuell zaehlt das auch als
GroupedDeclaration.
- [ ] Parameter-Listen ausnehmen.

---

## Strategie / Phasen

### Phase A — Profile-Tuning (1-2 Tage)
Statt jeden Detektor einzeln zu fixen: Default-Profile anpassen. Im
`ide-fast`- und `default`-Profile die Style-/Convention-Detektoren mit
hohem Noise-Faktor (BeginEndRequired, LowercaseKeyword, naming-Triade,
CommentedOutCode) deaktivieren. User kann `strict` waehlen wenn er sie
will.

- [ ] `uRuleProfiles.pas` (oder vergleichbar): Default-Profile updaten.
- [ ] `analyser.ini`-Template mit Erklaerung welche Profile welche Rules
      aktivieren.

### Phase B — Realworld-Korpus-Test (2 Tage)
Den Analyser auf 3-5 grosse Open-Source-Delphi-Projekte werfen
(Project JEDI VCL, mORMot2, Spring4D, FreePascal-RTL) und die
False-Positive-Rate messen.

- [ ] Korpus klonen (`tests/realworld-corpus/`)
- [ ] Skript `analyse-corpus.ps1`: rekursive Analyse pro Repo, Summary-
      JSON mit Counts pro Detector + Profile
- [ ] FP-Quote-Tabelle (Rules mit > 30% manuell als FP klassifiziert
      werden zu Phase-2-Framework migriert / suppressed by default).

### Phase C — Per-Rule-Refinement (3-5 Tage)
Die Top-N FP-produzierenden Rules aus Phase B nach Liste oben fixen.

- [ ] Pro Rule: Test mit reproducer aus dem Realworld-Korpus, Fix,
      Regression-Test im Plugin-Test-Suite.

### Phase D — Suppression-UX (1 Tag)
Bulk-Suppression in der IDE-UI:
- [ ] Rechtsklick auf Befund -> "Diese Rule fuer diese Datei suppress"
      (schreibt `.scaignore`-Eintrag im Projekt-Root).
- [ ] Rechtsklick auf Detector im Top-N-Panel -> "Diese Rule
      projektweit deaktivieren".

---

## Tracking

| Phase | Datum | Status |
|---|---|---|
| A — Profile-Tuning | _tbd_ | offen |
| B — Realworld-Korpus | _tbd_ | offen |
| C — Per-Rule-Refinement | _tbd_ | offen |
| D — Suppression-UX | _tbd_ | offen |

---

## Bereits gefixte FP-Vorfaelle (Audit-Trail)

| Commit | Was |
|---|---|
| `ad0632b` | LegacyInitializationSection — walk-back depth-tracking fuer Methoden-Bodies |
| `33a161c` | Ctor/DtorWithoutInherited + TwiceInheritedCalls — FindBodyBlock-Guard fuer Forward-Decls |
| `690d883` | EmptyBlock — Methoden-Bodies skippen (uEmptyMethod ist dafuer zustaendig) |
| `bd71831` | ConsecutiveVisibility — Same-Line `public procedure A;` als Section-mit-Member erkennen |
| `2514f67` | TautologicalBoolExpr — String-Argumente bleiben in Lhs/Rhs erhalten |
| `5496fc5` | VisibilityCheck IsUtilityClass — nur Klassen mit ALLEN class-Methoden skippen |
| `a5769c4` | VisibilityCheck — Utility-Class-Skip eingefuehrt (initial) |
| `ed1c080` | AnalyzeLeaks(FileName, ProjectRoot, ...) — Cross-Unit-Index im Single-File-Scan |
| `c046d8f` | TStaticFiles.FindProjectRoot — `.dproj`/`.dpk`/`.dpr`-Walk-Up |
