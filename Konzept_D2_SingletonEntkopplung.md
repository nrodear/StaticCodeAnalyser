# Konzept D.2 — Singleton-Entkopplung

Roadmap-Punkt aus
[`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) §D.2.

## 1. Zielbild

Aktuell hat der Engine-Code 5 globale Singleton-Variablen:

| Global | Unit | Lifecycle | Konsumenten |
|---|---|---|---|
| `gAstFileCache` | uAstFileCache.pas | scan-scoped | uParser2, uSuppression, uSymbolReferenceIndex, ~140 Detektoren (indirekt) |
| `gFileTextCache` | uFileTextCache.pas | scan-scoped, **lebt jetzt durch Post-Scan** (Commit 120894a) | uSuppression, uFindingFingerprint, 7 File-Scan-Detektoren |
| `gSymbolRefIndex` | uSymbolReferenceIndex.pas | scan-scoped | uVisibilityCheck (SCA052 nach A.3-Minimal) |
| `gDfmRepoIndex` | uDfmRepoIndex.pas | scan-scoped | uDfmAnalysisRunner, alle 22 DFM-Detektoren |
| `gDetectorTimings` | uStaticAnalyzer2.pas | scan-scoped, optional | uConsoleRunner (für `--time-detectors`) |

Zielbild:

```pascal
type
  TAnalyzeContext = class
  public
    AstFileCache    : TAstFileCache;
    FileTextCache   : TFileTextCache;
    SymbolRefIndex  : TSymbolReferenceIndex;
    DfmRepoIndex    : TDfmRepoIndex;
    DetectorTimings : TDictionary<string, TPair<Int64, Integer>>;
    constructor Create;
    destructor Destroy; override;
  end;

TStaticAnalyzer2.AnalyzeLeaksRecursive(Path; AContext: TAnalyzeContext;
  ...);
```

Detektoren bekommen `AContext` als Parameter. Globals werden komplett
entfernt.

## 2. Aufwand-Schätzung — realistisch

Konzept-Original schätzte **1 Tag**. Realistic-Audit:

| Komponente | Touch-Punkte | Aufwand |
|---|---|---|
| TAnalyzeContext-Record definieren + Tests | 1 neue Unit | 1-2h |
| uStaticAnalyzer2 - Context lifecycle + 32 Refs ersetzen | 32 lines | 2-3h |
| uSuppression / uFindingFingerprint / uBaseline - Context-Param hinzufügen | 3 Units | 1-2h |
| ~140 Detektoren - AnalyzeUnit-Signatur erweitern um Context | 140 Detektoren × 2 Stellen | **8-12h** |
| Tests - 100+ Test-Setups die Detektoren direkt aufrufen | DUnitX-Suite | **6-10h** |
| Pipeline-Wrapper (`AddD`-Macro) anpassen | 1 Stelle | 1h |
| Build + Test + Audit | | 2-4h |

**Total: 3-5 Tage**, nicht 1d. Der Hauptaufwand liegt in den ~140
Detector-Signature-Änderungen + Tests.

## 3. Kosten/Nutzen — ehrlich

### Was D.2 löst

- **Multi-Instance-Safety**: paralleler Scan zweier Repos im selben
  Prozess (z.B. Background-Service der mehrere Repos überwacht)
- **Test-Isolation**: Tests teilen sich aktuell die Globals zwischen
  Tests, daher Reihenfolge-Abhängigkeit möglich
- **Klare API-Grenzen**: Context-Parameter macht explizit was ein
  Detector braucht (heute: implicit globaler State)

### Was D.2 NICHT löst (aktuell kein konkretes Problem)

- **Performance**: kein Speed-Up, eher kleine Regression durch
  Parameter-Passing
- **Bestehende Bugs**: die scan-relevanten Cache-Issues (Stale-Cache,
  Memory-Leak) sind in Commit **1e7e193** (mtime-Invalidation) und
  **120894a** (Re-Create-Pattern bei Scan-Start) gefixt
- **Funktionalität**: kein neues Feature für User

### Wo D.2 in der Roadmap natürlich passt

**Zusammen mit D.1 (Engine-Extraction).** D.1 spalt die Engine in
ein separates Projekt ab. Das ist der natürliche Zeitpunkt für
sauberen Re-Design der Engine-API ohne Globals. D.2 isoliert nach
D.1 hat sehr geringen zusätzlichen Aufwand weil die Engine sowieso
neu re-modularisiert wird.

D.2 **vor** D.1 ist viel Refactor-Aufwand der dann bei D.1 nochmal
geschoben/angepasst wird.

## 4. Empfehlung

**D.2 NICHT als eigenständigen Sprint angehen.** Stattdessen:

### Pfad A — D.1 zuerst (empfohlen)

1. D.1 Engine-Extraction (siehe `Konzept_EngineExtraction.md`) — ~1 Tag
2. D.2 als integraler Teil von D.1 — die neue Engine-API bekommt
   `TAnalyzeContext` direkt eingebaut, ohne Globals
3. Aufwand-Total: 2-3 Tage (statt 3-5 D.2-only + nochmal D.1)

### Pfad B — D.2 minimal als Beifang

Wenn D.1 nicht ansteht: nur den **neu identifizierten Bug** adressieren,
nicht den ganzen Refactor:

- Test-Isolation-Hooks pro Scan-Start (`FreeAndNil(...)`-vor-`Create`-
  Pattern) — ist heute schon teilweise da (commit 120894a). Vervoll-
  ständigen für alle 5 Singletons, ohne Context-Pattern.
- Aufwand: 1h.
- Effekt: Test-Isolation-Risiko adressiert ohne 3-5 d Refactor.

## 5. Wenn D.2 trotzdem als Sprint kommt — Phasen-Plan

Falls man später D.2 standalone macht, sinnvolle Aufteilung:

| Phase | Inhalt | Aufwand |
|---|---|---|
| **D.2.1** | TAnalyzeContext-Record + Init/Destroy + Test | 2h |
| **D.2.2** | uStaticAnalyzer2 nutzt Context intern, Globals bleiben als Backward-Compat-Setter | 3h |
| **D.2.3** | Detector-Signature-Migration in Batches (Bug/Memory zuerst, Style/Naming zuletzt) | 8-12h verteilt |
| **D.2.4** | Tests anpassen | 6-10h |
| **D.2.5** | Globals entfernen | 2h |

D.2.1 + D.2.2 sind das **80%-Resultat**. Danach hat man Context als
Pattern etabliert ohne die ~140 Detektoren angefasst zu haben.
D.2.3-D.2.5 sind die letzten 20% Eleganz.

## 6. Verwandte Konzepte

- [`Konzept_EngineExtraction.md`](Konzept_EngineExtraction.md) — D.1,
  natürlicher Heimat-Sprint für D.2
- [`Konzept_ProjektAufteilung.md`](Konzept_ProjektAufteilung.md) —
  4-Projekt-Architektur (Alternative zu D.1, würde D.2 auch enthalten)
- [`Konzept_ScannerQualitaet.md`](Konzept_ScannerQualitaet.md) §D.2 —
  Original-Eintrag in der Roadmap

---

## 7. Entscheidung

**Status: NICHT-jetzt.** Begründung dokumentiert oben. Re-Evaluation
wenn:

- D.1 angegangen wird → dann D.2 integrieren
- Konkretes Multi-Instance-Use-Case aufkommt (z.B. Service der
  mehrere Repos parallel scannt)
- Test-Isolation-Bug konkret reproduziert wird (heute spekulativ)

Konzept_ScannerQualitaet.md sollte D.2 entsprechend markieren:
status = **"deferred bis D.1"**.
