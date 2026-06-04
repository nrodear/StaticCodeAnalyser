unit uExplicitTObjectInheritance;

// Detektor fuer `class(TObject)`-Deklarationen.
//
// SonarDelphi-Aequivalent: communitydelphi:ExplicitTObjectInheritance.
// In Delphi ist `TFoo = class` semantisch identisch zu `TFoo = class(TObject)`
// - die Wurzelklasse wird implizit verwendet. Das explizite `(TObject)`
// ist Rauschen und versteckt im Diff, wenn man wirklich von TObject
// auf eine andere Basis migriert (statt einfach den Inheritanc-Tail
// hinzuzufuegen).
//
// Erkennung: lexikalisch. Pattern `class` -> optional whitespace -> `(`
// -> optional ws -> `TObject` (Wort) -> optional ws -> `)`. String-
// /Kommentar-Awareness.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TExplicitTObjectInheritanceDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Sucht in der Zeile nach `class(TObject)`-Pattern.
function FindClassTObject(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j : Integer;
  InStr   : Boolean;
  pClose  : Integer;
  c       : Char;
  CCol    : Integer;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    // `class` als Wort
    if CharInSet(c, ['C', 'c']) and (i + 4 <= n) and
       SameText(Copy(Line, i, 5), 'class') then
    begin
      if (i > 1) and IsIdent(Line[i - 1]) then begin Inc(i); Continue; end;
      if (i + 5 <= n) and IsIdent(Line[i + 5]) then begin Inc(i); Continue; end;
      CCol := i;
      j := i + 5;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if (j > n) or (Line[j] <> '(') then begin i := j; Continue; end;
      Inc(j);
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      // `TObject` Wort
      if (j + 6 <= n + 1) and SameText(Copy(Line, j, 7), 'TObject') then
      begin
        if ((j + 7 <= n) and IsIdent(Line[j + 7])) then
        begin i := j; Continue; end;
        Inc(j, 7);
        while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
        if (j <= n) and (Line[j] = ')') then
        begin
          Result := CCol;
          Exit;
        end;
      end;
      i := j;
      Continue;
    end;
    Inc(i);
  end;
end;

class procedure TExplicitTObjectInheritanceDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindClassTObject(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        '`class(TObject)` at column %d - drop the parens (TObject is ' +
        'the implicit base class).', [Col]);
      F.SetKind(fkExplicitTObjectInheritance);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
