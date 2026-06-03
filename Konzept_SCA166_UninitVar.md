# Konzept SCA166 — UninitVar (uninitialised variable)

> **Note zur ID:** Die historisch in `DETECTORS.md` als Sonar-Slot #16
> reservierte ID `SCA016` ist seit langem durch `HardcodedPath`
> belegt. Dieser Detector nutzt daher `SCA166` (nach `SCA164`
> UnusedRoutine + `SCA165` UnusedSuppression).

Erkennt **lokale Variablen die auf mindestens einem Code-Pfad gelesen
werden, bevor sie auf demselben Pfad geschrieben wurden**.

Status: Konzept-Phase. Entkoppelt von Phase 2/3 der
[Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) — als
**konservatives MVP** ohne vollständige Symboltabelle (B.1) /
Expression-AST (B.2) bauchbar. Erweiterung Richtung voller
Flow-Analyse später, sobald B.1+B.2 erledigt sind.

Branch: `main` (Implementation direkt auf main).

---

## 1. Problem

Lokale Variablen die vor dem ersten Schreibzugriff gelesen werden,
sind ein klassischer Crash- bzw. Korruptions-Bug:

```pascal
procedure DoStuff;
var
  L : TStringList;            // (1) Local var deklariert, NICHT initialisiert
  Sum : Integer;              // (2) Local var deklariert, NICHT initialisiert
  i : Integer;
begin
  if SomeCondition then
    L := TStringList.Create;  // (3) nur DIESER Pfad weist L zu
  for i := 0 to 10 do
    Sum := Sum + i;           // (4) Sum gelesen vor erstem Write → undefined value
  L.Add('x');                 // (5) wenn SomeCondition=False → AV (L = nil/garbage)
end;
```

Pascal/Delphi initialisiert **nur Reference-Types** (`string`, dynamic
array, interface) automatisch auf nil/empty. Alle anderen Typen
(`Integer`, `Boolean`, record, Pointer, Klassen-Instanzen) haben
**undefined** Initial-Inhalte — was bei Klassen-Instanzen wie
`TStringList` typisch einen Access Violation auslöst, bei numerischen
Typen einen Garbage-Wert.

## 2. Was es heute gibt (Lücke)

| Quelle | Greift | Lücke |
|---|---|---|
| Delphi-Compiler **W1036** "Variable 'X' might not have been initialised" | viele Fälle, default-Hint | nicht in CI-Pipelines durchgereicht (oft auf Hint-Filter); pro File einzeln; bei `class`-Instanzen schweigt der Compiler in einigen Konstruktor-Pattern; springt nicht bei `Result`-Variable (siehe SCA020 ResultNotChecked) |
| [`uUnusedLocal.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedLocal.pas) | Variable **nie** gelesen | nicht: Variable gelesen, aber nicht zuerst geschrieben |
| [`uFreeWithoutNil.pas`](StaticCodeAnalyserForm/sources/Detectors/uFreeWithoutNil.pas) (Round 5) | `.Free` ohne `:= nil` bei Klassen-Feldern | unrelated |
| [`uUseAfterFree.pas`](StaticCodeAnalyserForm/sources/Detectors/uUseAfterFree.pas) | Use NACH `Free` | gegenteilig — wir wollen Use VOR erstem Init |
| DETECTORS.md Slot **#16** | 🔲 open seit v0.5 | weil "needs flow-analysis" |
| `rules/sca-rules.json` SCA166 | nicht registriert | reserviert |

**Konkretes Beispiel aus dem Self-Test-Corpus** (`Output\Win64 Release\StaticCodeAnalyser.d12.exe --path D:\git-demos\delphi --full --profile strict`) das aktuell durch alle Detektor-Maschen fällt:

```pascal
procedure Reverse;
var
  s, t : string;        // string -> Pascal initialisiert automatisch
  n : Integer;          // Integer -> Garbage!
  i : Integer;
begin
  Write('zahl ?');
  ReadLn(n);
  s := IntToStr(n);
  for i := 1 to Length(s) do
    t := t + s[Length(s) - i + 1];   // t lesen, vor erstem Write
  WriteLn(t);
end;
```

Pascal initialisiert `t` (string) implizit, ABER der Code-Smell bleibt:
`t := t + ...` ohne explizites `t := ''`-Anker macht den Reader stutzen.
Bei `n : Integer; if n > 0 then ... else WriteLn(n)` wäre es ein echter
Bug.

---

## 3. Recherche — wie andere Tools das lösen

### 3.1 Delphi-Compiler W1036 / H2077

**Funktionsweise:** Compiler trackt pro Variable + pro Basic-Block ob
sie auf dem aktuellen Pfad geschrieben wurde. Bei `var X: Integer;
if cond then X := 1; WriteLn(X);` → H2077 (Hint) bzw. W1036 (Warning).

**Limitierungen die wir abdecken können:**
- W1036 ist **per default ein Hint** — viele CI-Pipelines filtern Hints
  → Bug schlüpft durch.
- Compiler analysiert nur **eine Compilation-Unit** (ähnlich zu uns).
- Bei `class`-Instanzen verzichtet Delphi auf strict-Tracking in
  einigen Konstruktor-/`out`-Parameter-Pattern.
- W1036 löst bei **`with`-Statements** häufig nicht aus (eigene
  Code-Smell-Klasse).

### 3.2 FixInsight (TMS)

Hat **InitVarsBeforeUse** (Pi3092). Single-File, AST-basiert. Algorithmus
laut [Doku](https://www.tmssoftware.com/site/fixinsight.asp):

- Sammelt alle lokalen Var-Deklarationen pro Methode.
- Pro Var iteriert über die Methoden-Statements in Reihenfolge.
- Markiert Var als "initialised" bei direktem Schreibzugriff
  (`X := ...`, `Inc(X)`, `Read(X)`, `for X := ...`, passing as `out`/`var`
  Parameter).
- Markiert als "read" bei jedem anderen Vorkommen.
- Wenn ein Read VOR dem ersten Write → flag.

**Wichtige Pragma:** Branching wird konservativ aufgelöst — `if`/`case`/`try-except`
gilt als "Variable könnte hier geschrieben werden" und macht alle
nachfolgenden Reads "safe", auch wenn nur der then-Zweig schreibt. Das
ist eine bewusste Trade-off-Entscheidung: lieber falsche Negatives als
falsche Positives.

### 3.3 SonarDelphi

**Keine entsprechende Rule** in der offiziellen Liste — SonarDelphi
verlässt sich hier auf den Delphi-Compiler-Hint.

### 3.4 Peganza Pascal Analyzer

**HBNI11 — "Has been read but not initialized"**. Vollständige
Flow-Analyse per AST + Pfad-Tracking. Output enthält die konkrete
Read-Position + die Schreibstelle die fehlt.

### 3.5 Fazit der Recherche

Drei Tracks:
1. **Konservativ (FixInsight-Style)** — Single-Method, sequentieller
   Walk, Branch = "safe assumption". Wenig FPs, einige False-Negatives.
2. **Compiler-Style (Delphi W1036)** — basic-block-aware aber nicht
   path-sensitive. Gut für die häufigen Fälle.
3. **Voll path-sensitive (Peganza)** — pro Pfad tracken, alle
   Verzweigungen aufrollen. Korrekt aber teuer und braucht echten
   CFG-Builder.

**SCA166 zielt auf Track 1+2 hybrid**: konservativ + ein basic-block-
Modell. Track 3 ist ein Phase-3-Thema (B.2 Expression-AST + B.1
Symboltabelle).

---

## 4. Vorhandene Infrastruktur die wir wiederverwenden

| Helper | Was er kann | Quelle |
|---|---|---|
| `nkMethod` / `nkLocalVar` / `nkAssign` / `nkCall` / `nkRef` | Basis-Knoten im AST | [`uAstNode.pas`](StaticCodeAnalyserForm/sources/Parsing/uAstNode.pas) |
| `MethodNode.FindAll(nkLocalVar)` | Liste der Var-Deklarationen pro Methode | analog [`uUnusedLocal.pas:42`](StaticCodeAnalyserForm/sources/Detectors/uUnusedLocal.pas) |
| `AcquireLines` / `ReleaseLines` | gecachter File-Read | [`uFileTextCache.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uFileTextCache.pas) |
| `TDetectorUtils.StripStringsAndComments` | Identifier-Suche FP-frei | [`uDetectorUtils.pas`](StaticCodeAnalyserForm/sources/Common/uDetectorUtils.pas) |
| `TDetectorUtils.ScanCodeLine` + State | `//`/`{}`/`(* *)` korrekt | [`uDetectorUtils.pas`](StaticCodeAnalyserForm/sources/Common/uDetectorUtils.pas) |
| `LooksLikeRealLocalVar(Lines, LineNo)` | Filtert nested-Routine-Headers die der Parser als `nkLocalVar` ausliefert | [`uUnusedLocal.pas:50`](StaticCodeAnalyserForm/sources/Detectors/uUnusedLocal.pas#L50) — als Helper hochziehen |
| `TLeakFinding.SetKind(K, AConfidence)` | Kind + Severity + Confidence in einem Schritt (v0.9.8-Overload) | [`uMethodd12.pas`](StaticCodeAnalyserForm/sources/Common/uMethodd12.pas) |

---

## 5. SCA166-Algorithmus (Phasen)

### Phase A — Var-Inventur pro Methode

AST-Walk: `MethodNode.FindAll(nkLocalVar)`. Für jede Deklaration
sammeln:

```pascal
TLocalVarInfo = record
  Name      : string;        // Original-Name (case-preserved)
  NameLow   : string;        // lower-case für Match
  TypeName  : string;        // 'Integer', 'TStringList', 'Boolean', ...
  IsManaged : Boolean;       // string / dynamic array / interface → vom RTL initialisiert
  DeclLine  : Integer;       // 1-based
  // gefüllt in Phase C
  FirstWriteLine : Integer;  // 0 wenn nie geschrieben
  FirstReadLine  : Integer;  // 0 wenn nie gelesen
  ConditionalWrite : Boolean;// in if/case/try → "weicher" Write
end;
```

**Skip-Regeln** vor Phase B:
- Name beginnt mit `_` → Konvention "intentional"
- `IsManaged = True` und Skip-Heuristik aktiv (siehe Phase E)
- `LooksLikeRealLocalVar(Lines, DeclLine)` = False → Parser-Artefakt
- Methode ist `asm`-Block → Parser zerlegt nicht, kein zuverlässiger Scan

### Phase B — Body-Token-Iteration (sequentiell)

Walk durch die Statements der Methode in Quell-Reihenfolge.

Klassifikation pro Token-Match (`Var-Name` in Code-stripped Line):

| Pattern | Klasse | FirstWrite-Update | FirstRead-Update |
|---|---|---|---|
| `X := ...` | Write | wenn = 0 → setzen | — |
| `Inc(X)` / `Dec(X)` | Read-Modify-Write | wenn = 0 → setzen | wenn = 0 → setzen (read kommt vor write) → **FLAG** |
| `Read(X)` / `ReadLn(X)` / `Read(F, X)` | Write | wenn = 0 → setzen | — |
| `Procedure(X, Y)` mit `var`/`out` Parameter | Write | wenn = 0 → setzen | — |
| `for X := A to B do` | Write (loop-init) | wenn = 0 → setzen | — |
| `for X in Container do` | Write (enumerator) | wenn = 0 → setzen | — |
| jede andere Erwähnung (RHS, Vergleich, Cast, Param) | Read | — | wenn = 0 → setzen |

**Wichtige Konvention:** Wir verlassen uns auf den AST für Statement-
Grenzen + auf `TDetectorUtils.ScanCodeLine` für String/Kommentar-
Stripping. **Kein Versuch von String-Concat-Tracking** o.ä.

### Phase C — Conditional-Write-Marker (Branch-Awareness konservativ)

Wenn das Write in `if Cond then X := ...` ohne `else`-Zweig steht,
oder in `case`-Branch ohne Default, oder im `try`/`except`/`finally`-
Body: `ConditionalWrite := True`.

Heuristik zur Erkennung: gehe vom Write-Statement aufwärts im AST,
finde nächsten `nkIfStmt` / `nkCase` / `nkTry`-Vorfahren bevor man
`nkMethod` erreicht. Wenn gefunden → ConditionalWrite.

Wenn `if-then-else` mit Write in BEIDEN Zweigen: nicht conditional
(garantiert). Dafür müssen wir prüfen ob ein passendes Sibling-Write
existiert. **Phase A.MVP:** wir prüfen das NICHT — alle if/case/try-
Writes sind conditional. → false-positives bei sicheren if-else-Mustern.
**Phase B-Erweiterung:** sibling-Write-Check.

### Phase D — Klassifikation + Emit

| Zustand | Befund | Confidence |
|---|---|---|
| `FirstRead = 0` (nie gelesen) | **kein** SCA166 — fällt unter SCA019 (`UnusedLocal`) | — |
| `FirstWrite = 0` und `FirstRead > 0` | **SCA166** — gelesen, nie geschrieben | `fcHigh` |
| `FirstWrite > 0` und `FirstRead > 0` und `FirstRead < FirstWrite` | **SCA166** — Lese-Zeile vor Schreib-Zeile auf jedem Pfad | `fcHigh` |
| `FirstWrite > 0` und `FirstRead < FirstWrite` und `ConditionalWrite = True` | **SCA166** — Lese-Zeile kann ohne Write passieren | `fcMedium` (FP-Risiko bei if-else mit beidseitigem Write) |
| `FirstWrite > 0` und `FirstRead >= FirstWrite` | clean | — |
| `IsManaged = True` und kein Skip-Flag | **SCA166 nur als Code-Smell-Hint** (Pascal hat schon initialisiert, aber expliziter `X := ''` Anker fehlt) | `fcLow` (default-off, opt-in via INI) |

### Phase E — FP-Guards (Skip-Liste, in dieser Reihenfolge)

| # | Guard | Begründung |
|---|---|---|
| 1 | Name beginnt mit `_` | Konvention "intentional unused/uninit" |
| 2 | `IsManaged = True` und Profile ≠ `paranoid` | Pascal initialisiert managed types — selten ein echter Bug |
| 3 | Methode ist `asm`-Block (komplett) | Parser zerlegt nicht zuverlässig |
| 4 | Methode steht in einer Datei matching `IsTestFixturePath` und Profile-Default schließt das aus | Test-Demos haben absichtliche Bugs |
| 5 | Variable in `try-finally`-Block mit Cleanup-Read (`if Assigned(X) then X.Free`) | Häufiges Pattern: `var X` ohne Init, im `try` zugewiesen, im `finally` mit Assigned-Guard freigegeben → der `Assigned`-Check IST der defensive Read |
| 6 | Compiler-Direktive `{$WARN VARIANT_AS_FUNC OFF}`-ähnlich im Method-Body suppressiert SCA166 | Per-Method-Opt-Out via `// noinspection UninitVar` (existiert schon über `uSuppression`) |

Guard #5 (try-finally-cleanup) braucht Sonderlogik: wenn der einzige
Read im `finally`-Body steht und ein Write im `try`-Body existiert,
ist es kein UninitVar — das ist defensive Cleanup.

---

## 6. AST-Voraussetzungen — was haben wir, was fehlt

| Brauche | Haben wir | Lücke |
|---|---|---|
| `nkLocalVar` mit Name + TypeRef | ✅ ([`uAstNode.pas`](StaticCodeAnalyserForm/sources/Parsing/uAstNode.pas)) | TypeRef ist String, kein Typ-Lookup → IsManaged-Erkennung per Stringlist |
| `nkAssign` mit LHS-Identifier | ✅ | LHS-Parsing ist `Obj.Member` mit Punkt — Plain `X := ...` ist `Name = 'X'`, OK |
| `nkCall` mit Arg-Position | 🟡 | Arg-Liste in `Args` aber `var`/`out`-Marker fehlt → wir können nicht zuverlässig erkennen ob `DoStuff(X)` ein Write ist. **Workaround:** Pessimistic-Read (jeder Call-Arg = Read), bekannte Schreib-Procs allowlisten (`Read`, `ReadLn`, `BlockRead`, `FillChar`, `Move`, `New`, `GetMem`) |
| `nkRef` (Read-only Identifier-Use) | 🟡 | Existiert, aber Index-Logik im `uSymbolReferenceIndex` nutzt es nicht — siehe A.3+ Roadmap |
| `nkIfStmt` / `nkCase` / `nkTry` als AST-Knoten | ✅ | Für Phase-C Conditional-Branch-Detection |
| `nkFor` mit Loop-Variable | ✅ | Loop-Var = Write |
| Statement-Order im AST | ✅ | `Children` in Quell-Reihenfolge |
| `for var I := ...` (inline-var) | 🟡 | Parser erkennt inline-var, aber Scope ist nur der for-Body → unsere Var-Inventur darf das nicht als unitialisiert lesen |

**Gap-Workaround:** für Call-Args die nicht sicher Write sind →
Pessimistic-Read. False-Negatives akzeptabel (Detektor schweigt).

---

## 7. Architektur

### 7.1 Layering + Dep-Direction

```
+--------------------------+
|  uUninitVar.pas          |  Detector (uses ↓)
+--------------------------+
            |
            v
+--------------------------+
|  uAstNode (Parsing)      |
|  uFileTextCache          |  Infrastructure
|  uDetectorUtils          |  Common (StripStringsAndComments,
|  uSCAConsts (KIND_META)  |          LooksLikeRealLocalVar lift)
|  uMethodd12 (TLeakFinding)|
+--------------------------+
```

Direction strict: Detector → Infrastructure → Common. Keine
Rück-Imports. Detector ist **stateless** (class procedure
`AnalyzeUnit/AnalyzeMethod`), keine Klassen-Instanzen über Calls
hinweg.

### 7.2 Klassen-Design

```pascal
unit uUninitVar;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUninitVarDetector = class
  public
    // Unit-level entry: ruft AnalyzeMethod fuer jede Methode der Unit.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    // Per-Method (sub-routine entry) - testbar isoliert.
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache, uDetectorUtils;

type
  TVarUsageInfo = record
    Name             : string;
    NameLow          : string;
    TypeName         : string;
    IsManaged        : Boolean;
    DeclLine         : Integer;
    FirstWriteLine   : Integer;
    FirstReadLine    : Integer;
    ConditionalWrite : Boolean;
    Reported         : Boolean;
  end;

  // Map name (lowercase) -> Index in TList<TVarUsageInfo>
  TVarMap = TDictionary<string, Integer>;
```

Drei interne Phasen als private class function:

```pascal
class function CollectLocalVars(MethodNode: TAstNode;
  Lines: TStringList): TList<TVarUsageInfo>;

class procedure WalkMethodBody(MethodNode: TAstNode;
  Vars: TList<TVarUsageInfo>; VarMap: TVarMap);

class procedure EmitFindings(Vars: TList<TVarUsageInfo>;
  const FileName: string;
  Results: TObjectList<TLeakFinding>);
```

### 7.3 Pipeline-Integration

Registrierung in [`uStaticAnalyzer2.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uStaticAnalyzer2.pas)
Detector-Loop:

```pascal
AddD('UninitVar', fkUninitVar,
  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>)
  begin
    TUninitVarDetector.AnalyzeUnit(R, F, L);
  end);
```

Position: nach `UnusedLocalVar` und vor `UseAfterFree` — semantisch
zusammengehörige Local-Var-Lifecycle-Detektoren in Reihe.

### 7.4 Coupling-Inventar

- **Auf gFileTextCache** (Acquire/Release) — nur für Phase-Source-Line-
  Verifikation (`LooksLikeRealLocalVar`-Helper), nicht für AST.
- **Auf gSymbolRefIndex** — **NEIN**. UninitVar ist strikt single-method,
  kein Cross-Unit-Bezug.
- **Auf gAstFileCache** — implizit über `UnitNode` das vom Caller
  kommt; kein direkter Cache-Zugriff im Detector.
- **Globaler State im Detector:** keiner — alle Daten leben im Stack
  pro `AnalyzeMethod`-Call.

### 7.5 Test-Architektur

```
StaticCodeAnalyserForm/tests/uTestUninitVar.pas
├── 8 Positive-Tests (verschiedene FP-Pattern, jeder muss flaggen)
├── 12 Negativ-Tests (FP-Trigger die NICHT flaggen dürfen)
├── 4 Edge-Cases (asm-Block, inline-var, try-finally-cleanup, _-Prefix)
└── 2 Performance-Tests (sehr lange Methode → unter 50ms)
```

Plus **Golden-Corpus-Reproducer** in
`tests/golden-corpus/fp-reproducers/fp06_UninitVar_TryFinally.pas`
sobald der erste FP nach Live-Audit gefunden wird.

### 7.6 Erweiterbarkeit (B.1 / B.2 Aufruf)

Wenn Phase 3 (echte Symboltabelle + Expression-AST) später kommt,
sind Erweiterungspunkte:

- `CollectLocalVars` profitiert von der Symboltabelle für korrektes
  `var`/`out`-Parameter-Erkennen.
- `WalkMethodBody` kann auf Expression-AST upgrades um Sub-Expression-
  Reads (`X[i] := Y`) korrekt zu klassifizieren — heute pessimistic.
- `ConditionalWrite`-Detection kann durch echten CFG (Phase 4 A.4)
  vom konservativen "alles in if/case = conditional" auf
  "if-else mit beidseitigem Write = unconditional" upgegraded werden.

Jeder dieser Upgrades ist **drop-in** ohne API-Bruch.

---

## 8. Performance

### 8.1 Hot-Path-Analyse

Detector wird pro Unit gerufen. Per Unit:

```
for ClassNode in Classes do
  for Method in Class.Methods do
    AnalyzeMethod(Method)

AnalyzeMethod kostet:
  1. FindAll(nkLocalVar)         → O(method-AST-nodes)
  2. CollectLocalVars            → O(#localvars) ≈ 0..20
  3. WalkMethodBody              → O(method-AST-nodes × #localvars)
  4. EmitFindings                → O(#localvars)
```

Bei einem Real-World-Korpus (2 600 Files × ~10 Methoden × ~5 LocalVars
× ~50 AST-Nodes pro Body) → **~6.5 Mio Inner-Loop-Iterationen** für
den ganzen Scan. Pro Iteration: ein Dictionary-Lookup (`VarMap.TryGet`).

Schätzung: **< 2s** add-on für `--profile strict` auf 2 600 Files.
Akzeptabel (Gesamtscan ~70s).

### 8.2 Allocation-Pattern

| Allokation | Häufigkeit | Mitigation |
|---|---|---|
| `TList<TVarUsageInfo>.Create` | 1× pro Methode (~26 000 pro Real-World-Scan) | Records statt Klassen → nur 1 TList-Alloc, keine 20 Record-Allocs |
| `TVarMap = TDictionary<string, Integer>.Create` | 1× pro Methode | Reuse über `Clear` nicht möglich (Methode = neue Scope), aber Dictionary mit ~5-20 Entries ist günstig |
| `FindAll(nkLocalVar)` | 1× pro Methode | Liefert eine TList die der Caller free-t — etabliert pattern |
| String-Allokationen für `NameLow := LowerCase(...)` | pro LocalVar (~130k Real-World) | unvermeidlich, aber `string` in Delphi ist Reference-counted + COW → günstig |

**Worst-Case:** sehr lange Methode (100+ Local-Vars + 1000 Statements)
→ Inner-Loop wird 100k Iter. Bei <1µs/Iter sind das ~100ms für DIESE
Methode. Realer Worst-Case in `uStaticAnalyzer2.RunAllDetectors` (~250
Statements) → ~25ms. Akzeptabel.

**Memory-Peak:** TVarMap + TList<TVarUsageInfo> sind kurzlebig (Scope =
`AnalyzeMethod`-Call), werden im finally-Block freigegeben. Kein
Memory-Wachstum über Scan-Dauer.

### 8.3 RegEx-Caching

Keine RegEx im Detector (operiert auf AST + simplem
Token-Pattern-Match via existing `TDetectorUtils.FindWholeWordLower`).

### 8.4 Cache-Reuse

- `AcquireLines` einmal pro `AnalyzeUnit` (NICHT pro AnalyzeMethod) —
  alle Methoden teilen sich die TStringList für `LooksLikeRealLocalVar`-
  Checks.
- AST-Knoten kommen vom `gAstFileCache` aus dem Caller — kein
  Re-Parsing im Detector.

### 8.5 Skip-Pfade (Fast-Out)

In dieser Reihenfolge testen:

1. `MethodNode.FindAll(nkLocalVar).Count = 0` → return (keine
   LocalVars = nichts zu prüfen)
2. Methode ist asm-Block (TypeRef enthält `;asm`) → return
3. File matched `IsTestFixturePath(FileName, BaseDir)` und Profile
   filtert → return (eigentlich Post-Filter, aber Detector kann früh
   abbrechen wenn Profile dies signalisiert — heutiges Pattern in
   uVisibilityCheck)

### 8.6 Profiling-Hook

Mit `--time-detectors` (seit v0.9.7) wird der UninitVar-Detector
automatisch mitgemessen. Erwarteter Output:

```
UninitVar                  | calls: 26043  total: 1842ms  avg: 0.07ms
```

Wenn `avg > 0.5ms` → Profiling-Ziel, Verdacht auf O(n²) im Inner-Loop.

### 8.7 Worst-Case-Szenario

Pathologisch: eine generierte Datei mit einer einzigen Methode, 1000
Local-Vars, 10 000 Statements. Inner-Loop wird 10 Mio. Iter.
Geschätzt: ~5-10s für DIESE Methode. Mitigation: **Hard-Cap** —
wenn `#localvars > 200` ODER `#statements > 5000` → ohne UninitVar-
Analyse die Methode skippen (`fcLow`-Hint emittieren: "method too
large for uninit-analysis"). Cap-Werte konfigurierbar via INI:
`[Detectors] UninitVarMaxLocalVars = 200`,
`UninitVarMaxStatements = 5000`.

---

## 9. Konfiguration

### 9.1 INI-Keys

```ini
[Detectors]
UninitVarEnabled = true                ; default on
UninitVarFlagManagedTypes = false      ; string/array → fcLow Hint, default off
UninitVarMaxLocalVars = 200
UninitVarMaxStatements = 5000
UninitVarConditionalWriteMode = strict ; strict | lenient
                                       ;  strict  = ConditionalWrite immer fcMedium
                                       ;  lenient = nur if-ohne-else / case-ohne-else
                                       ;            als ConditionalWrite werten
```

### 9.2 Profile-Integration

| Profile | UninitVar enabled | Confidence-Filter |
|---|---|---|
| `default` | ja | fcMedium (= strict-Standard-Werte aktiv) |
| `strict` | ja | fcLow zugelassen (auch managed-type-Hints) |
| `selftest-quiet` | ja | fcMedium |
| `ide-fast` | ja (cheap genug) | fcHigh-only |
| `security` | nein | irrelevant |
| `bugs-only` | ja | fcHigh-only |

### 9.3 Suppression

Standard via `// noinspection UninitVar` — bereits durch `uSuppression`
abgedeckt sobald `fkUninitVar` im KIND_META registriert ist.

---

## 10. KIND_META + Rule-Catalog

`uSCAConsts.pas` ergänzen:

```pascal
TFindingKind = (
  ...
  fkUninitVar         // SCA166
);

KIND_META: array[TFindingKind] of TFindingKindMeta = (
  ...
  (Name: 'UninitVar'; FindingType: ftBug; DefaultSeverity: lsError),
);
```

`rules/sca-rules.json` ergänzen:

```json
{
  "id": "SCA166",
  "kind": "UninitVar",
  "name": "Uninitialised local variable",
  "shortDescription": "Local variable read before being assigned on every code path",
  "fullDescription": "...",
  "defaultSeverity": "Error",
  "type": "BUG",
  "tags": ["reliability", "memory-safety"],
  "configKey": "[Detectors] UninitVarEnabled",
  "detectorUnit": "uUninitVar.pas",
  "examples": { "bad": "...", "good": "..." }
}
```

`KindDefaultConfidence` in `uSCAConsts`: `fkUninitVar` NICHT in der
fcMedium-Liste → default `fcHigh`. Conditional-Write-Fälle setzen
Confidence per `SetKind(fkUninitVar, fcMedium)` direkt im Detector.

---

## 11. Roadmap

| Phase | Inhalt | Aufwand | Akzeptanz-Kriterium | Status |
|---|---|---|---|---|
| **MVP (Phase 1)** | Phase A-E ohne sibling-Write-Check + ohne CFG | 1-1.5d | 15 unit-tests grün, Real-World-Scan 0.7 Findings/File ohne Crash | ✅ commit 8e439ec |
| **Phase 2.1** | Sibling-Write-Check für if-then-else mit beidseitigem Write | 4-6h | `if cond then X := 1 else X := 2;` flaggt nicht mehr | 🔲 |
| **Phase 2.2** | Calls in `if`/`while`/`case`-Conditions als pessimistic-Write erkennen (Parser packt sie als TypeRef-String, kein nkCall-Walk) | 1d | `if not ReadFile(F, Buf, ...)` flaggt Buf nicht mehr falsch als unwritten | ✅ commit folgt — größter erwartbarer FP-Killer |
| **Phase 2.3** | Expression-Call-Walker auf nkAssign.RHS + nkForStmt.Range erweitern (gleicher Pfad wie 2.2, andere Knoten) | 1h | `Lines := AcquireLines(F, Cached)` registriert Cached als pessimistic-Write | ✅ commit folgt |
| **Phase 2.4** | **Nested-Method-Aware Walks** — Hits in inner procedures aus dem Outer-MethodNode-Walk ausklammern. Auditiert nach Audit-Sample `uConsoleRunner.pas:142` wo `i` von `ParseArgs` durch `Inc(i)` in nested `GetValue` als FirstWrite überschrieben wurde, echte Init `i := Low(Args)` ignoriert | 2h | nested-Methoden haben ihren eigenen AnalyzeMethod-Call, Outer-Detector überspringt sie | ✅ commit folgt |
| **Phase 2.5** | READ_ALLOWLIST erweitert: 30 → 56 Einträge (Windows-API Sleep/CloseHandle/WaitForSingleObject/..., zusätzliche String-Helper Trim/UpperCase/Pos/SameText, IsDebuggerPresent) | 1h | weniger pessimistic-Write bei Win-API-Calls | ✅ commit folgt |
| **Phase 2.6** | Source-Line-based Nested-Method-Detection als robuster Ersatz für Phase 2.4 (Parser entfernt Outer-MethodNode bei 'Headless-Method'-Pattern → AST-Walk findet nested nicht). Source-Scan nach `^\s{2,}(procedure\|function\|...)` + begin/end-Pair-Counting | 2h | uConsoleRunner.pas:142 `i` aus nested GetValue wird nicht mehr fälschlich als Read in ParseArgs gewertet | ✅ commit folgt |
| **Phase 3** | echter CFG-Builder (anstoßend an Konzept §A.4) | 3-5d | Komplexe try-except-finally + nested-if Fälle korrekt; Recall steigt, FP-Rate stabil | 🔲 |
| **Phase 4** | Symboltabelle (B.1 aus Konzept) integriert für korrektes `var`/`out`-Parameter-Erkennen | abhängig von B.1 | Pessimistic-Read durch exakte Read/Write-Klassifikation ersetzt | 🔲 |

Phase 1 (MVP) ist Stand-alone realisierbar OHNE Phase 2/3/4 der
Scanner-Qualität-Roadmap.

---

## 12. Test-Strategie

### 12.1 DUnitX-Suite (`uTestUninitVar.pas`)

**Positive Tests (MUST flag):**

1. `var n: Integer; if cond then n := 1; WriteLn(n);` — conditional-only
2. `var s: TStringList; s.Add('x');` — never written
3. `var i: Integer; for j := 0 to 10 do Sum := Sum + j;` — Sum used as
   write-via-read-modify
4. `var L: TList; try L.Add(0); finally L.Free; end;` — never
   constructed, used in try
5. `var n: Integer; case kind of A: n := 1; end; WriteLn(n);` — case
   ohne default
6. `var n: Integer; try ... except n := 0 end; WriteLn(n);` — write
   nur im except-Pfad
7. `var n: Integer; WriteLn(n);` — sofort gelesen ohne irgendeinen
   write
8. `var p: Pointer; if Assigned(p) then ...` — p in Assigned-Guard
   gelesen ohne vorherigen write

**Negativ Tests (MUST NOT flag):**

1. `var n: Integer; n := 0; WriteLn(n);` — sauber initialisiert
2. `var n: Integer; if cond then n := 1 else n := 2; WriteLn(n);` —
   sibling-write in else (Phase 2)
3. `var _temp: Integer; if cond then _temp := 1; WriteLn(_temp);` — `_`-prefix
4. `var L: TStringList; L := TStringList.Create; try L.Add('x'); finally
   L.Free; end;` — write before read in try
5. `var s: string; WriteLn(s);` — managed type, default `''`
6. `var arr: TArray<Integer>; WriteLn(Length(arr));` — managed dynamic array
7. `var n: Integer; ReadLn(n); WriteLn(n);` — `ReadLn` ist write
8. `var n: Integer; Inc(n); WriteLn(n);` — `Inc` ist write (RMW
   read-OK weil Compiler initialisiert IntegerVars auf 0 in einigen
   Fällen — KONSERVATIV: das ist trotzdem ein flag wert)
   → **Klärungs-Bedarf:** Inc/Dec ohne vorherigen Write. Aktuell
   geplant als flag. Während Live-Audit reviewen.
9. `var X: T; DoSomethingThatWrites(var X); WriteLn(X);` —
   `var`-Parameter (gut wenn AST `var`/`out` liefert; sonst Skip via
   Allowlist)
10. `var X: T; FillChar(X, SizeOf(X), 0); WriteLn(X);` — FillChar
    ist explicit-init-Idiom
11. `var i: Integer; for i := 0 to 10 do WriteLn(i);` — Loop-Var
12. `for var i := 0 to 10 do WriteLn(i);` — Inline-Var-Loop

**Edge-Cases:**

1. Methode ist `asm`-Block → Skip
2. `with X do begin n := 1; WriteLn(n); end;` — `with` darf nicht
   maskieren (heute schon FP-Quelle bei anderen Detektoren, hier
   konservativ skip)
3. nested procedure: `procedure Outer; var n: Integer; procedure Inner;
   begin n := 1; end; begin Inner; WriteLn(n); end;` — Outer.n wird
   von Inner geschrieben → nicht flaggen wenn Inner aufgerufen wird.
   **Phase-1-MVP:** flag mit fcLow + comment "nested-proc-write may
   hide initialiser"
4. `var n: Integer = 0;` — Initialised-Declaration (Delphi 10.3+)
   → kein Flag

### 12.2 Golden-Corpus

Nach Live-Audit gegen das Real-World-Korpus (D:\git-demos\delphi):
jeder gefundene FP wird zu einem Reproducer in
`tests/golden-corpus/fp-reproducers/fp06_UninitVar_XYZ.pas` + Eintrag
in `expected.json` mit `must_not_flag: ["SCA166"]`.

### 12.3 Performance-Test

```pascal
[Test] procedure HugeMethod_BelowCap_CompletesUnder50ms;
[Test] procedure HugeMethod_AboveCap_EmitsLowConfidenceHint;
```

---

## 13. Erwarteter FP-Audit-Outcome — geschätzt vs. tatsächlich

**Schätzung vor Implementation:**

| Erwartung | Anzahl | Begründung |
|---|---|---|
| Echte UninitVar-Bugs | ~5-20 | seltene aber harte Bugs |
| Conditional-Write FPs (Phase-2-Kandidaten) | ~50-200 | typische if-then-else mit beidseitigem Write |
| Pessimistic-Read FPs (`var`/`out`-Param nicht erkannt) | ~30-100 | abhängig von AST-Auflösung |
| **Erwarteter MVP-Output** | **~80-320** | nur `fcHigh` + `fcMedium` |

**Tatsächliche Audit-Werte** (commit 8e439ec, `D:\git-demos\delphi`,
2 752 Files):

| Stand | SCA166 | Faktor vs Schätzung |
|---|---|---|
| Initial (commit 03438de, ohne Method-Boundary, ohne pessimistic-Write) | 7 322 | 23-86× |
| + Method-Boundary + pessimistic-Write (commit 2eea78a) | (Tests brachen — alle Reads als Write) | — |
| + READ_ALLOWLIST (commit 8e439ec) | **1 920** | **6-22×** |

**Realistische Klassifikation der verbleibenden 1 920:**

| Klasse | Geschätzte Anzahl | Phase-2-Adressierung |
|---|---|---|
| Echte UninitVar-Bugs | ~50-200 | bleiben (= Detector-Zweck) |
| FPs aus Calls in `if`/`while`-Conditions | ~500-1 000 | **Phase 2.2** killt das |
| FPs aus Array-Indexing (`Buf[0]` als Call-Arg) | ~100-300 | Phase 2.4 (TypeRef-Walk) |
| FPs aus Sub-Expression-Calls die AST-Walk verpasst | ~500-1 000 | Phase 3 (CFG + Expression-AST) |

**Diskrepanz-Erklärung:** die ursprüngliche Schätzung beruhte auf
SonarDelphi-Erfahrung im SonarDelphi-Korpus. Unser Real-World-Korpus
enthält dicht Library-Code (mormot, ZXing, MVCFramework) mit vielen
Patterns die der Parser als `nkIfStmt.TypeRef`-Strings (statt
`nkCall`-Knoten) ablegt — diese werden vom pessimistic-Write-Pfad
nicht erfasst. Phase 2.2 löst das.

**Aktueller Signal-to-Noise:** ~0.7 Findings/File, dominiert von
Library-Code in mormot/MVCFramework/ZXing. App-Code-Density ist
deutlich niedriger. `// noinspection UninitVar` ist verfügbar für
einzelne Suppressions, `--profile bugs-only` schließt SCA166 nicht
explizit aus.

---

## 14. Verwandte Konzepte

- [Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) §A.4
  (Control-Flow-Awareness für SCA134) — der dort vorgeschlagene CFG-
  Builder ist gleichzeitig Voraussetzung für SCA166-Phase-3.
- [Konzept_ScannerQualitaet.md](Konzept_ScannerQualitaet.md) §B.1
  (Symboltabelle) + §B.2 (Expression-AST-Knoten) — Voraussetzung für
  SCA166-Phase-4.
- [Konzept_SCA164_UnusedRoutine.md](Konzept_SCA164_UnusedRoutine.md) —
  ähnlicher Single-Method-Scope-Detektor; SCA166-Design lehnt sich an
  dessen Pipeline-Integration an.

---

## 15. Offene Entscheidungen vor Implementierung

1. **Inc/Dec ohne vorherigen Write** — flag (konservativ) oder skip
   (Pragma "Compiler initialisiert Integer auf 0 manchmal")?
   → Default: **flag** mit fcMedium. Konservativ ist sicherer; User
   kann via `// noinspection UninitVar` opten-out.
2. **`var`/`out`-Parameter-Erkennung** — heute pessimistic (jeder
   Call-Arg = Read). Lohnt ein Helper der die häufigsten RTL-Schreib-
   Procs explizit als Write erkennt (`Read`, `ReadLn`, `Read`,
   `BlockRead`, `FillChar`, `Move`, `ZeroMemory`, `Initialize`)?
   → **Ja**, Allowlist + Test pro Eintrag.
3. **Severity** — `lsError` (sicher) oder `lsWarning` (kontextabhängig)?
   → **lsError**, weil ein echter UninitVar in den meisten Fällen
   einen Crash erzeugt; bei managed-types ist es ein fcLow-Smell.
4. **Default-State** — enabled in `default` Profile oder opt-in via
   `strict`?
   → **Enabled in `default`**; FP-Rate sollte durch konservative
   Guards niedrig genug sein.
