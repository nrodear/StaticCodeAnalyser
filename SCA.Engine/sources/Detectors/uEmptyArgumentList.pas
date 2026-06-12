unit uEmptyArgumentList;

// Detektor fuer leere Argument-Listen `()` nach Identifiern.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyArgumentList - die
// Konvention in Delphi/Object-Pascal ist, einen parameterlosen Call
// OHNE Klammern zu schreiben: `MyProc;` statt `MyProc();`. Die leere
// `()`-Form ist C-Sprachstil und in Delphi nirgends erforderlich;
// fuer Funktions-Calls die ein Result haben gilt dasselbe.
//
// Erkennung: lexikalischer Scan analog uGotoStatement. Match auf
//   Identifier ( whitespace )+ )
// also: rechte Klammer direkt (modulo whitespace) nach `(`, und davor
// ein Identifier-Zeichen oder `]`. Strings und Kommentare werden
// uebersprungen.
//
// False-Positive-Schutz:
//   * NICHT melden wenn vor dem `(` ein Komma oder anderes Nicht-Ident-/
//     Nicht-`]`-Zeichen steht - dann ist `()` ein Konstrukt wie ein
//     leeres Tupel/Set/Initialisierungslist (`MyArr := ()`).
//   * Klammer-Inhalt darf nur Whitespace sein, sonst ist es ein echter
//     Aufruf mit Argument.
//
// Schweregrad: lsHint - reines Style.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TEmptyArgumentListDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Liefert die 1-basierte Spalte des `(` einer leeren Argument-Liste
// nach einem Identifier, sonst 0. Setzt die Cursors `i`, `InStr`,
// `InBlockComm`, `InParenStarComm` korrekt fort.
function FindEmptyArgList(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j : Integer;
  InStr   : Boolean;
  pClose  : Integer;
  c, prev : Char;
  AllWs   : Boolean;
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
    // Trefferprueffung: `(` direkt nach Ident/`]`, und nur Whitespace bis `)`.
    if c = '(' then
    begin
      // Linke Seite: vorheriges Nicht-Whitespace-Zeichen muss Ident oder `]` sein.
      if i = 1 then begin Inc(i); Continue; end;
      j := i - 1;
      while (j >= 1) and CharInSet(Line[j], [' ', #9]) do Dec(j);
      if j < 1 then begin Inc(i); Continue; end;
      prev := Line[j];
      if not (IsIdent(prev) or (prev = ']')) then
      begin
        Inc(i); Continue;
      end;
      // Rechte Seite: bis `)` darf nur Whitespace stehen (innerhalb der Zeile).
      AllWs := True;
      j := i + 1;
      while j <= n do
      begin
        if Line[j] = ')' then Break;
        if not CharInSet(Line[j], [' ', #9]) then
        begin
          AllWs := False;
          Break;
        end;
        Inc(j);
      end;
      if AllWs and (j <= n) and (Line[j] = ')') then
      begin
        Result := i;
        Exit;
      end;
    end;
    Inc(i);
  end;
end;

class procedure TEmptyArgumentListDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindEmptyArgList(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Empty argument list `()` at column %d - drop the parens ' +
        '(Delphi convention).', [Col]);
      F.SetKind(fkEmptyArgumentList);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
