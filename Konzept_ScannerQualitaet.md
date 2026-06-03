# Konzept: Scanner-Qualität weiter verbessern

Status: **Konzept**, noch nicht umgesetzt
Stand: 2026-06-02

Nach 13 FP-Reduktions-Runden (12 200 → 6 918 Findings = −43%, Errors
37 → 5 = −86%) ist die tief hängende Frucht weg. Dieses Doc gliedert
die verbleibenden Qualitäts-Hebel nach Achse (Precision / Recall /
Tooling / Architektur) und schlägt eine priorisierte Reihenfolge vor.

Querverweise:
- [Todo_FalsePositiveReduction.md](Todo_FalsePositiveReduction.md) — die
  bisher umgesetzten Detector-Fixes (Section D)
- [HowTo_DetectorSelftest.md](HowTo_DetectorSelftest.md) — Workflow
- [Konzept_EngineExtraction.md](Konzept_EngineExtraction.md) — Architektur-
  Vorbedingung für mehrere der hier vorgeschlagenen Maßnahmen
- [tools/perf_analyse.md](tools/perf_analyse.md) — Perf-Optimierungs-Status

---

## A. Precision (weniger False-Positives)

Marginal-Hebel: die großen FP-Cluster (FieldName, RedundantJump,
GroupedDecl, FreeWithoutNil, ...) sind durch. Was bleibt sind
strukturelle Grenzen der heutigen Heuristik.

### A.1 Confidence-Tagging pro Detektor — **✅ ERLEDIGT (2026-06-02)**

**Problem**: Heute laufen ALLE Detektoren mit `fcHigh` (Default).
Confidence-Filter (`MinConfidence`) ist da, wird aber von keinem Detektor
genutzt. Resultat: Profile `default` zeigt Style-Heuristiken auf Augenhöhe
mit echten Bugs.

**Umsetzung**:
- Zentrale Funktion `KindDefaultConfidence(K)` in
  [uSCAConsts.pas](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas)
  (case-Statement; Default = `fcHigh`, ~35 Kinds explizit `fcMedium`)
- `TLeakFinding.SetKind` zieht Confidence aus `KindDefaultConfidence`
- 3 Detektoren mit direktem `F.Kind :=` (uDivByZero, uLeakDetector2,
  uCustomRuleDetector) explizit ergänzt
- Override bleibt möglich: `uCommandInjection` setzt `fcLow` nach SetKind
- Audit-Doku: [docs/ConfidenceAudit.md](docs/ConfidenceAudit.md)
- Tests in uTestConfidenceFilter: 4 neue Tests
  (`KindDefaultConfidence_*`, `SetKind_AppliesKindDefaultConfidence`)

**Aufwand-Ist**: ~3h
**Wirkung**: `--min-confidence high` blendet jetzt strukturell die
~35 heuristischen Kinds aus. Default-Profil unverändert (`fcMedium`-
Schwelle zeigt alles ausser `fcLow`-Overrides).
**Risiko**: niedrig — kein Detektor-Code geändert ausser den 3 Direkt-Settern.

### A.2 Test-Fixture-Auto-Detection — **Quick-Win**

**Problem**: Self-Test findet konsistent 5 Errors in `MeineUnit.pas` und
`uOrderForm.pas` (intentional Bug-Demos für eigene Tests). Die landen in
jedem Report und müssen manuell ignoriert werden.

**Maßnahme**: Heuristik im Post-Filter (oder im Path-Override):
Files matchend gegen `uTest*.pas` / `*Sample.pas` / `*Demo.pas` /
`MeineUnit.pas` werden als "test-fixture" markiert. Default-Verhalten:
- `--profile default`: ausblenden
- `--profile strict`: anzeigen mit Severity-Downgrade auf Hint
- `--profile selftest-quiet`: ausblenden (logisch)

**Aufwand**: 2h.
**Wirkung**: Self-Test-Reports klarer, CI-Quality-Gate nicht durch
intentional-Fixtures rot.
**Risiko**: niedrig — Heuristik ist konservativ, opt-in via Profile.

### A.3 Cross-Unit-Symbol-Index für SCA052/107 — **🟡 TEIL-ERLEDIGT (2026-06-02)**

**Stand A.3-Minimal (commit folgt):**
- `uVisibilityCheck` konsultiert `gSymbolRefIndex.HasExternalRefs` für
  `fkUnusedPublicMember` (SCA052) — wenn Member extern referenziert ist,
  wird kein "Dead public API"-Finding emittiert.
- Sanity-Check: `TLeakFinding.SetKind` (klar Cross-Unit) ist NICHT mehr
  als SCA052 geflaggt. Index wirkt.
- Real-World-Scan (D:\git-demos\delphi, 2 752 Files): SCA052 = 6 130.
- Andere Visibility-Kinds (SCA050/SCA107/CanBeProtected) noch
  Single-File — Audit ihrer FP-Cluster ist separater Schritt.

**Bekannte Limitation:** Index sammelt nur `nkCall` + `nkAssign` mit
`Obj.Member`-Pattern. Property-Reads / Function-without-Paren
(`F.SeverityText`) werden NICHT erfasst → `SeverityText`/`FindingType`/
`TypeText` bleiben fälschlich als SCA052 geflaggt obwohl in 19 Files
referenziert.

**Follow-up A.3+ (eigener Sprint):** Audit (Spot-Check 18 Methoden,
8/18 = 44% A.3-Wirkung) hat 3 Index-Limitationen offengelegt, die als
priorisierte Roadmap die restlichen ~56% erschließen würden:

1. **`nkRef`-Sammlung in `AddRefsFromNode`** — Index sammelt heute nur
   `nkCall` + `nkAssign` mit `Obj.Member`-Pattern. Value-uses ohne
   Klammern (`F.SeverityText`, Property-Reads, function-without-paren)
   werden nicht erfasst.
   *Geschätzt:* ~25-40% der verbleibenden FPs.

2. **Class-Function-Calls `TKlasse.ClassMethod(args)`** — werden vom
   Index nicht als `Obj.Member`-Pattern erkannt obwohl der nkCall.Name
   den qualifizierten Namen enthält. Vermutlich AST-Parser klassifiziert
   `TKlasse` als TypeRef statt als Receiver. Beispiele aus Audit:
   `TConfidenceFilter.ApplyToFindings`, `TRuleCatalog.GetRule`,
   `TFindingFingerprint.ContextHash`, `TSymbolReferenceIndex.HasExternalRefs`.
   *Geschätzt:* ~30-40% der verbleibenden FPs.

3. **Bare-Calls ohne Receiver** (`Fingerprint(F)` statt
   `Self.Fingerprint(F)`) — heute bewusst ausgeklammert weil zu viele
   FPs (jeder `Writeln` würde als hypothetischer public Writeln-Member
   zählen). Lösung: nur indexieren wenn der bare Call-Name mit einem
   in der Datenbank deklarierten public Member-Namen kollidiert (= Cross-
   Reference statt blind sammeln). *Aufwendiger, niedrigere Priorität.*

4. Nach 1-3: analog SCA050 (CanBeUnitPrivate) und SCA107
   (CanBeStrictPrivate) am Index dranhängen — derzeit alle Single-File.

5. Klassen-Filter `RTTI_DRIVEN_BASES` erweitern um IDE-spezifische
   Bases (Audit zeigt `uIDEAnalyserForm.pas` mit 17 SCA052, vermutlich
   nicht direkt `TForm`-Descendant).

**Library-FP-Klasse (nicht behebbar):** Real-World-Scan zeigt: Top-Files
mit SCA052 sind alle externe Libraries (`mormot.*`, `MVCFramework`).
Public-API für Cross-Repo-Konsumenten kann der Index per definitionem
nicht sehen. Empfehlung: per Path-Override-Default für `vendor/`-
ähnliche Ordner SCA052 ausblenden (separate Maßnahme).


**Problem**: SCA052 (Dead public API) + SCA107 (strict-private candidate)
+ SCA050 (unit-private candidate) sind by-design single-file-Scope —
zusammen ~580 Findings (8% des Self-Test-Outputs). Sie schweigen die
Cross-Unit-Konsumenten — das produziert FPs auf Helper-Klassen die
woanders genutzt werden.

**Maßnahme**: `gSymbolReferenceIndex` (existiert, aber von Visibility-
Detektoren nicht mehr genutzt — siehe `uSymbolReferenceIndex.pas:5-7`)
wieder aktivieren. Vorsicht: ursprünglich abgekoppelt weil RTTI-/DFM-/
Generic-Cluster mehr FPs brachten als TPs.

**Aufwand**: 3-5d (inkl. neue FP-Audits für die RTTI-/DFM-Konsumenten).
**Wirkung**: ~580 FPs strukturell behebbar.
**Risiko**: hoch — Regression auf neue FP-Klassen (TForm-Streaming,
TInterfaceImpl, Plugin-APIs).

### A.4 Control-Flow-Awareness für SCA134 UseAfterFree

**Problem**: aktueller Detektor (Round 2 fix `4b7f5cc`) erkennt sibling-
Free im if/else, aber nicht den allgemeinen Fall mit try/except/finally-
Verschachtelungen.

**Maßnahme**: vereinfachter Control-Flow-Graph pro Methode (Blocks +
Edges), `.Free`-Annotation pro Variable per Pfad. Klassischer Compiler-
Datenfluss.

**Aufwand**: 3-5d.
**Wirkung**: SCA134 produziert heute 0 FPs (nach Round 2) aber findet
auch keine Use-After-Frees in komplexeren Patterns. Mehr Recall ohne
mehr FPs.
**Risiko**: mittel — CFG-Implementierung muss korrekt sein.

### A.5 `{$IFDEF}`-Branch-Awareness

**Problem**: Scanner ignoriert Conditional-Defines, scannt beide Branches.
Code im inaktiven `{$IFDEF DEBUG}`-Branch wird mit gleicher Strenge
analysiert wie aktiver Code.

**Maßnahme**: Lexer-Level-Filterung: bekannt-undefinierte Symbole
(`DEBUG` standardmäßig False im Release) → entsprechende Branches
skippen. Konfigurierbar via `analyser.ini`.

**Aufwand**: 2-3d.
**Wirkung**: ~5-15% weniger FPs auf Codebases mit viel Conditional-Compile.
**Risiko**: mittel — falsch konfigurierte Defines = falsche Branches
gescannt.

---

## B. Recall (mehr echte Bugs finden)

Großer Hebel, aber teuer. Hier liegt die "vergessen Bugs"-Pipeline.

### B.1 Symboltabelle pro Unit — **Großer Wurf**

**Problem**: kein Type-Lookup. Detektoren wie FloatEquality müssen den Typ
einer Variable raten anhand `<ident>: <Type>;`-Regex. Klassisches Limit:
`A, B: Double;` findet nur A (Komma-Liste-Bug seit Detector-Genesis).
Function-Returns / Parameter / Self-Felder unauflösbar.

**Maßnahme**: Pro Unit eine `TSymbolTable: TDictionary<string, TSymbolInfo>`
aufbauen während des Parsens. Felder:
- `Name`, `Kind` (var/param/field/method/const/type)
- `TypeName` (raw text aus AST)
- `Visibility` (private/protected/public/published)
- `DeclLine`, `DeclCol`
- für Methoden: `ParamList`, `ReturnType`, `Directives`

API für Detektoren: `gSymbols.Lookup(UnitNode, IdentLow): TSymbolInfo` bzw.
in Methoden-Scope: `gSymbols.LookupInScope(MethNode, IdentLow)`.

**Aufwand**: 1-2 Wochen (Parser-Erweiterung + Detector-Migration für die
~10 Type-bewussten Detektoren).
**Wirkung**:
- Beseitigt FALSE-NEGATIVES (Komma-Listen, Property-Lookups via `Self.X`)
- Erlaubt neue Detektoren (Type-Mismatch, Nullable-Misuse, Generic-Constraint-Bruch)
- Macht die Codebasis Symbol-Table-fähig — Bedingung für B.2/B.3
**Risiko**: mittel — Parser wird komplexer, Memory-Footprint steigt um
~10-30 KB pro AST.

### B.2 Expression-AST-Knoten

**Problem**: `nkAssign.TypeRef` ist heute ein flacher String. ~30
Detektoren parsen ihn lexikalisch (Regex/Pos), weil keine strukturierte
Form da ist. Beispiele:
- `uFloatEquality` matcht `A = B` per Regex
- `uTautologicalExpr` vergleicht Strings statt AST-Knoten
- `uBoolAlwaysTrue` regex-matcht `Length(...)`

`TNodeKind` hat `nkBinaryOp/nkLiteral/nkDot/nkDeref/nkIndex/nkUnaryOp`
RESERVIERT, aber der Parser produziert sie nicht (siehe `uAstNode.pas:32-37`).

**Maßnahme**: Parser-Erweiterung zur tatsächlichen Expression-Generierung.
Folgekosten: alle Detektoren die TypeRef lesen müssen entweder migriert
(strukturiert auf nkBinaryOp etc.) oder via Hilfsfunktion einen
Text-Render aus dem Subtree generieren.

**Aufwand**: 2-3 Wochen (Parser + ~30 Detector-Migrationen).
**Wirkung**:
- Robustere Detektoren (kein String-Parsing mehr)
- Bessere FP-Resistenz (z.B. `x = nil` vs `x.y = nil` strukturell unterscheidbar)
- Erlaubt neue Detektoren (Dead-Store, Constant-Folding-Inkonsistenz)
**Risiko**: mittel-hoch — viel Code-Bewegung, Test-Regression-Surface
groß.

### B.3 Inter-procedural Data-Flow für Taint-Tracking

**Problem**: `SCA003 SQLInjection` und `SCA163 CommandInjection` sind
heute heuristisch — sie matchen `'+' im SQL/Shell-Arg`. Ohne Taint-
Tracking finden sie nicht:
- `cmd := 'cmd /c ' + UserInput; ShellExecute(0,...,cmd,...)` (Variable-Hop)
- `req.SQL.Text := MakeQuery(UserInput);` (Function-Indirection)

**Maßnahme**: Lokales Taint-Tracking pro Methode (Tainted-Sources:
Params/HttpRequest-Fields/EditBox-Text; Tainted-Sinks: SQL.Text,
ShellExecute, FileWrite). Hop-Tracking via Symboltabelle (B.1 ist
Vorbedingung).

**Aufwand**: 2 Wochen (lokal).
**Wirkung**: SCA003/163 Confidence von `fcLow` (heute) auf `fcHigh`,
erlaubt sie im `default`-Profile zu zeigen ohne FP-Tsunami.
**Risiko**: mittel.

### B.4 Mehr Detector-Klassen aus SonarDelphi/PMD

**Problem**: SonarDelphi hat ~120 Checks, wir haben ~80 Pendants
implementiert. Lücke: ~40 nicht migrierte Regeln.

**Maßnahme**: Liste der nicht-migrierten Checks aus SonarDelphi
durchgehen, pro Tag 1-2 neue Detektoren nach
[HowTo_AddDetector.md](HowTo_AddDetector.md)-Checkliste.

**Aufwand**: je 1-4h pro Detektor, ~3 Wochen für alle 40.
**Wirkung**: graduell besseres Coverage.
**Risiko**: niedrig.

---

## C. Tooling & Workflow — Sofort-Hebel

Kein Detector-Code-Change nötig, aber große Wirkung auf Iterations-Speed
und Vertrauen.

### C.1 Golden-Corpus-Regression-Tests — **✅ ERLEDIGT (2026-06-02)**

**Problem**: Jeder Detector-Fix dieser Session hat das Risiko, FUTURE-FPs
zurück zu bringen (Detector-Regression). Heutige DUnit-Tests prüfen
einzelne SRC-Strings — keine Regression-Bewachung gegen Real-World-Code.

**Umsetzung**:
- `tests/golden-corpus/fp-reproducers/` enthält 5 historische FP-Repro-Snippets
  (`fp01..fp05`, je 1 Round-Fix aus der FP-Reduction-Session)
- `expected.json` pro File: `must_not_flag`-Liste mit den gefixten Rules
- `tools/check-golden-corpus.ps1` scant Corpus + diffed gegen Erwartung
- Exit 0/1 → CI-tauglich; siehe `tests/golden-corpus/README.md`

**Aufwand-Ist**: ~3h (1h Snippets, 1h Runner, 1h README/Doku)
**Wirkung**: jeder zukünftige Detector-Fix ist regression-gesichert.
**Risiko**: niedrig.

### C.2 SARIF-PartialFingerprints für Baseline-Diff — **✅ ERLEDIGT (2026-06-02)**

**Problem**: aktuelles Baseline-System (`--baseline`/`--write-baseline`)
nutzt File+Kind+Method+Detail als Fingerprint. Edge-Case: Method-Rename
oder Verschieben in andere Methode → "neue" Findings obwohl identisch.

**Umsetzung**:
- Neue Unit `uFindingFingerprint.pas` (Infrastructure) mit
  `ContextHash(F)` über ±3 Zeilen Snippet, whitespace-normalisiert
  (Tabs→Space, WS-Runs kollabiert, Leerzeilen verworfen, Trim)
- SARIF: zusätzliches Feld `partialFingerprints.contextHash/v1`
  neben dem bisherigen `primaryLocationLineHash`
- Baseline.Write: speichert `contextHash` zusätzlich pro Entry
- Baseline.Apply: matched contextHash ODER legacy fingerprint
  (alte Baselines bleiben gültig — kein Migrations-Lauf nötig)
- Tests in `uTestFindingFingerprint.pas` (10 Tests, decken
  Normalisierung + Line-Drift + Backward-Compat ab)

**Aufwand-Ist**: ~4h
**Wirkung**: Baseline überlebt Re-Indent, Method-Rename, Line-Drift.
**Risiko**: niedrig — Backward-Compat ist Code-Pfad, kein Auto-Refresh nötig.

### C.3 `// noinspection`-Unused-Tracking — **Quick-Win**

**Problem**: heute kein Feedback ob ein Suppression-Marker noch nötig
ist. Detector-Verbesserung macht ihn evtl. obsolet, niemand merkt's.

**Maßnahme**: zweite Pipeline-Phase nach dem Scan: für jeden gefundenen
Marker prüfen ob er an seiner Position überhaupt ein Finding suppress'd
hat. Wenn nicht → "unused-suppression"-Finding (fkUnusedSuppression).

**Aufwand**: 4h.
**Wirkung**: Suppression-Liste hygienisch, kennt evolution-driven
Detector-Verbesserungen.
**Risiko**: niedrig.

### C.4 Per-Detector-Performance-Profil

**Problem**: aktueller Scan ist ~3s/409 Files, also ~7ms/File. Bei
2 600 Files (Real-World D:\git-demos\delphi) sind es 70s, also ~27ms/File.
Wer treibt die Verlangsamung? Heute nicht aggregiert sichtbar (nur
einzelne "langsam!"-Marker > 500ms).

**Maßnahme**: AOnTime-Callback erweitern: pro Detector kumulieren über
gesamten Scan, am Ende Markdown-Report. Tool `tools/perf_log_summary.ps1`
existiert für Datei-Granularität, hier analog für Detector-Granularität.

**Aufwand**: 1h.
**Wirkung**: datenbasierte Auswahl welcher Detektor als nächstes
optimiert wird.
**Risiko**: niedrig.

### C.5 Detector-Confidence-Telemetrie — **✅ ERLEDIGT (2026-06-04)**

**Problem**: Suppressions pro Kind sind nicht aggregiert. "Welche Regel
generiert am meisten User-Reaktion (Noise)?" nur per Bauchgefühl.

**Umsetzung**:
- Neue Unit [`uSuppressionTelemetry.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uSuppressionTelemetry.pas)
  mit `TSuppressionTelemetry`-Klasse + global opt-in `gSuppressionTelemetry`
- `uSuppression.RemoveSuppressedFindings` appendet pro consumed Marker
  einen Record (Kind + FileName + FindingLine + MarkerLine)
- CLI-Flag `--telemetry-csv <out.csv>` aktiviert + schreibt am Ende
- CSV-Format RFC-4180-konform: `timestamp_iso,kind,filename,finding_line,marker_line`
- Default = OFF, kein Overhead bei nil-Check
- Aggregations-Workflow (PowerShell-One-Liner) in Unit-Header dokumentiert

**Aufwand-Ist**: ~2h.
**Wirkung**: Datenbasis für A.1 (Confidence-Tagging) + Profile-Default-Anpassungen.
**Risiko**: niedrig — opt-in.

---

## D. Architektur-Fundament

Vorbedingung für mehrere der oben genannten Maßnahmen.

### D.1 Engine-Extraction

Siehe [Konzept_EngineExtraction.md](Konzept_EngineExtraction.md). 3h
Aufwand, schafft CI-Isolation der Engine, schlanker IDE-Plugin.
**Vorbedingung für**: A.1 (Confidence-Audit hat eigene CI), B.1 (Symbol-
Table-Implementation profitiert von engerer Scope-Grenze).

### D.2 Singleton-Entkopplung (gAstFileCache, gSymbolRefIndex) — 🟡 **deferred bis D.1**

> **Detail-Konzept:** [`Konzept_D2_SingletonEntkopplung.md`](Konzept_D2_SingletonEntkopplung.md)
>
> Audit-Ergebnis: realistischer Aufwand 3-5d (nicht 1d), kein konkreter
> aktueller Bug, natürlicher Heimat-Sprint ist D.1 (Engine-Extraction)
> wo die Engine-API sowieso re-modularisiert wird. **D.2 standalone =
> Refactor-Bumerang.** Test-Isolation-Risiko ist heute durch
> mtime-Cache (commit 1e7e193) + Re-Create-Pattern (commit 120894a)
> ausreichend adressiert.

**Problem**: globaler State im Engine-Code. Parallele Analysen würden
sich gegenseitig den Cache stehlen. Test-Isolation: jeder Test sieht
Cache-Reste vom Vortest.

**Maßnahme**: globale Vars durch `TAnalyzeContext`-Record ersetzen, der
durch `TStaticAnalyzer2.AnalyzeLeaksRecursive(Path, AContext)`
weitergereicht wird.

**Aufwand**: 1d.
**Wirkung**: Engine ist multi-instance-safe → parallele CI-Runs auf
verschiedenen Repos, ohne Cross-Talk.
**Risiko**: niedrig — Refactoring ohne Verhaltens-Änderung.

### D.3 Detector-Plugin-API

**Problem**: neue Detektoren brauchen Engine-Rebuild. Custom-Detektoren
(projekt-spezifisch) sind nur als YAML-Regeln möglich, nicht als echte
Pascal-Detektoren.

**Maßnahme**: Detector-Interface (`ISCADetector`) definieren, Engine
lädt zusätzliche `.bpl`s aus einem Plugin-Folder. Plugin registriert
sich beim `RuleCatalog` über die Interface-API.

**Aufwand**: 1 Woche.
**Wirkung**: User können eigene Detektoren ohne Engine-Fork bauen.
**Risiko**: hoch — Plugin-API ist eine Vertrags-Schnittstelle, jeder
Engine-Refactor muss sie respektieren.

---

## E. Empfohlene Reihenfolge

### Phase 1 — Quick-Wins (~1 Woche)

1. **C.1 Golden-Corpus-Regression** — sichert alle FP-Fixes ab
2. **A.2 Test-Fixture-Auto-Detection** — sauberer Self-Test-Output
3. **C.3 Unused-Suppression-Tracking** — Suppression-Hygiene
4. **C.4 Per-Detector-Performance-Profil** — datenbasiert weiter
5. **C.2 SARIF-PartialFingerprints** — Baseline robuster
6. **A.1 Confidence-Tagging Audit** — Default-Profile auf "echtes
   Signal" trimmen

### Phase 2 — Architektur-Fundament (~1 Woche)

7. **D.1 Engine-Extraction** (Konzept liegt vor)
8. **D.2 Singleton-Entkopplung**

### Phase 3 — Großer Wurf (~1 Monat)

9. **B.1 Symboltabelle pro Unit** — entriegelt B.2/B.3 und neue Detektoren
10. **B.2 Expression-AST-Knoten** — regex → AST-Migration für ~30 Detektoren

### Phase 4 — Optional, bei konkretem Bedarf

11. **A.3 Cross-Unit-Symbol-Index** wieder anschalten
12. **A.4 Control-Flow-Awareness UseAfterFree**
13. **A.5 `{$IFDEF}`-Branch-Awareness**
14. **B.3 Inter-procedural Taint-Tracking**
15. **B.4 Sonar-Migration-Restbestand**
16. **D.3 Detector-Plugin-API**

---

## F. Erfolgs-Metriken

Was misst "der Scanner ist besser geworden"?

| Metrik | Heute (v0.9.7) | Ziel nach Phase 1 | Ziel nach Phase 3 |
|---|---|---|---|
| Self-Test-Total | 6 918 | 5 000 | 3 500 |
| Self-Test-Errors | 5 (alle erklärt) | 2 (nur Parser-Bug + Wrapper-Pattern übrig) | 0 |
| Default-Profile-Signal-to-Noise | unbekannt | erste Messung | gemessen, gezielt verbessert |
| Scan-Time pro File | 7-27ms | 7-27ms (kein Regression) | 5-20ms (Symbol-Table-Cache) |
| Detector-Tests gesamt | ~1700 | ~1800 (Golden-Corpus + neue Tests) | ~2200 |
| Unused-Suppressions im Repo | unbekannt | 0 (durch C.3) | 0 |
| BPL-Build-Zeit IDE-Plugin | ~30s | ~15s (Engine separat) | ~10s |
| Real-Bug-Recall (bekannte injected) | ~80% (Schätzung) | ~80% (kein Regression) | ~95% (Symbol-Table + AST-Knoten) |

---

## G. Was NICHT in diesem Konzept ist

- **AI-basierte Detektion** (LLM-Schritt im Pipeline) — separates
  Konzept-Thema, keine harte Abgrenzung zum klassischen Static-Analyzer
- **Cross-Language-Support** (Pascal hinaus) — Out-of-Scope
- **Self-Hosted-Web-UI** — Standalone-Form/IDE-Plugin reicht
- **Distributed-Scan** (mehrere Worker) — bei 2 600 Files in 70s nicht
  nötig
- **VCS-Hook-Integration** (Pre-Commit-Scan automatisch) — separate
  Doku, kein Scanner-Quality-Hebel
