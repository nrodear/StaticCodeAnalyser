unit uTrailingCommaArgList;

// Detektor fuer trailing Komma in Argument-Listen: `Foo(A, B,)`.
//
// SonarDelphi-Aequivalent: communitydelphi:TrailingCommaArgumentList.
// Delphi-Compiler akzeptiert das stillschweigend in vielen Releases,
// aber:
//   * Suggeriert dass noch ein Argument folgen sollte (vergessen)
//   * Verwirrt Diff-Tools - die zusaetzliche leere Zeile vor `)` wirkt
//     wie eine entfernte Zeile.
//   * Anders als Python/JS-Conventions wo trailing Comma die letzte
//     Zeile vom Diff entkoppelt: Delphi hat keinen praktischen Vorteil.
//
// Erkennung: lexikalischer Scan mit String-/Kommentar-Awareness. Match
// auf Pattern `,` -> beliebig Whitespace -> `)`. Innerhalb derselben
// Zeile (mehrzeilige Argument-Listen mit trailing-Komma am Zeilenende
// werden NICHT erkannt - das waere ein State-Machine-Aufwand der hier
// nicht lohnt; mehrzeilige Listen sind typischerweise Code-Style, kein
// Bug-Risiko).
//
// Schweregrad: lsHint - reines Style/Convention.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TTrailingCommaArgListDetector = class
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

// Liefert die 1-basierte Spalte des trailing-Kommas (Zeichen `,`) wenn
// die Zeile ein `,` enthaelt, danach nur Whitespace, dann `)`. 0 sonst.
function FindTrailingComma(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j : Integer;
  InStr   : Boolean;
  pClose  : Integer;
  c       : Char;
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
    if c = ',' then
    begin
      // Look-ahead: nur Whitespace bis `)`?
      j := i + 1;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if (j <= n) and (Line[j] = ')') then
      begin
        Result := i;
        Exit;
      end;
    end;
    Inc(i);
  end;
end;

class procedure TTrailingCommaArgListDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindTrailingComma(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Trailing comma in argument list at column %d - drop the comma ' +
        'or add the missing argument.', [Col]);
      F.SetKind(fkTrailingCommaArgList);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
