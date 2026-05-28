# Konzept: Grid-Performance bei 150 000 Befunden

## Symptom

- Bei **100** Befunden: kein Problem.
- Bei **100 000+** Befunden: Grid lagged massiv, Events stauen sich.

Linear-skalierende Latenz → irgendwo gibt es eine **O(N)-Operation pro Event**, obwohl Painting selbst O(visible) ist. Die Diagnose unten zeigt: das Problem liegt nicht im Painting, sondern in Event-Handler-Seiteneffekten.

## Audit der Grid-Event-Pfade

Alle Events am `FResultGrid` (uIDEAnalyserForm.pas Zeile 1218–1222 + WindowProc 2952):

| Event | Handler | Was läuft | Kosten |
|-------|---------|-----------|--------|
| OnDrawCell | `GridDrawCell` | Renderer-Config durchreichen (nach Fix `e1a3a24`) | O(visible) ✅ |
| OnSelectCell | `GridSelectCell` | `UpdateHelp` + `ProcessMessages` + `CopyFindingToClipboard` + **`HighlightAllFindingsInFile`** | **O(min(N, 10k))** ❌ |
| OnMouseDown | `GridMouseDown` | Header → Sort umschalten → `ApplyFilter` | **O(N log N)** ❌ |
| OnDblClick | `GridDblClick` | Editor-Sprung | O(1) ✅ |
| OnKeyDown | `GridKeyDown` | Shortcuts; Cursor-Navigation läuft VCL-default → triggert `OnSelectCell` | siehe oben |
| WindowProc | `GridWindowProc` | WM_MOUSEWHEEL coalescing (`e2bfc78`) | O(1) ✅ |

Zusätzliche UI-Events außerhalb des Grids, die O(N) triggern:

| Event | Handler | Was läuft | Kosten |
|-------|---------|-----------|--------|
| `SearchChange` (per Keystroke) | line 1531 → `ApplyFilter` | Filter-Scan + Sort + `HighlightAllFindingsInFile` | **O(N) pro Tastendruck** ❌ |
| `SeverityFilterChange` | → `ApplyFilter` | dito | O(N) |
| `TypeFilterChange` | → `ApplyFilter` | dito | O(N) |
| Datei-Watch (`HandleFileUpdate`) | line 1656 | Walk FAllFindings für Delete-Match | O(N) pro Datei-Save |

## O(N)-Hotspots im Detail

### Killer #1 — `HighlightAllFindingsInFile`
[uIDEAnalyserForm.pas:2682](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L2682)

```pascal
SetLength(Entries, FDisplayedFindings.Count);          // 10000-Element-Array
for i := 0 to FDisplayedFindings.Count - 1 do
begin
  F := FDisplayedFindings[i];
  ...
  var FH := FixHint(F);                                // case-Statement, ~100ns
  Entries[Count].FileName := F.FileName;
  Entries[Count].Title    := F.MissingVar;
  ...
  Entries[Count].Color    := SeverityAccent(DispSev);
  Entries[Count].Fix      := FH.After;
  ...
end;
GHighlighter.SetAllFindings(Entries);                  // Highlighter-Rebuild
```

**Gerufen von:**
- `ApplyFilter` → line 1525 (nach jedem Filter/Search-Wechsel)
- `GridSelectCell` → line 1927 (**bei jeder Pfeiltasten-Navigation und Klick**)
- `OpenFileAtLine` → line 2667

Kosten pro Aufruf: 10k × (String-Copies + `FixHint`-Lookup + `SeverityAccent`) + Highlighter `SetAllFindings`. Bei einem Cursor-Down-Hold geht das pro Frame an die UI.

### Killer #2 — `ApplyFilter` pro Keystroke
[uIDEAnalyserForm.pas:1531](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L1531)

`SearchChange` ruft direkt `ApplyFilter` ohne Debounce. Bei 100 k FAllFindings:
- O(N) Filter-Scan (`TFindingFilter.Matches` pro Eintrag, mit Lower-Case-Compare)
- O(N log N) Sort
- O(min(N, cap)) Highlighter-Rebuild via `HighlightAllFindingsInFile`

Der User tippt "memory" → 6 ApplyFilter-Aufrufe nacheinander. Jeder ~100–500 ms bei 100 k. UI friert ein.

### Killer #3 — `UpdateStats` pro Analyse
[uIDEAnalyserForm.pas:1779](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L1779)

`for f in FAllFindings do` — O(N) Sweep für die Severity-/Typ-Aufteilung. Wird nach jedem `PopulateFindings`, `HandleFileUpdate` und Profile-Change gerufen. Pro Aufruf gut, aber bei häufigen Re-Runs spürbar.

### Per-Cell-Kosten (nicht O(N), aber multipliziert pro Repaint)
- `ExtractFileName` für Spalte 0 (nicht gecacht)
- `FixHint` wird in `HighlightAllFindingsInFile` 10 000 mal gerufen
- `SeverityFromKindLevel` Mehrfach-Aufrufe

---

## Konzept — gestaffelter Fix-Plan

Reihenfolge nach **(Wirkung × Aufwand)**, jeweils mit Fallback auf den nächsten Tier, falls das Symptom bleibt.

### Tier A — Highlighter entkoppeln (das eigentliche Problem)

**A1. `HighlightAllFindingsInFile` debouncen**
Statt pro `OnSelectCell` sofort den ganzen Highlighter neu aufzubauen: einen `TTimer` von 200 ms anwerfen. Bei jedem Selection-Change Timer resetten. Erst wenn der User aufhört zu navigieren, einmal rebuilden. Pfeiltasten-Hold gibt jetzt 1 Rebuild statt 60/s.

**A2. Highlighter-Index inkrementell statt voll-rebuild**
`SetAllFindings(Entries)` ersetzt die GESAMTE Highlighter-Datenbank. Besser: pro Datei einen Bucket pflegen, bei `OnSelectCell` nur den Bucket der aktuellen Datei aktualisieren. Das fällt auf O(Findings-in-aktueller-Datei) ≪ O(N).

**A3. `FixHint` aus dem Hot-Path raus**
Im Entry-Aufbau wird `FixHint(F)` pro Eintrag gerufen — nur für `Entries[i].Desc` und `Entries[i].Fix` (Hover-Overlay). Wenn der Overlay-Text lazy bei Hover berechnet wird statt eager beim Index-Aufbau, fällt das pro Refresh komplett weg.

### Tier B — Filter-Pipeline debouncen + parallelisieren

**B1. `SearchChange` mit 200 ms Debounce**
Pro Keystroke nur einen Timer-Reset. Bei „memory" feuert ApplyFilter einmal nach Tippstopp, nicht 6 mal währenddessen.

**B2. Filter inkrementell halten**
Filter-Komposition ist additiv (Severity ∧ Type ∧ Search). Wenn nur das Such-Feld sich verfeinert (= mehr Buchstaben), kann das Ergebnis aus dem **vorherigen** `FDisplayedFindings` gefiltert werden statt vom vollen FAllFindings. Bei einem Such-Verlauf „m" → „me" → „mem" sinkt jeder Schritt im Suchraum.

**B3. Filter mit `TParallel.For`**
`TFindingFilter.Matches` ist seitenwirkungsfrei. Bei 100 k Einträgen lohnt sich Parallelisierung (4 Cores → ~3× schneller).

### Tier C — Stats und Watch-Pfad

**C1. `UpdateStats` inkrementell**
Statt voll-Scan: Counter werden bei jedem `FAllFindings.Add`/`Delete` mit-gepflegt. UpdateStats wird O(1).

**C2. `HandleFileUpdate` per Datei-Index**
Statt O(N) Walk über FAllFindings: TDictionary<FileName, TList<TLeakFinding>> als Index, Delete pro Datei in O(1) Bucket-Drop.

### Tier D — Painting-Effizienz (schon weitgehend gefixed)

| Item | Status |
|------|--------|
| `DoubleBuffered := True` | ✅ Zeile 1177 |
| `FGridConfig` einmal bauen (statt pro Cell) | ✅ `e1a3a24` |
| Direkt-Enum-Severity-Callback | ✅ |
| ExtractRelativePath-Cache (Standalone) | ✅ `019dcde` |
| Cached IDE-StyleServices | ✅ `e2bfc78` |
| WM_MOUSEWHEEL coalescing | ✅ `e2bfc78` |
| Per-Paint-Color-Cache | offen — kleiner Win |
| Last-set-Tracking für Canvas Brush/Font | offen — kleiner Win |

### Tier E — Architektur-Switch (Notausgang)

**E1. Migration auf `TVirtualStringTree`**
Echter Virtual-Tree, kein interner Cell-Storage, skaliert auf Millionen Zeilen. Größere Migration, aber dauerhafte Lösung. Würde Tier A und Tier D obsolet machen.

**E2. Display-Cap aggressiv senken**
Aktuell `UIMaxDisplayedFindings = 10000`. Auf 2000–3000 senken bringt die rohen TStringGrid-Operationen unter die Wahrnehmungsschwelle. Reine Symptom-Bekämpfung, aber sofort wirksam.

---

## Empfohlene Reihenfolge

1. **A1 + B1** zusammen — beides Debounce, kleine isolierte Änderungen, treffen die zwei klar identifizierten Killer **direkt**. Vermutlich reicht das schon.
2. **A3** danach — `FixHint` lazy, halbiert HighlightAllFindingsInFile-Kosten zusätzlich.
3. **A2** falls A1+A3 nicht reichen — größerer Eingriff (Highlighter-API), aber löst die Wurzel.
4. **C1** als Nebeneffekt — billiger Win.
5. **B3** nur wenn Such-Latenz nach B1+B2 noch stört.
6. **E1** als Notfall-Plan B falls nichts ausreicht.

## Diagnose-Empfehlung vor der Implementierung

Vor jedem Tier 1 ms-genaue Messung in der IDE einbauen (drei `QueryPerformanceCounter`-Punkte: vor SelectCell, nach UpdateHelp, nach HighlightAllFindingsInFile). Dann erst implementieren — damit verifizierbar wird, welcher Schritt die spürbaren ms gekostet hat. Ohne Messung implementieren und hoffen, dass es besser wird, ist riskant: 5 Stunden Arbeit, Symptom bleibt, niemand weiß warum.
