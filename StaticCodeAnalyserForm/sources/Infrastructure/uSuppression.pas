unit uSuppression;

// Filter fuer 'noinspection'-Kommentare im Quelltext.
//
// Erlaubt Unterdruecken einzelner Befunde direkt im Code:
//
//   // noinspection NilDeref
//   obj.DoSomething;
//
//   // noinspection MemoryLeak, MissingFinally
//   list := TStringList.Create;
//
//   // noinspection All
//   // unterdrueckt alle Pruefungen fuer die naechste Code-Zeile
//
// Die Suppression gilt fuer die naechste nicht-leere, nicht-Kommentar-Zeile.
// Mehrere Kategorien koennen mit Komma oder Leerzeichen getrennt werden.
//
// Erkannte Kategorien (case-insensitive): jeder Eintrag in KIND_META
// (uSCAConsts.pas) plus 'All' / '*'. Die Liste wird ueber KindFromName-
// Reverse-Lookup aufgeloest - Single source of truth ist KIND_META,
// damit hier kein Drift mehr entsteht (frueher: statische Liste, hat
// dreimal Detektoren verpasst: TodoComment, EmptyMethod, DuplicateBlock).

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TSuppressedKinds = set of TFindingKind;

  TSuppression = class
  public
    // Filtert unterdrueckte Befunde aus der Liste (in-place).
    class procedure ApplyToFindings(
      Findings: TObjectList<TLeakFinding>); static;
  private
    class function ParseComment(const Line: string;
      out Kinds: TSuppressedKinds): Boolean; static;
    class function KindFromName(const Name: string;
      out Kind: TFindingKind): Boolean; static;
    class function BuildMap(const FileName: string): TDictionary<Integer,
      TSuppressedKinds>; static;
  end;

implementation

class function TSuppression.KindFromName(const Name: string;
  out Kind: TFindingKind): Boolean;
// Delegiert an KIND_META-Reverse-Lookup in uSCAConsts (single source
// of truth). Vorher: 21-Eintrag if-elseif-Kette die zweimal in der
// Vergangenheit unsynchron geworden ist (zuletzt: TodoComment,
// EmptyMethod, DuplicateBlock fehlten).
begin
  Result := uSCAConsts.KindFromName(Name, Kind);
end;

class function TSuppression.ParseComment(const Line: string;
  out Kinds: TSuppressedKinds): Boolean;
const
  TAG = 'noinspection';
var
  Trimmed   : string;
  KindStrs  : TArray<string>;
  K         : TFindingKind;
  KS        : string;
  HasAny    : Boolean;
begin
  Result := False;
  Kinds  := [];

  Trimmed := TrimLeft(Line);
  if not Trimmed.StartsWith('//') then Exit;
  Trimmed := TrimLeft(Trimmed.Substring(2));
  if not Trimmed.ToLower.StartsWith(TAG) then Exit;

  Trimmed := Trimmed.Substring(Length(TAG));
  // Optional ':' direkt nach 'noinspection' akzeptieren
  if Trimmed.StartsWith(':') then
    Trimmed := Trimmed.Substring(1);
  Trimmed := Trim(Trimmed);

  // 'All' = alle Kategorien
  if SameText(Trimmed, 'all') or (Trimmed = '*') then
  begin
    for K := Low(TFindingKind) to High(TFindingKind) do
      Include(Kinds, K);
    Result := True;
    Exit;
  end;

  KindStrs := Trimmed.Split([',', ';', ' ', #9]);
  HasAny := False;
  for KS in KindStrs do
  begin
    if Trim(KS) = '' then Continue;
    if KindFromName(KS, K) then
    begin
      Include(Kinds, K);
      HasAny := True;
    end;
  end;
  Result := HasAny;
end;

class function TSuppression.BuildMap(const FileName: string):
  TDictionary<Integer, TSuppressedKinds>;
var
  Lines      : TStringList;
  Kinds      : TSuppressedKinds;
  TargetLine : Integer;
  i, j       : Integer;
  L          : string;
begin
  Result := TDictionary<Integer, TSuppressedKinds>.Create;
  if not FileExists(FileName) then Exit;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName);
    except
      try Lines.LoadFromFile(FileName, TEncoding.UTF8);
      except
        try Lines.LoadFromFile(FileName, TEncoding.Unicode);
        except
          Exit; // unleserlich – keine Suppressions
        end;
      end;
    end;

    for i := 0 to Lines.Count - 1 do
    begin
      if not ParseComment(Lines[i], Kinds) then Continue;
      // Naechste echte Code-Zeile finden (nicht leer, nicht Kommentar)
      TargetLine := i + 2; // 1-basiert; default = direkte naechste Zeile
      for j := i + 1 to Lines.Count - 1 do
      begin
        L := TrimLeft(Lines[j]);
        if L = '' then Continue;
        if L.StartsWith('//') then Continue;
        TargetLine := j + 1;
        Break;
      end;
      Result.AddOrSetValue(TargetLine, Kinds);
    end;
  finally
    Lines.Free;
  end;
end;

class procedure TSuppression.ApplyToFindings(
  Findings: TObjectList<TLeakFinding>);
var
  FileMaps   : TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>;
  i, Line    : Integer;
  F          : TLeakFinding;
  Map        : TDictionary<Integer, TSuppressedKinds>;
  Suppressed : TSuppressedKinds;
begin
  if (Findings = nil) or (Findings.Count = 0) then Exit;

  FileMaps := TObjectDictionary<string, TDictionary<Integer, TSuppressedKinds>>.Create([doOwnsValues]);
  try
    // Rueckwaerts iterieren – sicher beim Loeschen
    for i := Findings.Count - 1 downto 0 do
    begin
      F := Findings[i];
      if (F.FileName = '') or (F.Kind = fkFileReadError) then Continue;

      if not FileMaps.TryGetValue(F.FileName, Map) then
      begin
        Map := BuildMap(F.FileName);
        FileMaps.Add(F.FileName, Map);
      end;

      Line := StrToIntDef(F.LineNumber, 0);
      if Line <= 0 then Continue;

      if Map.TryGetValue(Line, Suppressed) and (F.Kind in Suppressed) then
        Findings.Delete(i);
    end;
  finally
    FileMaps.Free;
  end;
end;

end.
