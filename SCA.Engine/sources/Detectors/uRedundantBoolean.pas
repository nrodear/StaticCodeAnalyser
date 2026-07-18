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
  var InParenStarComm: Boolean; var InConstSection: Boolean): Integer;

  // Ist W das erste Wort von S (Wortgrenze dahinter)?
  function StartsWithWord(const S, W: string): Boolean;
  var L: Integer;
  begin
    L := Length(W);
    Result := (Copy(S, 1, L) = W) and
              ((Length(S) = L) or not IsIdent(S[L + 1]));
  end;

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
  Trim1 := TrimLeft(Line);
  LineLow := LowerCase(Trim1);
  // const-Section-Tracker (Ist-Messung 2026-07-18, SCA072 100% FP im Sample):
  // untypisierte Konstanten auf FOLGE-Zeilen eines const-Blocks ('X = True;')
  // sind Deklarationen, kein Vergleich. Der bisherige Zeilenanfangs-Check
  // ('const'/'type') sah nur die Kopfzeile. Eine const-Section enthaelt keinen
  // ausfuehrbaren Code -> Skip ist TP-safe-by-construction. Section endet am
  // naechsten Abschnitts-Keyword. State nur ausserhalb von Kommentaren pflegen.
  if not (InBlockComm or InParenStarComm) then
  begin
    if StartsWithWord(LineLow, 'const') or StartsWithWord(LineLow, 'resourcestring') then
      InConstSection := True
    else if StartsWithWord(LineLow, 'type') or StartsWithWord(LineLow, 'var')
         or StartsWithWord(LineLow, 'threadvar') or StartsWithWord(LineLow, 'label')
         or StartsWithWord(LineLow, 'procedure') or StartsWithWord(LineLow, 'function')
         or StartsWithWord(LineLow, 'constructor') or StartsWithWord(LineLow, 'destructor')
         or StartsWithWord(LineLow, 'operator') or StartsWithWord(LineLow, 'class')
         or StartsWithWord(LineLow, 'property') or StartsWithWord(LineLow, 'begin')
         or StartsWithWord(LineLow, 'end') or StartsWithWord(LineLow, 'implementation')
         or StartsWithWord(LineLow, 'interface') or StartsWithWord(LineLow, 'initialization')
         or StartsWithWord(LineLow, 'finalization') or StartsWithWord(LineLow, 'uses')
         or StartsWithWord(LineLow, 'exports') or StartsWithWord(LineLow, 'public')
         or StartsWithWord(LineLow, 'private') or StartsWithWord(LineLow, 'protected')
         or StartsWithWord(LineLow, 'published') or StartsWithWord(LineLow, 'strict') then
      InConstSection := False;
  end;
  // Deklarations-Zeilen ausschliessen.
  if (Copy(LineLow, 1, 5) = 'const')
     or (Copy(LineLow, 1, 4) = 'type')
     or InConstSection then Exit;
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
    // Colon-Rule (Ist-Messung 2026-07-18, dominante SCA072-FP-Klasse 14/15):
    // steht VOR dem LHS-Identifikator ein nacktes ':', ist das Muster
    // 'name: Typ = True' - ein DEFAULT-PARAMETER ('X: Boolean = True'), eine
    // typisierte Konstante oder ein initialisiertes Global. Das '=' ist dort
    // Initializer, kein Vergleich. TP-safe-by-construction: vor dem LHS eines
    // ECHTEN Vergleichs steht nie ein nacktes ':' - bei 'r := x = True' ist
    // das Zeichen direkt vor dem LHS-Ident das '=' aus ':=', nicht ':'.
    if IsIdent(prev) then
    begin
      var bk := j;
      while (bk >= 1) and IsIdent(Line[bk]) do Dec(bk);   // LHS-Ident rueckwaerts
      while (bk >= 1) and CharInSet(Line[bk], [' ', #9]) do Dec(bk);
      if (bk >= 1) and (Line[bk] = ':') then
      begin
        Inc(i, OpLen); Continue;                          // Deklarations-Initializer
      end;
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
  InBlk, InParen, InConst : Boolean;
  F      : TLeakFinding;
  Cached : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InBlk   := False;
    InParen := False;
    InConst := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindRedundantBool(Lines[i], InBlk, InParen, InConst);
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
