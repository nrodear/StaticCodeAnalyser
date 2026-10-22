unit uRdxAttrGapFix;

// reDelphix - Editorhilfe SCA183 AttributeMisalignment: die Leerzeile(n)
// zwischen einer Attributzeile und dem Element, das sie annotiert,
// loeschen. OHNE ToolsAPI und ohne Parser, nur auf der Code-Sicht
// (TRdxCodeMap). Der Compiler haengt das Attribut ohnehin an das naechste
// Element - die Leerzeilen sind reiner Text, die Bedeutung bleibt.
//
// Was der Detektor meldet (uAttributeMisalignment): eine Zeile, die mit
// '[' und einem Bezeichner beginnt, nichts hinter dem letzten ']' hat,
// und deren NAECHSTE Zeile (nach Trim) leer ist, mit einer Member-artigen
// Zeile dahinter (IsLikelyAttributePosition). LineNumber ist die Attributzeile, die
// Meldung nennt 'Attribute [Name] with blank line ...'. Der Kopf des
// Detektors verspricht 'Member-Deklaration', der Code prueft das nicht
// (Korpus: 2 von 5 Funden waren [assembly: ..]-Attribute) - das prueft
// dieser Planer selbst.
//
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche.
// Geloescht werden NUR Zeilen aus Leerzeichen und Tabulatoren, ab der
// Zeile hinter dem Attribut bis vor die erste Zeile mit Inhalt. Keine
// Hilfe, wenn
//   * die Zeile keine Attributzeile mit dem Namen aus der Meldung ist
//     (verschoben; in einem Kommentar oder mehrzeiligen String),
//   * das Attribut ein Ziel hat ([assembly: ..], [Result: ..]) oder ueber
//     mehrere Zeilen laeuft oder hinter dem ']' Text/Kommentar steht,
//   * (eine Leerzeile in einem Block-Kommentar kann nicht vorkommen: die
//     Attributzeile endet auf ']' als Code, also ist danach nichts offen),
//   * die erste Zeile mit Inhalt ein Kommentar, eine Direktive oder keine
//     Deklaration ist, die ein Attribut tragen kann (Routine, property,
//     Feld, Typ, weiteres Attribut) oder
//   * vor dem Attribut kein Deklarationsende steht (';', ein Abschnitts-
//     wort, 'class'/'record'/'interface'/'object', ein weiteres Attribut),
//     oder eine Direktive dazwischen liegt.
// Nicht enthalten: ein Attribut hinter 'class(TBase)' ohne Abschnittswort
// (Kopf endet auf ')') - dort bietet die Hilfe nichts an.

interface

uses
  uRdxBufferMath,      // TRdxEdit
  uRdxCodeMap;         // TRdxCodeMap

type
  TRdxAttrGapFix = class
  public
    // SCA183: ALine ist die Attributzeile aus dem Fund. Die Ersetzung
    // loescht die Leerzeilen dahinter samt Zeilenende (Bereich ueber
    // mehrere Zeilen, NewText = ''); sonst der Grund.
    class function BlankGap(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;       // TRefactorSpan.Make

const
  SPAN_183 = 'sca183';
  KEY_ATTR = 'Attribute [';
  R_ATTR_MOVED = 'keine Attributzeile an der gemeldeten Stelle - Zeile '
    + 'verschoben? Datei neu pruefen';
  R_ATTR_TARGET = 'Attribut mit Ziel (assembly:, Result:) - es haengt an '
    + 'keinem Element';
  R_ATTR_MULTI = 'Attribut ueber mehrere Zeilen - keine Hilfe';
  R_ATTR_TAIL = 'hinter dem Attribut steht noch Text oder ein Kommentar';
  R_NO_GAP = 'keine Leerzeile hinter dem Attribut - Zeile verschoben? Datei '
    + 'neu pruefen';
  R_NO_MEMBER = 'hinter der Leerzeile steht kein Code mehr';
  R_NEXT_NOT_CODE = 'hinter der Leerzeile folgt ein Kommentar oder eine '
    + 'Direktive - die Zeilen bleiben';
  R_NOT_MEMBER = 'hinter der Leerzeile steht keine Deklaration, die das '
    + 'Attribut tragen kann';
  R_NO_ANCHOR = 'vor dem Attribut steht kein Deklarationsende - kein '
    + 'sicherer Attributkontext';
  R_DIRECTIVE = 'zwischen Attribut und Element liegt eine Compiler-Direktive';
  // Davor darf eine Attributzeile beginnen: Ende der Deklaration davor,
  // Abschnittswort, Beginn eines Typs (class, record, ...), anderes Attribut.
  ANCHOR_WORDS: array[0..13] of string = (';', ']', 'public', 'private',
    'protected', 'published', 'automated', 'class', 'record', 'interface',
    'object', 'type', 'implementation', 'dispinterface');
  // Elemente, die ein Attribut tragen (Kopf der Routine, property).
  HEAD_WORDS: array[0..6] of string = ('procedure', 'function', 'constructor',
    'destructor', 'property', 'class', 'operator');
  // Hinter 'Name =' beginnt ein Typ.
  TYPE_WORDS: array[0..5] of string = ('class', 'record', 'interface',
    'packed', 'object', 'dispinterface');
  // Diese Woerter beginnen nie ein Feld oder einen Typ.
  NOT_NAMES: array[0..10] of string = ('end', 'case', 'else', 'begin', 'var',
    'const', 'type', 'strict', 'uses', 'initialization', 'finalization');

// Der Name aus 'Attribute [Name] with blank line ...'; '' ohne.
function AttrNameOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(KEY_ATTR, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_ATTR));
  Q := P;
  while (Q <= Length(AMessage)) and (AMessage[Q] <> ']') do
    Inc(Q);
  if Q <= Length(AMessage) then
    Result := Copy(AMessage, P, Q - P);
end;

// Nur Leerzeichen und Tabulatoren (oder nichts).
function IsBlankLine(const S: string): Boolean;
begin
  Result := SkipBlanks(S, 1) > Length(S);
end;

// Die Klammerbilanz ('[' und '(' gegen ']' und ')') der Code-Zeichen von
// ALine zwischen AFrom und ATo; > 0 heisst, das Attribut laeuft weiter.
function OpenBrackets(AMap: TRdxCodeMap; ALine, AFrom, ATo: Integer): Integer;
var
  L : string;
  j : Integer;
begin
  Result := 0;
  L := AMap.Raw(ALine);
  for j := AFrom to ATo do
    if AMap.IsCode(ALine, j) then
      case L[j] of
        '[', '(': Inc(Result);
        ']', ')': Dec(Result);
      end;
end;

// Ist ALine eine einzeilige Attributzeile (Code-Sicht) mit dem Namen aus
// der Meldung, ohne Ziel und ohne Text hinter dem letzten ']'? '' oder der
// Grund; AFirstCol: Spalte des '['.
function AttrLineReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string; out AFirstCol: Integer): string;
var
  L             : string;
  P, Q, j, Last : Integer;
  Depth, Paren  : Integer;
  Closed        : Boolean;
  C             : Char;
begin
  Result := '';
  L := AMap.Raw(ALine);
  AFirstCol := SkipBlanks(L, 1);
  if AMap.StartsInside(ALine) or (AFirstCol > Length(L))
     or (L[AFirstCol] <> '[') or not AMap.IsCode(ALine, AFirstCol) then
    Exit(R_ATTR_MOVED);
  P := SkipBlanks(L, AFirstCol + 1);
  if (P > Length(L)) or not IsIdentStart(L[P]) or not AMap.IsCode(ALine, P) then
    Exit(R_ATTR_MOVED);
  Q := P;
  while (Q <= Length(L)) and IsIdentChar(L[Q]) do
    Inc(Q);
  if (AName = '') or not SameText(AName, Copy(L, P, Q - P)) then
    Exit(R_ATTR_MOVED);
  // Hinter dem letzten Zeichen der Zeile muss der Schliesser eines
  // Attributs stehen, als Code - kein Kommentar, kein Text.
  Last := Length(L);
  while (Last >= 1) and IsBlank(L[Last]) do
    Dec(Last);
  if (L[Last] <> ']') or not AMap.IsCode(ALine, Last) then
  begin
    // '[Foo(1,': das Attribut laeuft auf der naechsten Zeile weiter.
    if OpenBrackets(AMap, ALine, AFirstCol, Last) > 0 then
      Exit(R_ATTR_MULTI);
    Exit(R_ATTR_TAIL);
  end;
  Depth := 0;
  Paren := 0;
  Closed := False;
  for j := AFirstCol to Last do
  begin
    if not AMap.IsCode(ALine, j) then Continue;
    C := L[j];
    if IsBlank(C) then Continue;
    // Nach dem Schliesser darf nur noch ein weiteres Attribut folgen.
    if Closed and (C <> '[') then Exit(R_ATTR_TAIL);
    if C = '[' then
    begin
      Inc(Depth);
      Closed := False;
    end
    else if C = ']' then
    begin
      Dec(Depth);
      if Depth < 0 then Exit(R_ATTR_MULTI);
      Closed := Depth = 0;
    end
    else if C = '(' then
      Inc(Paren)
    else if C = ')' then
      Dec(Paren)
    else if (C = ':') and (Depth = 1) and (Paren = 0) then
      Exit(R_ATTR_TARGET);
  end;
  if (Depth <> 0) or not Closed then
    Result := R_ATTR_MULTI;
end;

// Kann das Token T (erstes Code-Token der Zeile hinter der Leerzeile) ein
// Attribut tragen? Weiteres Attribut, Routine, property, Feld ('Name:' oder
// 'A, B:'), Typ ('Name = class').
function CarriesAttribute(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  A, B : TRdxToken;
begin
  Result := False;
  if T.Low = '[' then Exit(True);
  if not T.IsWord then Exit;
  if InList(T.Low, HEAD_WORDS) then Exit(True);
  if InList(T.Low, NOT_NAMES) then Exit;
  A := After(AMap, T);
  if (A.Low = ':') or (A.Low = ',') then Exit(True);
  if A.Low = '=' then
  begin
    B := After(AMap, A);
    Result := InList(B.Low, TYPE_WORDS);
  end;
end;

{ ---- SCA183 ---- }

class function TRdxAttrGapFix.BlankGap(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  First, N, Start, Col : Integer;
  Prev, Head           : TRdxToken;
  L                    : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := AttrLineReason(AMap, ALine, AttrNameOf(AMessage), First);
  if AReason <> '' then Exit;
  // Die Leerzeilen: ab ALine + 1 bis vor die erste Zeile mit Inhalt.
  N := ALine + 1;
  if (N > AMap.LineCount) or not IsBlankLine(AMap.Raw(N)) then
  begin
    AReason := R_NO_GAP;
    Exit;
  end;
  // Keine Leerzeile beginnt in einem Kommentar oder String: die
  // Attributzeile endet auf ']' als Code (AttrLineReason), eine Leerzeile
  // oeffnet nichts.
  while (N <= AMap.LineCount) and IsBlankLine(AMap.Raw(N)) do
    Inc(N);
  if N > AMap.LineCount then
  begin
    AReason := R_NO_MEMBER;
    Exit;
  end;
  // Die Zeile mit Inhalt: Code, kein Kommentar, eine tragende Deklaration.
  Start := SkipBlanks(AMap.Raw(N), 1);
  if AMap.StartsInside(N) or not AMap.IsCode(N, Start) then
  begin
    AReason := R_NEXT_NOT_CODE;
    Exit;
  end;
  Head := TokenAt(AMap, N, Start);
  if not CarriesAttribute(AMap, Head) then
  begin
    AReason := R_NOT_MEMBER;
    Exit;
  end;
  // Das Token vor dem Attribut: eine Deklaration ist zu Ende oder beginnt.
  Prev := PrevToken(AMap, ALine, First);
  if (Prev.Low = '') or not InList(Prev.Low, ANCHOR_WORDS) then
  begin
    AReason := R_NO_ANCHOR;
    Exit;
  end;
  if DirectiveInLines(AMap, Prev.Line, N) then
  begin
    AReason := R_DIRECTIVE;
    Exit;
  end;
  // Ein Bereich beginnt auf einem Zeichen (SpanFits: nie auf einer leeren
  // Zeile, siehe LinesCut in uRdxCleanupFixes): er beginnt AUF dem letzten
  // Zeichen der Attributzeile, das neu geschrieben wird, und endet hinter
  // der letzten Leerzeile, ohne deren Zeilenende - das bleibt und trennt
  // die Attributzeile von der Zeile mit Inhalt.
  L := AMap.Raw(ALine);
  Col := Length(L);
  AEdit.Span := TRefactorSpan.Make(SPAN_183, ALine, Col, N - 1,
    Length(AMap.Raw(N - 1)) + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := Copy(L, Col, MaxInt);
  Result := True;
end;

end.
