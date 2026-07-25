unit uTestParallelScan;

// Perf Stufe 2 (2026-07-25): Determinismus-Tests fuer den Slot-Merge der
// Per-File-Parallelisierung (uParallelScan.MergeSlotsDeterministic).
//
// Das SARIF-Byte-Gate "seriell vs. parallel" haengt daran, dass der Merge
// die Slots STRIKT in Dateilisten-Reihenfolge zusammenfuehrt - egal in
// welcher Reihenfolge die Worker fertig wurden. Diese Tests beweisen die
// Merge-Eigenschaften ohne Engine-Scan (reine Listen-/Dictionary-Logik):
//   * Findings-Gesamtreihenfolge == Slot-Index-Reihenfolge, unabhaengig von
//     der Fuell-Reihenfolge (simulierte out-of-order-Worker).
//   * Ownership-Transfer: Slots sind nach dem Merge leer; Slots.Free gibt
//     die uebertragenen Findings NICHT frei (kein Doppel-Free/UAF).
//   * Marker-Dictionary: identische Insertionsreihenfolge (und damit
//     identische Iterationsreihenfolge) wie der serielle Pfad.
//   * Log-Zeilen in Slot-Reihenfolge; Merge-Callback mit aufsteigenden
//     Indizes, auch fuer nil-Slots.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestParallelScan = class
  public
    [Test] procedure Merge_FindingsInSlotOrder_UnabhaengigVonFuellReihenfolge;
    [Test] procedure Merge_OwnershipTransfer_SlotsDanachLeer_KeinDoppelFree;
    [Test] procedure Merge_MarkerReihenfolge_WieSeriellesEinfuegen;
    [Test] procedure Merge_MarkerKollision_HaengtAnStattZuUeberschreiben;
    [Test] procedure Merge_LogZeilen_InSlotReihenfolge;
    [Test] procedure Merge_Callback_AufsteigendeIndizes_AuchFuerNilSlots;
    [Test] procedure Merge_LeereSlots_ErgebnisLeer;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  System.Generics.Collections, System.Generics.Defaults,
  uSCAConsts, uMethodd12, uParallelScan;

function MakeFinding(const AFile, ATag: string): TLeakFinding;
// Minimal befuelltes Finding - fuer den Merge zaehlt nur Identitaet/Ordnung.
begin
  Result := TLeakFinding.Create;
  Result.FileName   := AFile;
  Result.MethodName := '';
  Result.LineNumber := '1';
  Result.MissingVar := ATag;
  Result.SetKind(fkMemoryLeak);
end;

function MakeMarkerList(AMarkerLine: Integer): TList<TSuppressionMarker>;
var
  M : TSuppressionMarker;
begin
  Result := TList<TSuppressionMarker>.Create;
  M := Default(TSuppressionMarker);
  M.MarkerLine := AMarkerLine;
  M.TargetLine := 0;
  Result.Add(M);
end;

function NewMasterMarkers: TObjectDictionary<string, TList<TSuppressionMarker>>;
// Settings-Spiegel von TAnalyzeContext.SuppressionMarkers.
begin
  Result := TObjectDictionary<string, TList<TSuppressionMarker>>
    .Create([doOwnsValues], TIStringComparer.Ordinal);
end;

{ TTestParallelScan }

procedure TTestParallelScan.Merge_FindingsInSlotOrder_UnabhaengigVonFuellReihenfolge;
var
  Slots   : TObjectList<TParallelFileSlot>;
  Results : TObjectList<TLeakFinding>;
  Markers : TObjectDictionary<string, TList<TSuppressionMarker>>;
  i       : Integer;
begin
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Markers := NewMasterMarkers;
  try
    for i := 0 to 2 do
      Slots.Add(TParallelFileSlot.Create);

    // Out-of-order-Worker simulieren: Slot 2 zuerst fertig, dann 0, dann 1.
    Slots[2].Findings.Add(MakeFinding('c.pas', 'C1'));
    Slots[0].Findings.Add(MakeFinding('a.pas', 'A1'));
    Slots[0].Findings.Add(MakeFinding('a.pas', 'A2'));
    Slots[1].Findings.Add(MakeFinding('b.pas', 'B1'));

    MergeSlotsDeterministic(Slots, Results, Markers, nil, nil);

    // Gesamtreihenfolge MUSS der Slot-Index-Reihenfolge entsprechen
    // (= Dateilisten-Reihenfolge des seriellen Loops).
    Assert.AreEqual<Integer>(4, Results.Count);
    Assert.AreEqual('A1', Results[0].MissingVar);
    Assert.AreEqual('A2', Results[1].MissingVar);
    Assert.AreEqual('B1', Results[2].MissingVar);
    Assert.AreEqual('C1', Results[3].MissingVar);
  finally
    Markers.Free;
    Results.Free;
    Slots.Free;
  end;
end;

procedure TTestParallelScan.Merge_OwnershipTransfer_SlotsDanachLeer_KeinDoppelFree;
var
  Slots   : TObjectList<TParallelFileSlot>;
  Results : TObjectList<TLeakFinding>;
  Markers : TObjectDictionary<string, TList<TSuppressionMarker>>;
begin
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Markers := NewMasterMarkers;
  try
    Slots.Add(TParallelFileSlot.Create);
    Slots[0].Findings.Add(MakeFinding('a.pas', 'A1'));

    MergeSlotsDeterministic(Slots, Results, Markers, nil, nil);

    // Slot ist nach dem Merge leer - die Findings gehoeren jetzt Results.
    Assert.AreEqual<Integer>(0, Slots[0].Findings.Count);
    Assert.AreEqual<Integer>(1, Results.Count);

    // Slots.Free (owning) darf die uebertragenen Findings NICHT freigeben.
    FreeAndNil(Slots);
    // Zugriff nach Slots.Free: bei einem Doppel-Free waere das ein UAF -
    // unter FastMM-FullDebug schlaegt genau hier der Test fehl.
    Assert.AreEqual('A1', Results[0].MissingVar);
  finally
    Markers.Free;
    Results.Free;
    Slots.Free;   // nil-sicher (FreeAndNil oben)
  end;
end;

procedure TTestParallelScan.Merge_MarkerReihenfolge_WieSeriellesEinfuegen;
// Determinismus-Kern: das Master-Dictionary muss nach dem Merge dieselbe
// INSERTIONS-Reihenfolge gesehen haben wie der serielle Pfad (Datei fuer
// Datei). Da die Iterationsreihenfolge eines TDictionary eine Funktion der
// Insertionssequenz ist, vergleichen wir die Keys-Iteration eines seriell
// befuellten Referenz-Dictionaries mit der des Merge-Ergebnisses.
var
  Slots    : TObjectList<TParallelFileSlot>;
  Results  : TObjectList<TLeakFinding>;
  Merged   : TObjectDictionary<string, TList<TSuppressionMarker>>;
  SerRef   : TObjectDictionary<string, TList<TSuppressionMarker>>;
  MergedKeys, SerKeys : TArray<string>;
  i        : Integer;
const
  Hosts : array[0..3] of string = ('a.pas', 'b.pas', 'c.pas', 'd.pas');
begin
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Merged  := NewMasterMarkers;
  SerRef  := NewMasterMarkers;
  try
    // Referenz: serielle Insertionsreihenfolge (Datei 0..3).
    for i := 0 to High(Hosts) do
      SerRef.Add(Hosts[i], MakeMarkerList(i + 1));

    // Parallel: Slots out-of-order befuellt (3,1,0,2), Merge in Index-Folge.
    for i := 0 to High(Hosts) do
      Slots.Add(TParallelFileSlot.Create);
    Slots[3].Markers.Add(Hosts[3], MakeMarkerList(4));
    Slots[1].Markers.Add(Hosts[1], MakeMarkerList(2));
    Slots[0].Markers.Add(Hosts[0], MakeMarkerList(1));
    Slots[2].Markers.Add(Hosts[2], MakeMarkerList(3));

    MergeSlotsDeterministic(Slots, Results, Merged, nil, nil);

    Assert.AreEqual<Integer>(Length(Hosts), Merged.Count);
    // Inhalt pro Host korrekt uebertragen (MarkerLine = Datei-Index + 1).
    for i := 0 to High(Hosts) do
    begin
      Assert.IsTrue(Merged.ContainsKey(Hosts[i]), Hosts[i] + ' fehlt');
      Assert.AreEqual<Integer>(i + 1, Merged[Hosts[i]][0].MarkerLine);
    end;
    // Iterationsreihenfolge == serielle Referenz (gleiche Insertionssequenz).
    MergedKeys := Merged.Keys.ToArray;
    SerKeys    := SerRef.Keys.ToArray;
    Assert.AreEqual<Integer>(Length(SerKeys), Length(MergedKeys));
    for i := 0 to High(SerKeys) do
      Assert.AreEqual(SerKeys[i], MergedKeys[i],
        Format('Key-Reihenfolge weicht an Position %d ab', [i]));
  finally
    SerRef.Free;
    Merged.Free;
    Results.Free;
    Slots.Free;
  end;
end;

procedure TTestParallelScan.Merge_MarkerKollision_HaengtAnStattZuUeberschreiben;
var
  Slots   : TObjectList<TParallelFileSlot>;
  Results : TObjectList<TLeakFinding>;
  Markers : TObjectDictionary<string, TList<TSuppressionMarker>>;
begin
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Markers := NewMasterMarkers;
  try
    Slots.Add(TParallelFileSlot.Create);
    Slots.Add(TParallelFileSlot.Create);
    // Defensiv-Fall (im Per-File-Modell nicht erreichbar): beide Slots
    // liefern denselben Host-Key -> Merge haengt an, nichts geht verloren.
    Slots[0].Markers.Add('same.pas', MakeMarkerList(10));
    Slots[1].Markers.Add('same.pas', MakeMarkerList(20));

    MergeSlotsDeterministic(Slots, Results, Markers, nil, nil);

    Assert.AreEqual<Integer>(1, Markers.Count);
    Assert.AreEqual<Integer>(2, Markers['same.pas'].Count);
    Assert.AreEqual<Integer>(10, Markers['same.pas'][0].MarkerLine);  // Slot 0 zuerst
    Assert.AreEqual<Integer>(20, Markers['same.pas'][1].MarkerLine);
  finally
    Markers.Free;
    Results.Free;
    Slots.Free;
  end;
end;

procedure TTestParallelScan.Merge_LogZeilen_InSlotReihenfolge;
var
  Slots   : TObjectList<TParallelFileSlot>;
  Results : TObjectList<TLeakFinding>;
  Markers : TObjectDictionary<string, TList<TSuppressionMarker>>;
  Emitted : TStringList;
begin
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Markers := NewMasterMarkers;
  Emitted := TStringList.Create;
  try
    Slots.Add(TParallelFileSlot.Create);
    Slots.Add(TParallelFileSlot.Create);
    Slots[1].LogLines.Add('[2/2] b.pas');
    Slots[1].LogLines.Add('  Acquire: 0 ms (cache)');
    Slots[0].LogLines.Add('[1/2] a.pas');

    MergeSlotsDeterministic(Slots, Results, Markers,
      procedure(S: string)
      begin
        Emitted.Add(S);
      end,
      nil);

    Assert.AreEqual<Integer>(3, Emitted.Count);
    Assert.AreEqual('[1/2] a.pas', Emitted[0]);
    Assert.AreEqual('[2/2] b.pas', Emitted[1]);
    Assert.AreEqual('  Acquire: 0 ms (cache)', Emitted[2]);
  finally
    Emitted.Free;
    Markers.Free;
    Results.Free;
    Slots.Free;
  end;
end;

procedure TTestParallelScan.Merge_Callback_AufsteigendeIndizes_AuchFuerNilSlots;
var
  Slots   : TObjectList<TParallelFileSlot>;
  Results : TObjectList<TLeakFinding>;
  Markers : TObjectDictionary<string, TList<TSuppressionMarker>>;
  Seen    : TList<Integer>;
  i       : Integer;
begin
  // OwnsObjects=True + nil-Eintrag: TObjectList toleriert nil (Free-No-op).
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Markers := NewMasterMarkers;
  Seen    := TList<Integer>.Create;
  try
    Slots.Add(TParallelFileSlot.Create);
    Slots.Add(nil);   // Datei nie bearbeitet (z.B. Abbruch) -> Slot bleibt nil
    Slots.Add(TParallelFileSlot.Create);

    MergeSlotsDeterministic(Slots, Results, Markers, nil,
      procedure(Index: Integer)
      begin
        Seen.Add(Index);
      end);

    // Callback exakt einmal pro Index, streng aufsteigend - der parallele
    // Main-Loop reicht darueber AProgress(i+1, Total) nach.
    Assert.AreEqual<Integer>(3, Seen.Count);
    for i := 0 to 2 do
      Assert.AreEqual<Integer>(i, Seen[i]);
  finally
    Seen.Free;
    Markers.Free;
    Results.Free;
    Slots.Free;
  end;
end;

procedure TTestParallelScan.Merge_LeereSlots_ErgebnisLeer;
var
  Slots   : TObjectList<TParallelFileSlot>;
  Results : TObjectList<TLeakFinding>;
  Markers : TObjectDictionary<string, TList<TSuppressionMarker>>;
begin
  Slots   := TObjectList<TParallelFileSlot>.Create(True);
  Results := TObjectList<TLeakFinding>.Create(True);
  Markers := NewMasterMarkers;
  try
    Slots.Add(TParallelFileSlot.Create);
    Slots.Add(TParallelFileSlot.Create);

    MergeSlotsDeterministic(Slots, Results, Markers, nil, nil);

    Assert.AreEqual<Integer>(0, Results.Count);
    Assert.AreEqual<Integer>(0, Markers.Count);
  finally
    Markers.Free;
    Results.Free;
    Slots.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestParallelScan);

end.
