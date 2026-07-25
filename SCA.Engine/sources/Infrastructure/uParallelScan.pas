unit uParallelScan;

// ============================================================================
//  Perf Stufe 2 (2026-07-25) — Per-File-Parallelisierung: Slot-Puffer + Merge
// ============================================================================
//
// Infrastruktur fuer den parallelen ParseLeaks-Main-Loop (uStaticAnalyzer2):
// Jeder Datei-Index bekommt einen TParallelFileSlot, in den GENAU EIN Worker
// seine Ergebnisse schreibt (Findings, Log-Zeilen, Suppression-Marker).
// Nach dem Join aller Worker fuehrt MergeSlotsDeterministic die Slots STRIKT
// in Dateilisten-Reihenfolge zusammen - unabhaengig davon, in welcher
// Reihenfolge die Worker fertig wurden.
//
// DETERMINISMUS-GATE (Konzept_Performance25, Stufe 2):
//   * Findings werden pro Slot in Slot-Reihenfolge an die Master-Liste
//     angehaengt -> identische Gesamt-Reihenfolge wie der serielle Loop
//     (der pro Datei in Dateilisten-Reihenfolge appendet). SARIF muss
//     byte-identisch zur seriellen Ausgabe bleiben.
//   * Suppression-Marker werden pro Slot in Slot-Reihenfolge in das Master-
//     Dictionary uebertragen -> identische Insertion-Reihenfolge wie beim
//     seriellen CollectMarkersForScan-Aufruf pro Datei (die Emission der
//     UnusedSuppression-Findings iteriert das Dictionary, dessen
//     Iterationsreihenfolge von der Insertionsreihenfolge abhaengt).
//   * Log-Zeilen werden pro Slot in Slot-Reihenfolge an den Log-Sink
//     gereicht -> scan.log entspricht dem seriellen Layout (nur die
//     gemessenen ms-Werte differieren naturgemaess).
//
// Die Merge-Logik ist bewusst frei von Engine-/Scan-Abhaengigkeiten und
// dadurch ohne IDE-Build unit-testbar (uTestParallelScan).

interface

uses
  System.SysUtils, System.Classes,
  System.Generics.Collections, System.Generics.Defaults,
  uSCAConsts,      // TSuppressionMarker
  uMethodd12;      // TLeakFinding

type
  // Ergebnis-Puffer fuer GENAU EINE Datei des Scans. Wird ausschliesslich
  // vom bearbeitenden Worker beschrieben (kein Lock noetig) und nach dem
  // Join ausschliesslich vom Merge-Thread gelesen.
  TParallelFileSlot = class
  public
    // Findings dieser Datei, in Detektor-Emissions-Reihenfolge. BESITZT die
    // Findings bis zum Merge (OwnsObjects=True); MergeSlotsDeterministic
    // uebertraegt die Ownership an die Master-Liste (OwnsObjects -> False +
    // Clear), damit ein Abbruch VOR dem Merge nichts leakt und der Merge
    // nichts doppelt freigibt.
    Findings : TObjectList<TLeakFinding>;
    // scan.log-Zeilen dieser Datei (der Worker darf nicht selbst in den
    // TStreamWriter schreiben - der ist nicht thread-safe).
    LogLines : TStringList;
    // '// noinspection'-Marker dieser Datei (TSuppression.CollectMarkers-
    // ForScan schreibt pro Aufruf hoechstens EINEN Host-Key). Gleiche
    // Settings wie TAnalyzeContext.SuppressionMarkers (doOwnsValues +
    // case-insensitiver Pfad-Vergleich) - Pflicht, damit der Merge die
    // identische Semantik ins Master-Dictionary uebertraegt.
    Markers  : TObjectDictionary<string, TList<TSuppressionMarker>>;

    constructor Create;
    destructor Destroy; override;
  end;

  // Callback pro fertig gemergtem Slot (Index in Dateilisten-Reihenfolge).
  // Der parallele Main-Loop reicht darueber den Progress-Callback des
  // Aufrufers nach (auf dem AUFRUFER-Thread, nie aus einem Worker).
  TSlotMergedProc = reference to procedure(Index: Integer);

// Fuehrt die Slots deterministisch in Dateilisten-Reihenfolge (Index 0..n-1)
// zusammen:
//   * Slot.Findings -> AResults (Append in Slot-Reihenfolge, Ownership-
//     Transfer, s. TParallelFileSlot.Findings).
//   * Slot.Markers  -> AMarkers (ExtractPair-Transfer in Slot-Reihenfolge;
//     bereits vorhandene Keys werden angehaengt statt ueberschrieben -
//     defensiv, im Per-File-Modell kollidieren Host-Keys nicht).
//   * Slot.LogLines -> ALogSink (eine Zeile pro Aufruf; nil = kein Log).
//   * AOnSlotMerged(i) nach jedem Slot (nil = kein Callback).
// nil-Slots (Datei wurde z.B. wegen Abbruch nie bearbeitet) werden
// uebersprungen. AResults/AMarkers duerfen nicht nil sein.
procedure MergeSlotsDeterministic(
  ASlots      : TList<TParallelFileSlot>;
  AResults    : TObjectList<TLeakFinding>;
  AMarkers    : TObjectDictionary<string, TList<TSuppressionMarker>>;
  ALogSink    : TProc<string>;
  AOnSlotMerged: TSlotMergedProc);

implementation

{ TParallelFileSlot }

constructor TParallelFileSlot.Create;
begin
  inherited Create;
  Findings := TObjectList<TLeakFinding>.Create(True);
  LogLines := TStringList.Create;
  // Settings-Spiegel von TAnalyzeContext.SuppressionMarkers (uAnalyzeContext.
  // Create): doOwnsValues + TIStringComparer.Ordinal (case-insensitive Pfade).
  Markers  := TObjectDictionary<string, TList<TSuppressionMarker>>
    .Create([doOwnsValues], TIStringComparer.Ordinal);
end;

destructor TParallelFileSlot.Destroy;
begin
  Findings.Free;   // gibt nur frei, was der Merge NICHT uebernommen hat
  LogLines.Free;
  Markers.Free;
  inherited;
end;

procedure MergeSlotsDeterministic(
  ASlots      : TList<TParallelFileSlot>;
  AResults    : TObjectList<TLeakFinding>;
  AMarkers    : TObjectDictionary<string, TList<TSuppressionMarker>>;
  ALogSink    : TProc<string>;
  AOnSlotMerged: TSlotMergedProc);
var
  i, j    : Integer;
  Slot    : TParallelFileSlot;
  Key     : string;
  Pair    : TPair<string, TList<TSuppressionMarker>>;
  Existing: TList<TSuppressionMarker>;
  Keys    : TArray<string>;
begin
  if (ASlots = nil) or (AResults = nil) or (AMarkers = nil) then Exit;

  for i := 0 to ASlots.Count - 1 do
  begin
    Slot := ASlots[i];
    if Slot <> nil then
    begin
      // 1) Log-Zeilen in Datei-Reihenfolge (Layout wie der serielle Loop).
      if Assigned(ALogSink) then
        for j := 0 to Slot.LogLines.Count - 1 do
          ALogSink(Slot.LogLines[j]);

      // 2) Findings: Append in Slot-Reihenfolge + Ownership-Transfer.
      //    OwnsObjects VOR dem Clear abschalten, sonst wuerde Clear die
      //    soeben uebertragenen Findings freigeben (Use-after-free).
      Slot.Findings.OwnsObjects := False;
      for j := 0 to Slot.Findings.Count - 1 do
        AResults.Add(Slot.Findings[j]);
      Slot.Findings.Clear;

      // 3) Marker: ExtractPair loest die Values aus dem doOwnsValues-Slot-
      //    Dictionary, OHNE sie freizugeben -> Master uebernimmt Ownership.
      //    Keys-Snapshot, weil ExtractPair das Dictionary mutiert.
      if Slot.Markers.Count > 0 then
      begin
        Keys := Slot.Markers.Keys.ToArray;
        for Key in Keys do
        begin
          Pair := Slot.Markers.ExtractPair(Key);
          if Pair.Value = nil then Continue;
          if AMarkers.TryGetValue(Pair.Key, Existing) then
          begin
            // Defensiv (kollidiert im Per-File-Modell nicht): anhaengen
            // statt ueberschreiben, damit keine Marker verloren gehen.
            Existing.AddRange(Pair.Value);
            Pair.Value.Free;
          end
          else
            AMarkers.Add(Pair.Key, Pair.Value);
        end;
      end;
    end;

    if Assigned(AOnSlotMerged) then
      AOnSlotMerged(i);
  end;
end;

end.
