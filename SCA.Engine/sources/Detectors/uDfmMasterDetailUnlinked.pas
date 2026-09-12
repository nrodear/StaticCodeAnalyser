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

// noinspection-file NilComparison, TooLongLine, UnsortedUses, UnusedRoutine
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

// True, wenn eine der SQL-Properties der Komponente einen benannten
// Parameter (':' + Bezeichnerstart) traegt.
//
// WARUM DIESES GATE (Voll-Review 2026-09-12, Blocker): FireDAC (und
// ADO/IBX analog) dokumentiert parameter-basiertes Master-Detail als
// Standardweg - MasterSource gesetzt, Detail-SQL mit :param, dessen
// Name ein Master-Feld ist; FireDAC fuellt die Parameter beim
// Master-Scroll. MasterFields/IndexFieldNames sind dort WEDER noetig
// noch ueblich, einen Cross-Join gibt es nicht. Der Detektor meldete
// diese dokumentierte Standard-Konfiguration als lsError/ftBug.
//
// Konservativ je Evidenz-Politik ('Error = bewiesen'): JEDES
// parametrisierte SQL macht die Kopplung plausibel gewollt -> still.
// Ein ':param', der kein Master-Feld ist, kann hier nicht vom echten
// Fall unterschieden werden (die Master-Feldliste steht nicht im DFM).
// '::' (SQL-Cast-Syntax) zaehlt nicht als Parameter.
function HasParameterizedSql(N: TComponentNode): Boolean;
const
  SQL_PROPS : array[0..2] of string =
    ('SQL.Strings', 'CommandText', 'SelectSQL.Strings');
var
  PropName : string;
  V        : TPropValue;
  S        : string;
  i        : Integer;
begin
  Result := False;
  for PropName in SQL_PROPS do
  begin
    if not N.TryGetProperty(PropName, V) then Continue;
    if not (V.Kind in [pvkString, pvkStrList]) then Continue;
    S := V.RawValue;
    for i := 1 to Length(S) - 1 do
    begin
      if S[i] <> ':' then Continue;
      if (i > 1) and (S[i - 1] = ':') then Continue;
      if S[i + 1] = ':' then Continue;
      if CharInSet(S[i + 1], ['A'..'Z', 'a'..'z', '_']) then
        Exit(True);
    end;
  end;
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

      // 3. Parameter-basiertes Master-Detail (Begruendung am Helfer):
      // parametrisiertes Detail-SQL + MasterSource ist der dokumentierte
      // FireDAC-Standardweg OHNE MasterFields - kein Cross-Join, kein
      // Fund.
      if HasParameterizedSql(N) then Continue;

      // -> Treffer
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := Format(
        '%s.MasterSource=%s without MasterFields/IndexFieldNames - '
        + 'silent cross-join at runtime',
        [N.Name, MasterSrc]);
      F.SetKind(fkDfmMasterDetailUnlinked);
      Results.Add(F);
    end;
  finally
    All.Free;
  end;
end;

end.
