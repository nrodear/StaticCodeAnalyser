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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TLegacyInitializationSectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

// Liefert das erste Nicht-Whitespace-Zeichen NACH dem ersten Wort einer
// Zeile (oder #0 wenn keines).
function CharAfterFirstWord(const Line: string): Char;
var
  i, n : Integer;
begin
  Result := #0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  if i > n then Exit;
  Result := Line[i];
end;

// Walked backwards from end of file. Trackt Procedure-Body-Tiefe: jedes
// `end;` (mit Semikolon, gehen wir backwards rein) erhoeht die Tiefe;
// jedes `begin` bei Tiefe > 0 dekrementiert (wir verlassen das Body
// going up). Bei Tiefe = 0:
//   * `begin`        -> Legacy-Init-Match
//   * `initialization`/`finalization` -> moderne Init
// `end.` (mit Punkt) ist Unit-Terminator und wird ignoriert.
function FindLastInitMarker(Lines: TStringList; out Lower: string): Integer;
var
  i, Col : Integer;
  Word   : string;
  L      : string;
  After  : Char;
  Depth  : Integer;
begin
  Result := -1;
  Lower := '';
  Depth := 0;
  for i := Lines.Count - 1 downto 0 do
  begin
    Word := ExtractFirstWord(Lines[i], Col);
    if Word = '' then Continue;
    L := LowerCase(Word);
    if L = 'end' then
    begin
      After := CharAfterFirstWord(Lines[i]);
      if After = '.' then
      begin
        // Unit terminator - ueberspringen
        Continue;
      end;
      // `end;` oder `end` ohne Punkt -> Procedure-Body-Schliesser
      Inc(Depth);
      Continue;
    end;
    if L = 'begin' then
    begin
      if Depth > 0 then
      begin
        Dec(Depth);
        Continue;
      end;
      Result := i;
      Lower := L;
      Exit;
    end;
    if (L = 'initialization') or (L = 'finalization') then
    begin
      if Depth = 0 then
      begin
        Result := i;
        Lower := L;
        Exit;
      end;
    end;
    // Andere Worte: weiter zurueck
  end;
end;

class procedure TLegacyInitializationSectionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  Cached : Boolean;
  Marker : Integer;
  Lower  : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Marker := FindLastInitMarker(Lines, Lower);
    if (Marker >= 0) and (Lower = 'begin') then
      Results.Add(TLeakFinding.New(FileName, '', Marker + 1,
        'Legacy unit-init `begin..end.` - migrate to ' +
        '`initialization..end.` for explicit init/finalization separation.',
        fkLegacyInitializationSection));
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
