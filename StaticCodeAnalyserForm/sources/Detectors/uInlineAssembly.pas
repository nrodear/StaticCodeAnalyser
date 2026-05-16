unit uInlineAssembly;

// Detektor fuer `asm ... end` Inline-Assembly-Bloecke.
//
// SonarDelphi-Aequivalent: communitydelphi:InlineAssembly. Inline-ASM
// ist in modernen Delphi-Codebases praktisch immer ein Indiz fuer Code,
// der die folgenden Probleme hat:
//   * Plattform-Lock-In: x86/x64-spezifischer Maschinencode, der bei
//     ARM-Cross-Compile / FPC-Targets gar nicht uebersetzt.
//   * Toolchain-Risiko: Delphi-Optimizer kann ASM-Bloecke nicht inlinen
//     oder reorganisieren, Performance-Vorteil oft illusorisch.
//   * Wartbarkeit: kaum jemand im Team kann ASM live debuggen.
//
// Heutige Use-Cases (CPUID-Detection, MMX/SSE-Intrinsics) sind in der
// RTL bereits abgedeckt - ein neuer ASM-Block in App-Code rechtfertigt
// fast immer einen Refactor zu Pascal + Compiler-Intrinsics.
//
// Erkennung: lexikalischer Scan mit String-/Kommentar-Awareness analog
// uGotoStatement. Match auf `asm` als ganzes Wort - der zugehoerige
// `end`-Marker wird NICHT extra getrackt (eine Meldung pro asm-Block-
// Start ist genug, der Reviewer findet das Ende selbst).
//
// Schweregrad: lsWarning. Kein Bug per se, aber starker Maintainability-
// Schmerz und potenzielles Portabilitaets-Problem.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TInlineAssemblyDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils,
  uFileTextCache;

const
  KW            = 'asm';
  KW_LEN        = 3;
  EMIT_SEVERITY = lsWarning;

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Findet die 1-basierte Spalte des ersten Top-Level `asm`-Keywords in der
// Zeile (ausserhalb String-Literal, ausserhalb {..}/(*..*)/// und mit
// beidseitiger Wortgrenze). 0 wenn keines.
function FindAsm(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n   : Integer;
  InStr  : Boolean;
  pClose : Integer;
  c, nx  : Char;
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
    if CharInSet(c, ['a','A']) and (i + KW_LEN - 1 <= n) and
       SameText(Copy(Line, i, KW_LEN), KW) then
    begin
      // Linke Wortgrenze
      if (i > 1) and IsIdent(Line[i - 1]) then
      begin
        Inc(i); Continue;
      end;
      // Rechte Wortgrenze
      if (i + KW_LEN <= n) then
      begin
        nx := Line[i + KW_LEN];
        if IsIdent(nx) then
        begin
          Inc(i); Continue;
        end;
      end;
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

class procedure TInlineAssemblyDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindAsm(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Inline assembly block at column %d - prefer Pascal + compiler ' +
        'intrinsics for portability / ARM compatibility.', [Col]);
      F.SetKind(fkInlineAssembly);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
