unit uUnitLevelKeywordIndent;

// Detektor fuer Unit-Level-Keywords (unit/interface/implementation/
// initialization/finalization), die NICHT auf Spalte 1 stehen.
//
// SonarDelphi-Aequivalent: communitydelphi:UnitLevelKeywordIndentation.
// Konvention seit Object-Pascal: die strukturellen Section-Keywords
// einer Unit stehen flush-left (Spalte 1). Wenn sie eingerueckt sind,
// erschwert das das visuelle Skimmen der Unit-Gliederung und kann auf
// fehlerhafte Block-Verschachtelung hindeuten.
//
// Erkennung: pro Zeile pruefen, ob das erste Nicht-Whitespace-Token
// eines der Section-Keywords ist UND die Zeile mit Whitespace beginnt.
//
// Beachte: `interface` wird hier ueberprueft NUR wenn es die GANZE Zeile
// ist (nach Trim) - sonst clasht es mit `type IFoo = interface ... end`
// (dort ist `interface` im Typ-Kontext und darf eingerueckt sein).
// Genauso `uses` koennte in Interface- oder Implementation-Section
// auftauchen und sollte typografisch auf Spalte 1 stehen.
//
// Schweregrad: lsHint - reines Style/Konvention.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnitLevelKeywordIndentDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DuplicateBlock, GroupedDeclaration, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

// True wenn Lower einem strukturellen Section-Keyword entspricht, das
// IMMER auf Spalte 1 stehen sollte (auch wenn es im Code nochmal in
// anderem Kontext vorkommt waere das ungewoehnlich).
function IsStrictSectionKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'unit') or (Lower = 'implementation')
         or (Lower = 'initialization') or (Lower = 'finalization');
end;

// True wenn das Token eines ist, das stand-alone-Zeile sein muss
// (interface, uses) - aber nur wenn keine weiteren Tokens auf der
// Zeile folgen.
function IsSoloOnlyKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'interface') or (Lower = 'uses');
end;

// Liefert das erste Wort der Zeile (nach Leading-Whitespace, ohne
// Trailing-Garbage), plus die Spalte, an der es beginnt (1-basiert),
// und ob die ganze Zeile bis auf Whitespace/Semikolon nur dieses Wort
// enthaelt (RestEmpty). Wenn die Zeile leer ist oder mit Kommentar
// startet, gibt FirstWord = '' zurueck.
procedure ExtractFirstWord(const Line: string; out FirstWord: string;
  out StartCol: Integer; out RestEmpty: Boolean);
var
  i, n, wStart : Integer;
  c            : Char;
begin
  FirstWord := '';
  StartCol  := 0;
  RestEmpty := False;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  // Kommentar-Start am Zeilenbeginn -> ignorieren
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  // Wort scannen
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  FirstWord := Copy(Line, wStart, i - wStart);
  // RestEmpty: nur Whitespace + optional `;` bis Zeilenende
  RestEmpty := True;
  while i <= n do
  begin
    c := Line[i];
    if CharInSet(c, [' ', #9, ';']) then Inc(i)
    else begin RestEmpty := False; Break; end;
  end;
end;

class procedure TUnitLevelKeywordIndentDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines     : TStringList;
  i         : Integer;
  Cached    : Boolean;
  Word      : string;
  Lower     : string;
  Col       : Integer;
  RestEmpty : Boolean;
  F         : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    for i := 0 to Lines.Count - 1 do
    begin
      ExtractFirstWord(Lines[i], Word, Col, RestEmpty);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      if Col <= 1 then Continue;  // bereits auf Spalte 1
      if IsStrictSectionKw(Lower) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Unit-level keyword "%s" should start at column 1 ' +
          '(currently at column %d).', [Word, Col]);
        F.SetKind(fkUnitLevelKeywordIndent);
        Results.Add(F);
      end
      else if IsSoloOnlyKw(Lower) and RestEmpty then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'Unit-level keyword "%s" should start at column 1 ' +
          '(currently at column %d).', [Word, Col]);
        F.SetKind(fkUnitLevelKeywordIndent);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
