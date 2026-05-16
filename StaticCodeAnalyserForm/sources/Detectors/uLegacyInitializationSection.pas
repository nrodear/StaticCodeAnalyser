unit uLegacyInitializationSection;

// Detektor fuer Legacy-Initialization mit `begin..end.` statt
// `initialization..end.`.
//
// SonarDelphi-Aequivalent: communitydelphi:LegacyInitializationSection.
// Vor Delphi 2 wurde der Unit-Init-Block mit `begin..end.` markiert.
// Seit Delphi 2 ist `initialization..end.` (und optional `finalization`)
// der idiomatische Weg - er erlaubt einen separaten Finalization-Block
// fuer Cleanup beim Unit-Unload.
//
// Erkennung: vom Ende der Datei aus den ersten Section-Header suchen
// (`initialization`/`finalization` oder `begin`). Wenn `begin` der
// letzte Section-Header vor `end.` ist, ist es Legacy.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TLegacyInitializationSectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function ExtractFirstWord(const Line: string; out StartCol: Integer): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
  StartCol := 0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

// Sucht in der letzten Implementation-Zeile (oberhalb von `end.`) das
// erste Vorkommen von `begin`/`initialization`/`finalization`. Liefert
// die Zeile (-1 wenn keine gefunden) und den Keyword-Namen lowercase.
function FindLastInitMarker(Lines: TStringList; out Lower: string): Integer;
var
  i      : Integer;
  Word   : string;
  Col    : Integer;
  L      : string;
begin
  Result := -1;
  Lower := '';
  for i := Lines.Count - 1 downto 0 do
  begin
    Word := ExtractFirstWord(Lines[i], Col);
    if Word = '' then Continue;
    L := LowerCase(Word);
    if (L = 'begin') or (L = 'initialization') or (L = 'finalization') then
    begin
      Result := i;
      Lower := L;
      Exit;
    end;
    if (L = 'end') then
    begin
      // `end.` -> Unit terminator. Bevor begin/init/final gefunden.
      // Continue ueberspringt nicht; wir muessen das `end.` ignorieren.
      // Falls weitere `end;` darauf folgen (z.B. fuer Procedure-Bodies),
      // die ueberspringen wir auch.
      Continue;
    end;
    // Andere Worte: koennten Identifier-Statements im Init-Block sein
    // (z.B. `RegisterClass(...)`). Weiter zurueck suchen.
  end;
end;

class procedure TLegacyInitializationSectionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  Cached : Boolean;
  Marker : Integer;
  Lower  : string;
  F      : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Marker := FindLastInitMarker(Lines, Lower);
    if (Marker >= 0) and (Lower = 'begin') then
    begin
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Marker + 1);
      F.MissingVar := 'Legacy unit-init `begin..end.` - migrate to ' +
        '`initialization..end.` for explicit init/finalization separation.';
      F.SetKind(fkLegacyInitializationSection);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
