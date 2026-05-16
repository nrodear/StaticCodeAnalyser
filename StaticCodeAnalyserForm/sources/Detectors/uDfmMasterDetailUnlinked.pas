unit uDfmMasterDetailUnlinked;

// Detektor: TDataSet hat `MasterSource` gesetzt, aber weder
// `MasterFields` noch `IndexFieldNames` -> silent Cross-Join zur Laufzeit.
//
// Beispiel:
//   object qOrders: TFDQuery
//     MasterSource = dsCustomers          // Detail an Master gehaengt
//     // MasterFields fehlt!
//     // IndexFieldNames fehlt!
//   end
//
// Folge: bei jedem Master-Recordwechsel feuert ein "open Detail without
// join", das jede Order zu jedem Kunden joint -> Cartesian-Cross-Join.
// Bei realer Datenmenge sind das schnell hunderttausend Records statt
// dutzend; der Klick im Master-Grid laggt unsichtbar.
//
// Komplementaer zu fkDfmCircularDataSource (das Zyklen findet); dieser
// Detektor findet die andere haeufige Master-Detail-Fehlkonfiguration:
// "Link vergessen".
//
// Heuristik:
//   * Komponente hat MasterSource-Property mit Wert (pvkIdent, nicht leer)
//   * AND: hat KEIN MasterFields ODER MasterFields leer
//   * AND: hat KEIN IndexFieldNames ODER IndexFieldNames leer
//   -> Treffer
//
// Severity: lsError (echter Performance-/Data-Korrektheits-Bug).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmMasterDetailUnlinkedDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  EMIT_SEVERITY = lsError;

// Pruefe ob eine Identifier-Property gesetzt + nicht-leer ist.
function HasNonEmptyIdent(N: TComponentNode; const PropName: string): Boolean;
var
  V : TPropValue;
begin
  Result := N.TryGetProperty(PropName, V) and (V.Kind = pvkIdent)
        and (Trim(V.RawValue) <> '');
end;

// String-Property gesetzt + nicht-leer (MasterFields ist eine string-
// Property im DFM, nicht ein Identifier).
function HasNonEmptyString(N: TComponentNode; const PropName: string): Boolean;
var
  V : TPropValue;
begin
  Result := N.TryGetProperty(PropName, V) and (V.Kind = pvkString)
        and (Trim(V.RawValue) <> '');
end;

function GetIdent(N: TComponentNode; const PropName: string): string;
var
  V : TPropValue;
begin
  Result := '';
  if N.TryGetProperty(PropName, V) and (V.Kind = pvkIdent) then
    Result := Trim(V.RawValue);
end;

class procedure TDfmMasterDetailUnlinkedDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All : TList<TComponentNode>;
  N : TComponentNode;
  HasMasterFields : Boolean;
  HasIndexFields  : Boolean;
  MasterSrc : string;
  F : TLeakFinding;
begin
  if Graph = nil then Exit;
  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if N.Name = '' then Continue;
      // 1. MasterSource muss gesetzt sein
      MasterSrc := GetIdent(N, 'MasterSource');
      if MasterSrc = '' then Continue;

      // 2. MasterFields / IndexFieldNames pruefen
      HasMasterFields := HasNonEmptyString(N, 'MasterFields');
      HasIndexFields  := HasNonEmptyString(N, 'IndexFieldNames');
      if HasMasterFields or HasIndexFields then Continue;

      // -> Treffer
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format(
        '%s.MasterSource=%s without MasterFields/IndexFieldNames - '
        + 'silent cross-join at runtime',
        [N.Name, MasterSrc]);
      F.Severity   := EMIT_SEVERITY;
      F.Kind       := fkDfmMasterDetailUnlinked;
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.
