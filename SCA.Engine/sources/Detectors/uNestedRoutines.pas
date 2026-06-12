unit uNestedRoutines;

// Detektor fuer geschachtelte Routinen (nested procedures/functions
// innerhalb der lokalen Decl-Section einer anderen Methode).
//
// SonarDelphi-Aequivalent: communitydelphi:NestedRoutines /
// AvoidNestedRoutines. Lokale geschachtelte Routinen sind in Delphi
// syntaktisch erlaubt, machen aber Refactorings schwierig (nicht
// testbar in Isolation, schwer wiederverwendbar) und blaehen Methoden
// auf.
//
// Erkennung: NICHT AST-basiert. Der aktuelle Parser entfaltet nested
// Routinen nicht korrekt (`ParseMethodImpl` faellt beim Antreffen eines
// inneren `procedure` in die "Headless-Method"-Branch und loescht den
// Outer-Knoten). Deshalb verwenden wir einen lexikalischen Scan ueber
// die kommentbereinigte Source:
//   1. Sektion `implementation` finden - vorher gibt es nur Class-
//      Method-Deklarationen, keine Bodies, also auch keine Nestings.
//   2. Within implementation: simple State-Maschine
//        InLocalDecl=False
//        wenn Wort = procedure/function/constructor/destructor:
//          wenn InLocalDecl -> Fund
//          InLocalDecl := True
//        wenn Wort = begin -> InLocalDecl := False
//        wenn Wort = end   -> InLocalDecl := False
//   Limitation: Records/Cases mit `end;` zwischen Routine-Header und
//   ihrem `begin` koennen den State faelschlich resetten - akzeptabel
//   weil in der Praxis sehr selten.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TNestedRoutinesDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, MultipleExit, NestedRoutine, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
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

function LineContainsWord(const Line, Word: string): Boolean;
var
  Lower : string;
  p     : Integer;
  function IsIdentChar(C: Char): Boolean; inline;
  begin
    Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
  end;
begin
  Result := False;
  Lower := LowerCase(Line);
  p := Pos(Word, Lower);
  while p > 0 do
  begin
    if ((p = 1) or not IsIdentChar(Lower[p - 1])) and
       ((p + Length(Word) > Length(Lower)) or not IsIdentChar(Lower[p + Length(Word)])) then
      Exit(True);
    p := PosEx(Word, Lower, p + 1);
  end;
end;

class procedure TNestedRoutinesDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i, Col   : Integer;
  Word, L  : string;
  InImpl   : Boolean;
  InLocal  : Boolean;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InImpl  := False;
    InLocal := False;
    for i := 0 to Lines.Count - 1 do
    begin
      // Implementation-Marker erkennen (auch wenn er nicht am Zeilen-
      // anfang steht, z.B. `unit t; implementation`).
      if not InImpl then
        if LineContainsWord(Lines[i], 'implementation') then
          InImpl := True;
      if not InImpl then Continue;
      Word := ExtractFirstWord(Lines[i], Col);
      if Word = '' then Continue;
      L := LowerCase(Word);
      if (L = 'procedure') or (L = 'function') or
         (L = 'constructor') or (L = 'destructor') then
      begin
        if InLocal then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(i + 1);
          F.MissingVar := Format(
            'Nested routine declared at column %d - extract to ' +
            'unit-level to enable testing and reuse.', [Col]);
          F.SetKind(fkNestedRoutine);
          Results.Add(F);
        end;
        InLocal := True;
      end
      else if L = 'begin' then
        InLocal := False
      else if L = 'end' then
        InLocal := False;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
