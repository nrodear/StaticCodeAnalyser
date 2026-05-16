unit uDfmCircularDataSource;

// Detektor: Zyklus in DataSource <-> DataSet / MasterSource-Verkettung.
//
// Beispiel (direkter Zyklus):
//   object dsOrder: TDataSource
//     DataSet = qOrder
//   end
//   object qOrder: TADOQuery
//     MasterSource = dsOrder       <- circular
//   end
//
// Beispiel (transitiver Zyklus):
//   dsA.DataSet=qA, qA.MasterSource=dsB, dsB.DataSet=qB, qB.MasterSource=dsA
//
// Zur Laufzeit haengt sich der Master-Detail-Refresh in einer Endlos-
// Schleife auf, oft erst bei BeforeOpen sichtbar (UI haengt, kein Crash).
//
// Erkennung pragmatisch ueber Duck-Typing - eine Komponente nimmt an einer
// Master-Detail-Kette teil, wenn sie eine 'DataSet'- oder 'MasterSource'-
// Property mit pvkIdent-Wert hat. Klassen-Whitelist nicht noetig: die
// Property-Namen sind im DFM-Streamer-Modell hart kodiert und werden so
// auch von Drittanbieter-Komponenten respektiert.
//
// Algorithmus: iterativer DFS mit Farb-State (white/gray/black). Bei
// gray-Wiederbegegnung wird der Pfad zwischen dem ersten gray-Vorkommen
// und der aktuellen Position als Zyklus rekonstruiert und jede beteiligte
// Komponente bekommt einen Befund mit dem vollstaendigen Pfad als Kontext.
//
// Schweregrad: lsError, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmCircularDataSourceDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

type
  TNodeColor = (ncWhite, ncGray, ncBlack);

const
  // Properties, die im DFM-Streamer-Modell eine Master-Detail-Kante bilden.
  // Whitelist hier ist konservativ - DataSource (auf TDBEdit etc.) ist
  // bewusst NICHT drin, weil von dort keine Rueckkante moeglich ist und sie
  // nur als eingehender Hop bei der TDBEdit liegt, nicht in der Kette.
  EDGE_PROPS: array[0..1] of string = ('DataSet', 'MasterSource');

class procedure TDfmCircularDataSourceDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  function CollectEdges(All: TList<TComponentNode>): TDictionary<string, TList<string>>;
  var
    N    : TComponentNode;
    P    : string;
    V    : TPropValue;
    K    : string;
    List : TList<string>;
  begin
    Result := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
    for N in All do
    begin
      if N.Name = '' then Continue;
      List := TList<string>.Create;
      try
        for P in EDGE_PROPS do
          if N.TryGetProperty(P, V) and (V.Kind = pvkIdent) then
          begin
            K := Trim(V.RawValue);
            if K <> '' then List.Add(K);
          end;
        Result.Add(LowerCase(N.Name), List);
        List := nil;
      finally
        List.Free;                              // nil wenn uebernommen
      end;
    end;
  end;

  procedure AddCycleFindings(Names: TList<string>; All: TList<TComponentNode>);
  var
    I       : Integer;
    N       : TComponentNode;
    Joined  : string;
    F       : TLeakFinding;
    Found   : TComponentNode;
  begin
    Joined := '';
    for I := 0 to Names.Count - 1 do
    begin
      if I > 0 then Joined := Joined + ' -> ';
      Joined := Joined + Names[I];
    end;
    Joined := Joined + ' -> ' + Names[0];      // schliessen

    for I := 0 to Names.Count - 1 do
    begin
      Found := nil;
      for N in All do
        if SameText(N.Name, Names[I]) then
        begin
          Found := N;
          Break;
        end;
      if Found = nil then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Found.Line);
      F.MissingVar := Format('%s is part of a master-detail cycle: %s',
                              [Found.Name, Joined]);
      F.SetKind(fkDfmCircularDataSource);
      Results.Add(F);
    end;
  end;

var
  All         : TList<TComponentNode>;
  Edges       : TDictionary<string, TList<string>>;
  Color       : TDictionary<string, TNodeColor>;
  Reported    : TDictionary<string, Boolean>;
  PathStack   : TList<string>;
  StartNode   : TComponentNode;
  Start, Cur, Target : string;
  TargetList  : TList<string>;
  CycleNames  : TList<string>;
  Hit, Found  : Boolean;
  I, Idx      : Integer;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    Edges    := CollectEdges(All);
    Color    := TDictionary<string, TNodeColor>.Create;
    Reported := TDictionary<string, Boolean>.Create;
    try
      for StartNode in All do
        Color.AddOrSetValue(LowerCase(StartNode.Name), ncWhite);

      // Iterativer DFS pro noch nicht erkundetem Knoten. Wir benutzen
      // Color, Parent und einen aktuellen Pfad-Stack zur Rekonstruktion.
      for StartNode in All do
      begin
        Start := LowerCase(StartNode.Name);
        if Color[Start] <> ncWhite then Continue;

        // DFS mit explizitem Stack der aktuellen Tiefe (PathStack haelt nur
        // die Komponenten auf dem aktuellen Wurzel-Pfad). Iterative
        // Variante: wir simulieren rekursive Aufrufe ueber Color-Updates.
        Color[Start] := ncGray;
        PathStack    := TList<string>.Create;
        try
          PathStack.Add(Start);
          Cur := Start;

          while PathStack.Count > 0 do
          begin
            Hit := False;
            if Edges.TryGetValue(Cur, TargetList) then
            begin
              for I := 0 to TargetList.Count - 1 do
              begin
                Target := LowerCase(TargetList[I]);
                if not Color.ContainsKey(Target) then Continue;  // Edge ins Leere

                if Color[Target] = ncWhite then
                begin
                  Color[Target] := ncGray;
                  PathStack.Add(Target);
                  Cur := Target;
                  Hit := True;
                  Break;
                end
                else if Color[Target] = ncGray then
                begin
                  // Zyklus gefunden: Pfad zurueck zu Target rekonstruieren.
                  // PathStack enthaelt Wurzel..Cur; Target liegt irgendwo
                  // weiter oben im Stack.
                  Idx := PathStack.IndexOf(Target);
                  if Idx >= 0 then
                  begin
                    CycleNames := TList<string>.Create;
                    try
                      for var J := Idx to PathStack.Count - 1 do
                        CycleNames.Add(PathStack[J]);

                      // Doppel-Meldung vermeiden: jeder Komponenten-Name
                      // produziert nur einmal einen Befund pro Lauf.
                      Found := False;
                      for var J := 0 to CycleNames.Count - 1 do
                        if Reported.ContainsKey(CycleNames[J]) then
                        begin
                          Found := True; Break;
                        end;
                      if not Found then
                      begin
                        AddCycleFindings(CycleNames, All);
                        for var J := 0 to CycleNames.Count - 1 do
                          Reported.AddOrSetValue(CycleNames[J], True);
                      end;
                    finally
                      CycleNames.Free;
                    end;
                  end;
                  // Pruefe weitere Kanten dieses Knotens
                end;
              end;
            end;

            if not Hit then
            begin
              // Alle Kanten erkundet -> Knoten schwarz markieren, im Stack
              // einen Schritt zurueck.
              Color[Cur] := ncBlack;
              PathStack.Delete(PathStack.Count - 1);
              if PathStack.Count > 0 then
                Cur := PathStack[PathStack.Count - 1];
            end;
          end;
        finally
          PathStack.Free;
        end;
      end;
    finally
      Reported.Free;
      Color.Free;
      Edges.Free;
    end;
  finally
    All.Free;
  end;
end;

end.
