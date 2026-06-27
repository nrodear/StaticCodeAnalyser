unit uAvoidOut;

// Detektor fuer `out`-Parameter in Methoden-Signaturen.
//
// SonarDelphi-Aequivalent: communitydelphi:AvoidOut. `out`-Parameter
// haben in Delphi unterschiedliche Semantik je nach Typ:
//   * Managed-Typen (string, Interface, dynamic array): werden beim
//     Methoden-Entry freigegeben - der Aufrufer-Wert geht verloren bevor
//     die Methode anlauft.
//   * Records / einfache Typen: werden nicht initialisiert; auf den
//     Eingangswert zuzugreifen ist UB.
// Beides ist selten gewuenscht. `var` ist die robustere Wahl, sofern
// kein COM-Interop noetig ist.
//
// Erkennung: lexikalischer Scan. Match auf Wort `out` (case-insensitive)
// innerhalb von Klammern `(...)` einer `procedure`/`function`/`constructor`/
// `destructor`-Deklaration. Vereinfachung: matche `out ` (Wort + Whitespace
// + Ident) ohne Klammer-Kontext zu verfolgen - false-positives auf
// `out` als Identifier sind sehr selten.
//
// Schweregrad: lsHint - kein Bug per se, aber API-Design-Hint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TAvoidOutDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
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

// Liefert Spalte des `out`-Keywords als Parameter-Direktive (innerhalb
// `(...)`), sonst 0.
function FindOutParam(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j   : Integer;
  InStr     : Boolean;
  pClose    : Integer;
  c         : Char;
  ParenDep  : Integer;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  ParenDep := 0;
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
    if c = '(' then begin Inc(ParenDep); Inc(i); Continue; end;
    if c = ')' then begin Dec(ParenDep); Inc(i); Continue; end;
    // Innerhalb `(...)` und Wort `out` matchen
    if (ParenDep > 0) and CharInSet(c, ['O', 'o']) and (i + 2 <= n) and
       SameText(Copy(Line, i, 3), 'out') then
    begin
      if (i > 1) and IsIdent(Line[i - 1]) then begin Inc(i); Continue; end;
      if (i + 3 <= n) and IsIdent(Line[i + 3]) then begin Inc(i); Continue; end;
      // Naechstes Nicht-Whitespace muss Ident-Start sein (Parametername)
      j := i + 3;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if (j <= n) and CharInSet(Line[j], ['A'..'Z','a'..'z','_']) then
      begin
        Result := i;
        Exit;
      end;
      Inc(i);
      Continue;
    end;
    Inc(i);
  end;
end;

class procedure TAvoidOutDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindOutParam(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('`out` parameter at column %d - prefer `var` (out clears ' +
               'managed types on entry, leaves records uninitialized).',
          [Col]),
        fkAvoidOut));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
