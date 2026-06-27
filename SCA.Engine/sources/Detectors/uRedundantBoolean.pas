unit uRedundantBoolean;

// Detektor fuer redundante boolesche Vergleiche `= True` / `<> False` etc.
//
// SonarDelphi-Aequivalent: communitydelphi:RedundantBoolean. Wenn `X`
// bereits ein Boolean ist, ist `X = True` semantisch identisch zu `X`
// (und `X <> False` ebenfalls). Das ueberfluessige `= True` haengt aus
// historischen Gruenden in Code drin und ist:
//   * Laenger zu lesen
//   * Mehr Quellen fuer Tippfehler (`=` vs `:=`)
//   * In speziellen Faellen ein Bug-Risiko (`If X = True` schlaegt fehl
//     wenn `X` zwar truthy, aber nicht == 1 ist, z.B. WinAPI-BOOL)
//
// Erkennung: lexikalischer Scan mit String-/Kommentar-Awareness. Match
// auf Pattern `=` oder `<>` (Operator) -> Whitespace -> `True`/`False`
// (case-insensitive, ganzes Wort).
//
// Ausgeschlossen: Zeilen, die mit `const`/`type` beginnen - dort ist
// `= True` Deklaration und kein Vergleich. Heuristik bewusst grob.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TRedundantBooleanDetector = class
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

function ScanIdent(const Line: string; var i: Integer): string;
var
  wStart, n : Integer;
begin
  n := Length(Line);
  wStart := i;
  while (i <= n) and IsIdent(Line[i]) do Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

// Liefert Spalte des `=` / `<>` wenn ein redundanter Boolean-Vergleich
// auf der Zeile gefunden wurde, sonst 0.
function FindRedundantBool(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j : Integer;
  InStr   : Boolean;
  pClose  : Integer;
  c, prev : Char;
  OpLen   : Integer;
  RhsWord : string;
  RhsLow  : string;
  LineLow : string;
  Trim1   : string;
begin
  Result := 0;
  // Deklarations-Zeilen ausschliessen.
  Trim1 := TrimLeft(Line);
  LineLow := LowerCase(Trim1);
  if (Copy(LineLow, 1, 5) = 'const')
     or (Copy(LineLow, 1, 4) = 'type') then Exit;
  InStr := False;
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
    OpLen := 0;
    if c = '=' then
    begin
      // `:=`-Assign ausschliessen, `>=`/`<=` ebenfalls
      if (i > 1) and CharInSet(Line[i - 1], [':', '<', '>']) then
      begin
        Inc(i); Continue;
      end;
      OpLen := 1;
    end
    else if (c = '<') and (i < n) and (Line[i + 1] = '>') then
    begin
      OpLen := 2;
    end;
    if OpLen = 0 then begin Inc(i); Continue; end;
    // Linker Operand: vorheriges Nicht-Whitespace muss ident oder `)`/`]`
    j := i - 1;
    while (j >= 1) and CharInSet(Line[j], [' ', #9]) do Dec(j);
    if j < 1 then begin Inc(i, OpLen); Continue; end;
    prev := Line[j];
    if not (IsIdent(prev) or (prev = ')') or (prev = ']')) then
    begin
      Inc(i, OpLen); Continue;
    end;
    // Rechte Seite: skip whitespace, dann ein Wort scannen
    j := i + OpLen;
    while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
    if (j > n) or not CharInSet(Line[j], ['T','t','F','f']) then
    begin
      Inc(i, OpLen); Continue;
    end;
    RhsWord := ScanIdent(Line, j);
    RhsLow := LowerCase(RhsWord);
    if (RhsLow = 'true') or (RhsLow = 'false') then
    begin
      Result := i;
      Exit;
    end;
    Inc(i, OpLen);
  end;
end;

class procedure TRedundantBooleanDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col : Integer;
  InBlk, InParen : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindRedundantBool(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar := Format(
        'Redundant boolean comparison at column %d - drop `= True` / ' +
        '`<> False` (the expression itself is the condition).', [Col]);
      F.SetKind(fkRedundantBoolean);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
