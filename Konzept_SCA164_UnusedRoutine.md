# Konzept SCA164 — UnusedRoutine

Erkennt **top-level Procedure/Function (oder Klassen-Methode), die nirgendwo
aufgerufen wird** — die existierende Lücke zwischen SCA147 (nur `private`
class methods) und SCA148+ (nur public class members).

Status: Konzept-Phase. Implementierung folgt nach Review dieses Dokuments.
Branch: `feat/sca164-unused-routine`.

---

## Was es heute schon gibt (Lücke nachgewiesen)

| Detector | Scope | Lücke |
|---|---|---|
| [`uUnusedPrivateMethod.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedPrivateMethod.pas) (SCA147) | nur `class private` / `class strict private` | top-level Routinen + non-private Methoden ungedeckt |
| [`uVisibilityCheck.pas`](StaticCodeAnalyserForm/sources/Detectors/uVisibilityCheck.pas) → `fkUnusedPublicMember` | nur `class public` Member, single-file | top-level Routinen ungedeckt |
| [`uUnusedUses.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedUses.pas) | `uses`-Klausel-Eintraege | nur Unit-Level |
| [`uUnusedLocal.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedLocal.pas) / [`uUnusedParameter.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedParameter.pas) | lokale `var` / Parameter | sub-Routine-Level |

Konkretes Beispiel das durch *alle* Maschen fällt:

```pascal
unit u;
interface
procedure ExportedHelper;    // dürfte cross-unit gerufen werden
implementation

procedure InternalHelper;    // nur implementation, ohne Aufruf -> DEAD
begin
  ShowMessage('hi');
end;

procedure ExportedHelper;
begin
  ShowMessage('export');
end;

end.
```

`InternalHelper` ist eindeutig toter Code. Kein Detector der Suite warnt.

---

## Wie andere SCA-Tools das machen (Recherche-Synthese)

### 1. SonarDelphi `UnusedRoutineCheck` — der Referenz-Algorithmus

Quelle: [`UnusedRoutineCheck.java`](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/UnusedRoutineCheck.java)
+ [`UnusedRoutineCheckTest.java`](https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/test/java/au/com/integradev/delphi/checks/UnusedRoutineCheckTest.java) (24 Tests).

**Scope:** Single-File AST. Visit `RoutineNode`, prüfe `getUsages()` —
zählt jede Symbol-Referenz **außerhalb** der Routine selbst als "used".

**FP-Guards (in Reihenfolge der Prüfung):**

| # | Guard | Begründung |
|---|---|---|
| 1 | `published` Sichtbarkeit | RTTI-Zugriff per `TypeInfo` / DFM-Binding |
| 2 | `public` in `interface`-Sektion (wenn `excludeApi=true`) | Cross-Unit-Konsumenten unbekannt |
| 3 | `override` directive | Subklassen-Contract — Parent ruft |
| 4 | `message TWM_xxx` directive | Win32-Message-Pump dispatched über VTable |
| 5 | non-callable (z.B. abstract ohne body) | nichts zum nennen |
| 6 | Routine mit `[Attribute]` non-empty type | RTTI-konsumiert (Mocking, Serialisierung) |
| 7 | unit-scope `Register` Prozedur | IDE-Plugin-Registrierung über Pkg-System |
| 8 | Methode implementiert Interface | Interface-Contract erzwingt |
| 9 | Konstruktor der via `raise EAbstract`-Style "verboten" wird | Forbidden-Constructor-Pattern |
| 10 | Enumerator-Methoden (`MoveNext`/`GetEnumerator`/`Current`) | `for-in`-Loop ruft implizit |

**Kritischer Detail-Punkt:** Rekursive Routinen werden **trotzdem geflagged** —
self-references zählen NICHT als Verwendung. SonarDelphi hat das in
`testUnusedRecursiveRoutineShouldAddIssue` explizit verankert.

### 2. Peganza Pascal Analyzer

Quelle: [Code Reduction Report Doku](https://www.peganza.com/PALHelp/code_reduction_report.htm).

- **Project-wide**, multi-projekt-faehig.
- Drei Granularitäten: REDU13 (called once), REDU14 (only-within-class),
  unused identifier-Listings.
- Explizite Exclusions: DFM-event-handlers, Konstruktoren/Destruktoren,
  Interface-Implementierungen, "general-purpose units" (die ggf. extern
  gerufen werden).

### 3. FixInsight (TMS)

Hat W519 (empty methods), aber **kein eigenes UnusedRoutine-Check** in
der offiziellen Doku auffindbar. Lücke.

### 4. Delphi-Compiler selbst

**W1045 "H2164 Unreferenced function"** existiert als Hint, wird vom
Smart-Linker getriggert. Limit: nur fuer File-lokale Funktionen, springt
selten bei Klassen-Methoden, springt nicht bei virtuellen / Interface-
gebundenen Routinen.

### Fazit der Recherche

SonarDelphi's `UnusedRoutineCheck` ist das **direkteste, am besten
dokumentierte Pendant**. Wir spiegeln dessen Algorithmus 1:1, plus den
optionalen Cross-Unit-Sanity-Check via unserem bereits vorhandenen
`gSymbolRefIndex` (siehe [`uSymbolReferenceIndex.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uSymbolReferenceIndex.pas)).

---

## Vorhandene Infrastruktur die wir wiederverwenden

| Helper | Was er kann | Quelle |
|---|---|---|
| `AcquireLines` / `ReleaseLines` | gecachter File-Read | [`uFileTextCache.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uFileTextCache.pas) |
| `TDetectorUtils.StripStringsAndComments` | Identifier-Suche FP-frei | [`uDetectorUtils.pas`](StaticCodeAnalyserForm/sources/Common/uDetectorUtils.pas) |
| `gSymbolRefIndex` | repo-weiter `Obj.Member`-Index | [`uSymbolReferenceIndex.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uSymbolReferenceIndex.pas) — aktuell von keinem Detektor konsumiert |
| `IsPrivateSection` / `UnqualifiedName` | aus SCA147 — wir copy-pasten ODER ziehen sie in `uDetectorUtils` hoch | [`uUnusedPrivateMethod.pas`](StaticCodeAnalyserForm/sources/Detectors/uUnusedPrivateMethod.pas) |
| DFM-Event-Handler-Liste | aus dem DFM-Index | [`uDfmRepoIndex.pas`](StaticCodeAnalyserForm/sources/Infrastructure/uDfmRepoIndex.pas) (Cross-Check: wenn Methode im DFM gebunden ist, ist sie "used") |
| `TLeakFinding.Confidence` | `fcLow`/`fcMedium`/`fcHigh` | [`uMethodd12.pas`](StaticCodeAnalyserForm/sources/Common/uMethodd12.pas) |

---

## SCA164-Algorithmus

### Phase 1 — Kandidaten sammeln

AST-Walk pro Unit:

1. Alle `nkMethod`-Knoten unterhalb `nkImplementation` finden.
2. Klassifizierung jeder Routine:
   - **Standalone-Implementation** — kein `.`-Qualifier im Method-Namen,
     keine Vorab-Deklaration im `interface` der eigenen Unit.
   - **Standalone-Interface** — Forward-Decl im `interface`, Impl im
     `implementation`.
   - **Klassen-Methode** — qualifizierter Name (`TFoo.Bar`).

3. Pro Routine FP-Guards anwenden (SonarDelphi-Liste 1-10, an unsere
   AST-Aufloesung angepasst — siehe nächstes Kapitel).

### Phase 2 — Verwendungs-Check

| Routine-Typ | Such-Strategie | Confidence |
|---|---|---|
| Standalone-Implementation (nur `implementation`) | Wortgrenz-Match im stripped Unit-Source (analog SCA147). Self-Call NICHT zählen (Position-Aware: Match-Position liegt innerhalb der gerade analysierten Routine = überspringen). | `fcHigh` — kein Cross-Unit-Confound |
| Standalone-Interface (in `interface` deklariert) | Unit-lokaler Scan + `gSymbolRefIndex.HasExternalRefs(name, ownUnit)` falls Index nicht-leer. Falls Index leer (Single-File-Mode): gar nicht flaggen oder mit `fcLow`. | `fcMedium` (mit Index), sonst `fcLow` |
| Klassen-Methode `public`/`protected` | Wenn `excludeApi=true` (Default): nicht flaggen — fällt in SCA148-Spezialfall (`fkUnusedPublicMember` in `uVisibilityCheck`). Wenn `false`: Unit-lokaler Scan + Symbol-Index-Check. | `fcMedium` |
| Klassen-Methode `private` | übergeben — SCA147 deckt das ab (kein Duplikat-Finding). | — |

### Phase 3 — FP-Guards (in Reihenfolge anwenden, kurzschließen sobald einer matcht)

| # | Guard | Implementierung |
|---|---|---|
| 1 | `Mth.IsInPublishedSection` | Visibility-Section-Check (analog SCA147) |
| 2 | `Mth.Modifiers` enthaelt `'override'` | Parser legt Modifiers in `TypeRef` ab; substring-check |
| 3 | `Mth.Modifiers` enthaelt `'message '` | substring-check |
| 4 | `Mth.Modifiers` enthaelt `'virtual; abstract'` / leerer Body | AST-check: keine `nkBlock`-Children |
| 5 | Hat `[Attribute]` davor | Parser stellt das nicht zuverlässig dar — **PHASE-1-Limit**, optional in v2 |
| 6 | Top-level `Register` Prozedur | Name-Check `LowerCase = 'register'` AND Parent = nkImplementation |
| 7 | Implementiert ein Interface | Cross-Check: `Mth.Name = 'TFoo.SomeMethod'` und in der Klassen-Deklaration ist ein Ancestor ein Interface — **PHASE-1-Limit**, optional in v2 (AST hat nicht zwingend Ancestor-Info auflösbar) |
| 8 | Methode ist im DFM als Event-Handler gebunden | Lookup über `gDfmRepoIndex.IsMethodReferenced(unit, name)` — Helper existiert wahrscheinlich noch nicht, müssen wir bauen |
| 9 | Konstruktor / Destruktor | Name endet auf `.Create` / `.Destroy` ODER `Mth.Kind`-Flag im AST (falls vorhanden) |
| 10 | Enumerator-Trio (`MoveNext`/`GetEnumerator`/`Current`) | Name-Whitelist |

**MVP:** Guards 1-4, 6, 9, 10. Guards 5, 7, 8 als bekannte Limit
dokumentieren (Suppression-Marker als Escape-Hatch).

---

## Severity, Type, Confidence

| | Wert | Begründung |
|---|---|---|
| Severity | `lsHint` | Dead Code ist Wartbarkeits-Problem, kein Bug |
| Type | `ftCodeSmell` | Sonar-Konvention |
| Confidence Default | je Pfad (Tabelle oben) | Implementation-only = High, Interface = Medium/Low |

---

## Test-Plan (mindestens diese Tests, alle in `uTestUnusedRoutine.pas`)

### Positiv (sollen flaggen)

- `Unused_StandaloneImpl_Reported` — `procedure Helper; begin end;` in implementation, kein Aufruf
- `Unused_StandaloneInterfaceWithoutExternalRef_Reported` — interface-decl, kein cross-unit-call (Index leer = `fcLow`)
- `Unused_RecursiveSelfCallOnly_Reported` — `procedure F; begin F; end;` (Self-Call zählt nicht)
- `Unused_OverloadVariantUnused_Reported` — eine Overload-Variante ungenutzt

### Negativ (FP-Guards greifen)

- `Unused_OverrideMethod_NoFinding`
- `Unused_MessageHandler_NoFinding` — `procedure WMClose(var Msg); message WM_CLOSE;`
- `Unused_RegisterProcedure_NoFinding`
- `Unused_DfmBoundEventHandler_NoFinding` — Methode wird in `.dfm`-File referenziert
- `Unused_AbstractWithoutBody_NoFinding`
- `Unused_ConstructorDestructor_NoFinding`
- `Unused_EnumeratorMethod_NoFinding`
- `Unused_PublicWithCrossUnitCall_NoFinding` — Index hat externen Caller
- `Unused_PublicWithoutIndex_NoFinding` — `excludeApi=true` Default

### Finding-Inhalt

- `Unused_Finding_KindSeverityConfidence` — Confidence variiert je Pfad
- `Unused_SuppressionMarker_NoFinding` — `// noinspection UnusedRoutine`

---

## Bewusst weggelassen (Phase 2)

- **Cross-Unit-Symbol-Index erweitern um Bare-Calls** — der jetzige
  `gSymbolRefIndex` indexiert nur `Obj.Member`-Calls. Bare-Top-Level-
  Aufrufe (`Helper;`) landen nicht im Index. Falls SCA164 für
  interface-Routinen breit eingesetzt wird, brauchen wir das.
  Aufwand: ~50 LOC in `AddRefsFromNode` + Disambiguierung
  (Helper vs `obj.Helper`). Geht nach MVP, weil v1 für `excludeApi=true`
  arbeitet und cross-unit-public-Routinen NICHT flaggt.
- **Attribute-Awareness** (Guard 5) — Parser stellt `[Attr]` aktuell
  nicht als AST-Kind dar. Workaround: vor der `nkMethod`-Zeile im
  File-Text nach `[` greifen.
- **Interface-Implementierungs-Erkennung** (Guard 7) — AST liefert
  Klassen-Ancestors nur als Flachtext (`TypeRef`). Korrekte
  Auflösung braucht Symbol-Tabelle (siehe FP-Reduktion #4 in
  `Todo_FalsePositiveReduction.md`).

Beide Lücken werden im MVP durch Suppression-Marker abgefangen:
`// noinspection UnusedRoutine` per Routine.

---

## Aufwands-Schaetzung

| Komponente | LOC | Zeit |
|---|---|---|
| Detektor-Unit | ~180 | 1h |
| Tests | ~12 Tests x ~25 LOC = 300 | 1.5h |
| Pipeline-Integration (uses, AddD, FindingHelper, dproj × 3, dpk, json, FixHint, i18n) | analog SCA162/163 | 1h |
| Todo_neuerdetector.md fortfuehren | — | 15 min |
| **Gesamt** | **~480 LOC + 8 Files** | **~4h** |

---

## Implementierungs-Reihenfolge (wenn freigegeben)

1. Detector-Skelett mit nur Standalone-Implementation-Pfad (Phase 2 Path 1),
   keine FP-Guards außer der trivialen (Konstruktor/Destruktor).
2. Tests dazu — die ersten 4 positiven + 3 negativen Cases.
3. FP-Guards 1-4 + 9 + 10 nachziehen.
4. Phase 2 Path 2 (Interface-Routinen) mit `gSymbolRefIndex`-Lookup.
5. Phase 3 Path 3 (Klassen-Methode public/protected) hinter `excludeApi=false`-Flag.
6. DFM-Event-Handler-Guard (Punkt 8) — wenn `gDfmRepoIndex` einen
   passenden Helper hat oder wir einen bauen.
7. Pipeline-Rollout + Doku.

---

## Quellen

- SonarDelphi `UnusedRoutineCheck.java`:
  https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/UnusedRoutineCheck.java
- SonarDelphi `UnusedRoutineCheckTest.java`:
  https://github.com/integrated-application-development/sonar-delphi/blob/master/delphi-checks/src/test/java/au/com/integradev/delphi/checks/UnusedRoutineCheckTest.java
- Peganza Pascal Analyzer Code Reduction Report:
  https://www.peganza.com/PALHelp/code_reduction_report.htm
- codestudy.net "Finding Unused Code in Delphi" (Übersicht aller Ansätze):
  https://www.codestudy.net/blog/finding-unused-aka-dead-code-in-delphi/
- TMS FixInsight Developers Guide (Vergleich):
  https://download.tmssoftware.com/download/manuals/TMS%20FixInsight.pdf
