unit uDigitGrouping;

// Detektor fuer grosse Ganzzahl-Literale ohne `_`-Tausender-Trennung.
//
// SonarDelphi-Aequivalent: communitydelphi:DigitGrouping. Seit Delphi
// 10.4 koennen Zahlenliterale `_` als optischen Trenner enthalten:
//   1_000_000  statt  1000000
// Das macht Konstanten wie Timeouts (1_800_000 ms = 30 min), Datei-
// groessen (1_048_576 = 1 MiB) oder Money-Cents auf einen Blick lesbar.
//
// Erkennung:
//   * Lexikalischer Scan mit String-/Kommentar-Awareness.
//   * Match auf eine Sequenz von >= MIN_GROUP_LEN aufeinanderfolgenden
//     Ziffern (Default 5), mit linker Wortgrenze (kein Identifier-Teil
//     wie `Var123456`) und ohne `_` in der Sequenz.
//   * Hex (`$DEADBEEF`) und float (`3.14`) werden ausgenommen - andere
//     Konvention.
//
// Schweregrad: lsHint - reines Lesbarkeits-Refactor, kein Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TDigitGroupingDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, RedundantJump, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uFileTextCache;

const
  EMIT_SEVERITY  = lsHint;
  MIN_GROUP_LEN  = 5;  // ab dieser Laenge wird Gruppierung gefordert

function IsIdent(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

// Liefert die 1-basierte Spalte des ersten ungrupierten Zahlenliterals
// mit >= MIN_GROUP_LEN Ziffern, sonst 0. Ueberspringt String-/Kommentar-
// Bereiche und Hex-/Float-Literale.
function FindUngrouped(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, wStart : Integer;
  InStr        : Boolean;
  pClose       : Integer;
  c, prev      : Char;
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
    // Hex: `$...` - skip until non-hex
    if c = '$' then
    begin
      Inc(i);
      while (i <= n) and CharInSet(Line[i],
        ['0'..'9', 'A'..'F', 'a'..'f', '_']) do Inc(i);
      Continue;
    end;
    // Ziffern-Run starten
    if IsDigit(c) then
    begin
      // Linke Wortgrenze: vorheriges Zeichen darf nicht Ident sein
      // (sonst ist es Bestandteil eines Identifier wie `Var123456`).
      if i > 1 then
      begin
        prev := Line[i - 1];
        if IsIdent(prev) then
        begin
          // ueberspringen ganz bis Ende des Identifier-Tokens
          while (i <= n) and IsIdent(Line[i]) do Inc(i);
          Continue;
        end;
      end;
      wStart := i;
      while (i <= n) and (IsDigit(Line[i]) or (Line[i] = '_')) do Inc(i);
      // Falls direkt ein `.` folgt -> Float-Literal, ignorieren
      if (i <= n) and (Line[i] = '.') then
      begin
        // Float weiter ueberspringen
        Inc(i);
        while (i <= n) and IsDigit(Line[i]) do Inc(i);
        Continue;
      end;
      // Falls 'e'/'E' folgt -> wissenschaftliche Notation, ueberspringen
      if (i <= n) and CharInSet(Line[i], ['e','E']) then
      begin
        Inc(i);
        if (i <= n) and CharInSet(Line[i], ['+','-']) then Inc(i);
        while (i <= n) and IsDigit(Line[i]) do Inc(i);
        Continue;
      end;
      // Hat das Literal `_`? Dann ist es gruppiert, ueberspringen.
      if Pos('_', Copy(Line, wStart, i - wStart)) > 0 then Continue;
      // Reine Ziffern-Sequenz - haben wir genug Stellen?
      if (i - wStart) >= MIN_GROUP_LEN then
      begin
        Result := wStart;
        Exit;
      end;
      Continue;
    end;
    Inc(i);
  end;
end;

class procedure TDigitGroupingDetector.AnalyzeUnit(UnitNode: TAstNode;
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
      Col := FindUngrouped(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;
      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('Integer literal at column %d has >=%d digits without `_` ' +
               'grouping - consider readability (e.g. 1_000_000).',
          [Col, MIN_GROUP_LEN]),
        fkDigitGrouping));
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
