unit uDfmDuplicateBinding;

// Detektor: Mehrfach gebundene DB-Felder.
//
// Wenn mehrere Komponenten denselben (DataSource, DataField) binden,
// kommt es spaetestens beim Post zu Update-Konflikten - zwei TDBEdit
// auf dem gleichen Field schreiben unkoordiniert in den gleichen
// Dataset-Slot. Klassischer Designfehler nach Copy/Paste einer Komponente.
//
// Erkennung pragmatisch:
//   * Komponente muss BEIDE Properties haben: DataSource (Ident) und
//     DataField (String oder Ident, gangbar je nach VCL/Drittanbieter).
//   * Schluessel = case-insensitives Tupel (DataSource, DataField).
//   * Wenn >= 2 Komponenten den gleichen Schluessel teilen, werden ALLE
//     beteiligten Komponenten je ein Finding bekommen, damit der User
//     in der Liste sieht, welche Stellen gemeinsam betroffen sind.
//
// Bewusst NICHT in Phase 1:
//   * TDBText-Whitelist (rein lesend, kein Update-Konflikt) -> Phase 2,
//     wenn analyser.ini fuer Whitelist verfuegbar ist.
//   * Cross-Form-Erkennung -> Iteration 3, braucht Repo-weiten Graph.
//
// Schweregrad: lsWarning, FindingType: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmDuplicateBindingDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

function TryGetBindingKey(N: TComponentNode; out Key: string;
  out DataSourceName, DataFieldName: string): Boolean;
var
  Ds, Df: TPropValue;
begin
  Result := False;
  if not N.TryGetProperty('DataSource', Ds) then Exit;
  if not N.TryGetProperty('DataField',  Df) then Exit;
  // DataSource ist typischerweise ein Ident (Komponenten-Referenz), kann
  // aber auch eine qualifizierte Form-Pfad-Ref sein -> RawValue trimmen.
  // DataField ist typisch pvkString.
  if (Trim(Ds.RawValue) = '') or (Trim(Df.RawValue) = '') then Exit;

  DataSourceName := Trim(Ds.RawValue);
  DataFieldName  := Trim(Df.RawValue);
  // Case-insensitiver Schluessel: Delphi-Felder/Komponenten sind nicht
  // case-sensitiv.
  Key := LowerCase(DataSourceName) + #1 + LowerCase(DataFieldName);
  Result := True;
end;

class procedure TDfmDuplicateBindingDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure AddFinding(N: TComponentNode; const DataSourceName,
    DataFieldName: string; Line: Integer);
  var
    F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Format('%s (%s) shares DataSource=%s, DataField=%s',
                            [N.Name, N.ClassRef, DataSourceName, DataFieldName]);
    F.SetKind(fkDfmDuplicateBinding);
    Results.Add(F);
  end;

var
  All     : TList<TComponentNode>;
  Buckets : TObjectDictionary<string, TList<TComponentNode>>;
  KeyToDs : TDictionary<string, string>;
  KeyToDf : TDictionary<string, string>;
  N       : TComponentNode;
  Key     : string;
  Ds, Df  : string;
  Bucket  : TList<TComponentNode>;
  Pair    : TPair<string, TList<TComponentNode>>;
begin
  if Graph = nil then Exit;

  All     := Graph.EnumerateAll;
  Buckets := TObjectDictionary<string, TList<TComponentNode>>.Create([doOwnsValues]);
  KeyToDs := TDictionary<string, string>.Create;
  KeyToDf := TDictionary<string, string>.Create;
  try
    for N in All do
    begin
      if not TryGetBindingKey(N, Key, Ds, Df) then Continue;

      if not Buckets.TryGetValue(Key, Bucket) then
      begin
        Bucket := TList<TComponentNode>.Create;
        Buckets.Add(Key, Bucket);
        KeyToDs.Add(Key, Ds);
        KeyToDf.Add(Key, Df);
      end;
      Bucket.Add(N);
    end;

    for Pair in Buckets do
      if Pair.Value.Count >= 2 then
      begin
        Ds := KeyToDs[Pair.Key];
        Df := KeyToDf[Pair.Key];
        for N in Pair.Value do
          AddFinding(N, Ds, Df, N.Line);
      end;
  finally
    KeyToDf.Free;
    KeyToDs.Free;
    Buckets.Free;
    All.Free;
  end;
end;

end.
