unit uRdxAssertSideEffectFix;

// reDelphix - Editorhilfe SCA169 AssertWithSideEffect, OHNE ToolsAPI und
// ohne Parser: 'Assert(C, M);' wird zu
//
//   if not (C) then Assert(False, M);
//
// Ohne Meldung ('Assert(C);') wird die Bedingung zur Meldung wie bei SCA074
// (TRdxSimpleFixes.AssertMessage): 'if not (C) then Assert(False, ''C'');'.
// Ein 'Assert(False)' ohne Meldung meldete SCA074 sofort wieder, und dessen
// Hilfe machte daraus 'Assert(False, ''False'')'.
//
// DER FUND: uAssertWithSideEffect meldet auf der Zeile des nkCall
// 'Assert(..)' (T.Line in uParser2, das erste Token der Anweisung), eine
// feste Meldung ohne Spalte. Gemeldet wird, wenn das Argument einen Aufruf
// bzw. einen blossen Namen mit einem Verb-Praefix (Init, Update, Open ...)
// traegt. Den Qualifizierer schneidet der Detektor ab - 'Obj.Assert(..)'
// meldet er auch; das bekommt keine Hilfe.
//
// VERHALTEN (Kennzeichnung E2): ohne Assertions ($C-, ASSERTIONS OFF - der
// uebliche Release-Bau) uebersetzt Delphi den Assert-Aufruf samt Argument
// nicht; die Nebenwirkung des Aufrufs fiel dort weg. Danach steht die
// Bedingung ausserhalb von Assert und laeuft IMMER - genau das will die
// Meldung ('Move the call outside Assert'). Mit Assertions verhaelt sich die
// neue Form wie die alte: die Bedingung laeuft einmal, ist sie False, loest
// Assert(False, ..) EAssertionFailed aus; Datei und Zeile der Meldung bleiben
// (die Form bleibt auf der Zeile). Ohne Assertions entfaellt nur die
// Pruefung.
// Die Form traegt keine neue Variable ('var Ok := ..' wie im Katalog) - so
// gilt sie auch fuer FPC und Delphi vor 10.3, und kein Name ist zu waehlen.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - kein bzw. mehr als ein 'Assert(' im Code der Zeile (Zeile verschoben,
//     mehrdeutig),
//   - die Anweisung steht nicht allein auf ihrer Zeile (Code oder Kommentar
//     davor, Code oder Direktive dahinter), schliesst nicht auf der Zeile,
//     traegt einen Kommentar, ist ein case-Zweig bzw. markiert (':'),
//   - hinter der Anweisung folgt 'else' (dangling else: das neue if naehme
//     das else des aeusseren if an sich - Vorgabe der Recherche-Tabelle),
//   - nicht genau ein oder zwei Argumente, anonyme Methode oder ein '<'
//     direkt hinter einem Namen (Typargumente) im Argument, eine Bedingung
//     ueber 255 Zeichen ohne Meldung (das Literal ginge nicht, E2056),
//   - Assert ist nicht System.Assert: fremder Qualifizierer, eine eigene
//     Routine Assert in der Datei, ein with in der Routine davor (Assert
//     koennte ein Member des with-Ausdrucks sein).
//
// GRENZE: ist die Bedingung ein Variant (eine Funktion mit Variant-
// Ergebnis), waere 'not' bitweise - 'Assert(V)' mit V = 1 haelt, 'if not
// (V)' loest aus. Die Typen der Aufrufe kennt hier niemand; der Detektor
// meldet nur Aufrufe mit Verb-Praefix, deren Ergebnis fast immer Boolean
// ist (Integrationsnotiz).
//
// OHNE ToolsAPI und ohne den Laeufer: die Unit bindet nur Code-Sicht,
// Puffer-Rechnung, uRefactorInfo und uRdxText (Hausregel in uRdxFixTable,
// FPC-Pruefstand). Den Adapter fuer FIX_ROWS (MapFix) traegt uRdxFixTable.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_ASSERTSE_MOVED = 'no "Assert(" on the reported line';
  R_ASSERTSE_MANY = 'the line has more than one "Assert("';
  R_ASSERTSE_NOT_ALONE = 'the Assert call does not stand alone on its line';
  R_ASSERTSE_FOREIGN = '"%s.Assert" is not System.Assert';
  R_ASSERTSE_LABEL = 'the Assert call follows a case label or a goto label';
  R_ASSERTSE_ONE_LINE = 'Assert(..) does not close on its line';
  R_ASSERTSE_DANGLING = 'an "else" follows the Assert call - the new if '
    + 'would take it over';
  R_ASSERTSE_FORM = 'not of the form "Assert(Cond);" or "Assert(Cond, Msg);"';
  R_ASSERTSE_TAIL = 'code or a compiler directive follows the statement on '
    + 'its line';
  R_ASSERTSE_COMMENT = 'comment or compiler directive inside the statement';
  R_ASSERTSE_ARGS = 'Assert has %d arguments here, not one or two';
  R_ASSERTSE_GENERIC = '"<" right after a name in the arguments (type '
    + 'arguments?) - their commas cannot be told apart safely';
  R_ASSERTSE_ANON = 'anonymous method in the arguments';
  R_ASSERTSE_LONG = 'the condition has more than 255 characters - it cannot '
    + 'become the message literal';
  R_ASSERTSE_OWN = 'the file declares its own routine Assert';
  R_ASSERTSE_WITH = 'with statement in the routine - Assert could be a '
    + 'member of the with expression';

type
  TRdxAssertSideEffectFix = class
  public
    // SCA169: 'Assert(C[, M]);' allein auf ALine ->
    // 'if not (C) then Assert(False, M);' (ohne M die Bedingung als
    // Literal). Form TRdxMapPlanner (uRdxFixRunner); AMessage braucht die
    // Hilfe nicht (feste Meldung ohne Spalte).
    class function AssertOutside(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_169 = 'sca169';
  KW_ASSERT = 'assert';
  // Der einzige erlaubte Qualifizierer.
  QUALIFIER_SYSTEM = 'system.';
  // Laengstes String-Literal (E2056).
  MAX_LITERAL = 255;
  // Davor beginnt die Anweisung: Ende einer Anweisung, Anfang einer
  // Anweisungsliste oder ein Zweig (then/else/do - ein else dahinter
  // sperrt ReadEnd).
  STMT_PREV: array[0..10] of string = (';', 'begin', 'try', 'finally',
    'except', 'repeat', 'initialization', 'finalization', 'then', 'else',
    'do');
  // Dahinter endet eine Anweisung ohne ';': uRdxCodeMap.LIST_ENDS (bis zur
  // Hygiene-Welle H1 hier als STMT_END_WORDS kopiert). Die Suche nach
  // einem with davor endet an uRdxCodeMap.UNIT_BOUNDS.
  // Damit beginnt eine anonyme Methode (in einem Argument).
  ANON_WORDS: array[0..2] of string = ('function', 'procedure', 'begin');

type
  // Die Token einer Fundstelle.
  TAssertSite = record
    Start  : TRdxToken;   // erstes Token der Anweisung
    Open   : TRdxToken;   // '(' hinter Assert
    Close  : TRdxToken;   // ')' dazu
    Last   : TRdxToken;   // ';' bzw. ')' ohne ';'
    Semi   : string;      // ';' oder ''
    Parts  : TArray<string>;   // Bedingung[, Meldung] (getrimmt)
  end;

// Wie viele 'Assert(' stehen im Code von ALine?
function AssertsOnLine(AMap: TRdxCodeMap; ALine: Integer): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = KW_ASSERT) and (After(AMap, T).Low = '(') then
      Inc(Result);
    T := After(AMap, T);
  end;
end;

// Der Anfang der Anweisung auf ALine: allein auf der Zeile, 'Assert(' bzw.
// 'System.Assert(', davor das Ende einer Anweisung, der Anfang einer
// Anweisungsliste oder ein Zweig. AOpen ist die '(' hinter Assert. '' oder
// der Grund.
function ReadStart(AMap: TRdxCodeMap; ALine: Integer;
  out AStart, AOpen: TRdxToken): string;
var
  T, P : TRdxToken;
  Q    : string;
  n    : Integer;
begin
  AStart := Default(TRdxToken);
  AOpen := Default(TRdxToken);
  n := AssertsOnLine(AMap, ALine);
  if n = 0 then
    Exit(MsgMovedSuffix(_(R_ASSERTSE_MOVED)));
  if n > 1 then
    Exit(_(R_ASSERTSE_MANY));
  if AMap.StartsInside(ALine) then
    Exit(MsgLineStartsInCommentOrString);
  AStart := NextToken(AMap, ALine, 1);
  if not FirstOnLine(AMap, AStart) then
    Exit(_(R_ASSERTSE_NOT_ALONE));
  T := AStart;
  Q := '';
  while T.IsWord and (T.Low <> KW_ASSERT) and (After(AMap, T).Low = '.') do
  begin
    Q := Q + T.Low + '.';
    T := After(AMap, After(AMap, T));
  end;
  if (T.Low <> KW_ASSERT) or (T.Line <> ALine)
     or (After(AMap, T).Low <> '(') then
    Exit(_(R_ASSERTSE_NOT_ALONE));
  if (Q <> '') and (Q <> QUALIFIER_SYSTEM) then
    Exit(_(R_ASSERTSE_FOREIGN, [Trim(Copy(AMap.Raw(ALine), AStart.Col,
      T.Col - 1 - AStart.Col))]));
  P := Before(AMap, AStart);
  if P.Low = ':' then
    Exit(_(R_ASSERTSE_LABEL));
  if not InList(P.Low, STMT_PREV) then
    Exit(MsgUnclearStatementOwner(TokText(AMap, P)));
  AOpen := After(AMap, T);
  Result := '';
end;

// Das Ende der Anweisung hinter AClose: ';' auf der Zeile, oder kein ';'
// vor end/until/except/finally; ein else dahinter sperrt (dangling else);
// dahinter auf der Zeile nur Leerraum oder Kommentar. '' oder der Grund.
function ReadEnd(AMap: TRdxCodeMap; const AClose: TRdxToken;
  out ALast: TRdxToken; out ASemi: string): string;
var
  N : TRdxToken;
begin
  ALast := AClose;
  ASemi := '';
  N := After(AMap, AClose);
  if N.Low = ';' then
  begin
    if N.Line <> AClose.Line then
      Exit(_(R_ASSERTSE_FORM));
    ALast := N;
    ASemi := ';';
  end
  else if N.Low = 'else' then
    Exit(_(R_ASSERTSE_DANGLING))
  else if not InList(N.Low, LIST_ENDS) then
    Exit(_(R_ASSERTSE_FORM));
  if not TailIsQuiet(AMap, ALast.Line, ALast.EndCol - 1) then
    Exit(_(R_ASSERTSE_TAIL));
  Result := '';
end;

// Die Argumente zwischen AOpen und AClose (eine Zeile), getrennt an den
// Kommas der obersten Ebene; Strings sieht die Code-Sicht nicht als Token,
// ihre Kommas trennen also nicht. '' oder der Grund.
function SplitArgs(AMap: TRdxCodeMap; const AOpen, AClose: TRdxToken;
  out AParts: TArray<string>): string;
var
  L     : string;
  P, T  : TRdxToken;
  Depth : Integer;
  From  : Integer;
begin
  AParts := nil;
  L := AMap.Raw(AOpen.Line);
  Depth := 0;
  From := AOpen.EndCol;
  P := AOpen;
  T := After(AMap, AOpen);
  while not SameTok(T, AClose) do
  begin
    if (T.Low = ';') or InList(T.Low, ANON_WORDS) then
      Exit(_(R_ASSERTSE_ANON));
    if (T.Low = '<') and P.IsWord and (P.Line = T.Line)
       and (P.EndCol = T.Col) then
      Exit(_(R_ASSERTSE_GENERIC));
    if (Depth = 0) and (T.Low = ',') then
    begin
      AddText(AParts, Trim(Copy(L, From, T.Col - From)));
      From := T.EndCol;
    end;
    Depth := Depth + ParenDelta(T);
    P := T;
    T := After(AMap, T);
  end;
  AddText(AParts, Trim(Copy(L, From, AClose.Col - From)));
  Result := '';
end;

// Ein oder zwei Argumente, keines leer; ohne Meldung passt die Bedingung in
// ein Literal. '' oder der Grund.
function ArgsReason(const AParts: TArray<string>): string;
var
  S : string;
begin
  Result := '';
  if (Length(AParts) < 1) or (Length(AParts) > 2) then
    Exit(_(R_ASSERTSE_ARGS, [Length(AParts)]));
  for S in AParts do
    if S = '' then
      Exit(_(R_ASSERTSE_ARGS, [Length(AParts)]));
  if (Length(AParts) = 1) and (Length(AParts[0]) > MAX_LITERAL) then
    Exit(_(R_ASSERTSE_LONG));
end;

// Steht vor AStart in derselben Routine ein 'with'? Rueckwaerts bis zum
// Kopf der Routine (IsRoutineHeadAfter - eine anonyme Methode zaehlt nicht
// als Kopf) oder einer Grenze der Unit.
function WithBefore(AMap: TRdxCodeMap; const AStart: TRdxToken): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  T := Before(AMap, AStart);
  while T.Low <> '' do
  begin
    if InList(T.Low, UNIT_BOUNDS) then
      Exit;
    P := Before(AMap, T);
    if (T.Low = 'with') and IsKeywordAfter(T, P) then
      Exit(True);
    if IsRoutineHeadAfter(T, P) then
      Exit;
    T := P;
  end;
end;

// Ist S ganz von EINEM Klammerpaar umschlossen ('(A and B)', nicht
// '(A) and (B)')? Dann braucht 'not' kein weiteres. Quotes schalten
// Strings um (ein verdoppeltes '' schaltet zweimal); Kommentare stehen in
// S nicht (ReadSite sperrt sie).
function FullyParenthesized(const S: string): Boolean;
var
  i, Depth : Integer;
  InStr    : Boolean;
begin
  Result := False;
  if (Length(S) < 2) or (S[1] <> '(') or (S[Length(S)] <> ')') then
    Exit;
  Depth := 0;
  InStr := False;
  for i := 1 to Length(S) do
    if S[i] = '''' then
      InStr := not InStr
    else if not InStr and (S[i] = '(') then
      Inc(Depth)
    else if not InStr and (S[i] = ')') then
    begin
      Dec(Depth);
      if (Depth = 0) and (i < Length(S)) then
        Exit;
    end;
  Result := Depth = 0;
end;

// Die Fundstelle auf ALine; '' oder der Grund.
function ReadSite(AMap: TRdxCodeMap; ALine: Integer;
  out ASite: TAssertSite): string;
begin
  ASite := Default(TAssertSite);
  Result := ReadStart(AMap, ALine, ASite.Start, ASite.Open);
  if Result <> '' then
    Exit;
  ASite.Close := MatchClose(AMap, ASite.Open, 0);
  if ASite.Close.Low = '' then
    Exit(_(R_ASSERTSE_ONE_LINE));
  Result := ReadEnd(AMap, ASite.Close, ASite.Last, ASite.Semi);
  if Result <> '' then
    Exit;
  if AMap.HasComment(ALine, ASite.Start.Col, ASite.Last.EndCol - 1) then
    Exit(_(R_ASSERTSE_COMMENT));
  Result := SplitArgs(AMap, ASite.Open, ASite.Close, ASite.Parts);
  if Result = '' then
    Result := ArgsReason(ASite.Parts);
end;

{ TRdxAssertSideEffectFix }

class function TRdxAssertSideEffectFix.AssertOutside(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Site   : TAssertSite;
  L      : string;
  Callee : string;
  Cond   : string;
  Msg    : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := ReadSite(AMap, ALine, Site);
  if (AReason = '') and DeclaresRoutine(AMap, 'Assert') then
    AReason := _(R_ASSERTSE_OWN);
  if (AReason = '') and WithBefore(AMap, Site.Start) then
    AReason := _(R_ASSERTSE_WITH);
  if AReason <> '' then
    Exit;
  L := AMap.Raw(ALine);
  Callee := TrimRight(Copy(L, Site.Start.Col, Site.Open.Col - Site.Start.Col));
  Cond := Site.Parts[0];
  if Length(Site.Parts) = 2 then
    Msg := Site.Parts[1]
  else
    Msg := QuotedStr(Cond);
  if not FullyParenthesized(Cond) then
    Cond := '(' + Cond + ')';
  AEdit.Span := TRefactorSpan.Make(SPAN_169, ALine, Site.Start.Col, ALine,
    Site.Last.EndCol);
  AEdit.Expected := Copy(L, Site.Start.Col,
    Site.Last.EndCol - Site.Start.Col);
  AEdit.NewText := 'if not ' + Cond + ' then ' + Callee + '(False, ' + Msg
    + ')' + Site.Semi;
  Result := True;
end;

end.
