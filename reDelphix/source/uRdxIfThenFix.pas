unit uRdxIfThenFix;

// reDelphix - Editorhilfe SCA131 IfThenShortCircuit, OHNE ToolsAPI und ohne
// Parser: die Zuweisung 'X := IfThen(C, A, B);' wird zu
//
//   if C then
//     X := A
//   else
//     X := B;
//
// DER FUND: uIfThenShortCircuit meldet auf der Zeile des ERSTEN Tokens der
// Anweisung (nkAssign/nkCall, T.Line in uParser2), eine feste Meldung ohne
// Spalte. Gemeldet wird nur, wenn ein Wert-Arm einen Aufruf mit Klammern
// traegt, der kein reines Builtin ist (ValueBranchHasSideEffectCall) - auch
// eingebettet ('Trim(IfThen(..))', 'ShowMessage(IfThen(..))'); diese Formen
// bekommen keine Hilfe.
//
// VERHALTEN (Kennzeichnung E2): IfThen ist eine gewoehnliche Funktion, beide
// Arme laufen VOR dem Aufruf. Danach laeuft nur noch der zutreffende Arm -
// Nebenwirkungen, Kosten und Ausnahmen des anderen entfallen. Genau das ist
// der Fix, aber es aendert, was zur Laufzeit geschieht. Die Bedingung laeuft
// wie vorher genau einmal; X wird wie vorher genau einmal zugewiesen.
// Typen: Math.IfThen waehlt eine Ueberladung (Integer, Int64, Double ...)
// und wandelt beide Arme in deren Typ; die Zuweisung an X wandelt danach in
// den Typ von X. Ohne IfThen wandelt die Zuweisung den Arm unmittelbar. Fuer
// Zahlen und Strings ist der Wert derselbe; bei einem Variant als Ziel
// bekaeme X aus einem Literal-Arm einen anderen VarType (ShortInt statt
// Integer) - diese Typfrage stellt der Adapter in uRdxFixTable mit dem
// Quellstellen-Dienst (VariantReason, TargetOf).
//
// FORM: die mehrzeilige Form aus dem Katalog (GoodExample von SCA131, auch
// im Kopf des Detektors); die Zweige ruecken um eine Stufe ein (IndentStep:
// zwei Leerzeichen bzw. ein Tab, wenn die Zeile mit Tabs einrueckt). Die
// einzeilige Form 'if C then X := A else X := B;' waere bei den gemeldeten
// Aufrufen meist laenger als die Zeile davor.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - kein bzw. mehr als ein 'IfThen' im Code der Zeile (Zeile verschoben,
//     mehrdeutig, verschachtelte IfThen),
//   - die Zuweisung steht nicht allein auf ihrer Zeile (Code oder Kommentar
//     davor, Code oder Direktive dahinter), ist eine Inline-Deklaration
//     ('var X := IfThen(..)'), oder ihr Ziel ist kein einfacher Ausdruck,
//   - die Zuweisung ist Zweig eines then/else/do ohne begin..end, ein
//     case-Zweig oder markiert (':') - Vorgabe des Auftrags; die neue
//     if-Anweisung truege dort ihr eigenes else, mehrzeilig ohne Block,
//   - IfThen ist nicht die ganze rechte Seite ('IfThen(..) + 1',
//     'Trim(IfThen(..))'), schliesst nicht auf der Zeile, hat nicht genau drei
//     Argumente (zwei: das dritte haengt an der Ueberladung, 0 bzw. ''),
//     traegt eine anonyme Methode, einen Kommentar oder ein '<' direkt
//     hinter einem Namen (Typargumente: deren Kommas trennt die Hilfe nicht
//     sicher von den Argument-Kommas),
//   - IfThen ist nicht das von System.Math bzw. System.StrUtils: fremder
//     Qualifizierer, eine eigene Routine IfThen in der Datei, keine der
//     beiden Units in uses, oder ein with in der Routine davor (IfThen oder X
//     koennten Member des with-Ausdrucks sein).
//
// GRENZEN: eine andere Unit in uses, die eine eigene IfThen exportiert und
// nach System.Math steht, sieht die Hilfe nicht (der Detektor ebenso
// wenig); eine geerbte Methode IfThen einer Klasse aus einer anderen Unit
// auch nicht. Ein with in einem frueheren, schon geschlossenen Block der
// Routine sperrt mit (sicher, nur weniger Angebot).
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
  R_IFTHEN_MOVED = 'no "IfThen" on the reported line';
  R_IFTHEN_MANY = 'the line has more than one "IfThen"';
  R_IFTHEN_NOT_ALONE = 'the assignment does not stand alone on its line';
  R_IFTHEN_INLINE = 'inline declaration "%s X := IfThen(..)" - declare X '
    + 'first';
  R_IFTHEN_BRANCH = 'the assignment follows "%s" without begin..end - put '
    + 'it into begin..end first';
  R_IFTHEN_FORM = 'not of the form "X := IfThen(Cond, A, B);"';
  R_IFTHEN_NOT_WHOLE = 'IfThen(..) is not the whole right-hand side of the '
    + 'assignment';
  R_IFTHEN_FOREIGN = '"%s.IfThen" is not the IfThen of System.Math or '
    + 'System.StrUtils';
  R_IFTHEN_ONE_LINE = 'IfThen(..) does not close on its line';
  R_IFTHEN_TAIL = 'code or a compiler directive follows the statement on '
    + 'its line';
  R_IFTHEN_COMMENT = 'comment or compiler directive inside the statement';
  R_IFTHEN_ARGS = 'IfThen has %d arguments here, not three';
  R_IFTHEN_TWO_ARGS = 'IfThen with two arguments - the default of the third '
    + 'depends on the overload (0 or an empty string)';
  R_IFTHEN_GENERIC = '"<" right after a name in the arguments (type '
    + 'arguments?) - their commas cannot be told apart safely';
  R_IFTHEN_ANON = 'anonymous method in the arguments';
  R_IFTHEN_OWN = 'the file declares its own routine IfThen';
  R_IFTHEN_NO_UNIT = 'neither System.Math nor System.StrUtils is in uses - '
    + 'IfThen may be another routine';
  R_IFTHEN_WITH = 'with statement in the routine - IfThen or the target '
    + 'could be a member of the with expression';
  R_IFTHEN_VARIANT = '%s is a Variant - a literal branch would give it '
    + 'another VarType than the result of IfThen';

type
  TRdxIfThenFix = class
  public
    // SCA131: 'X := IfThen(C, A, B);' allein auf ALine ->
    // 'if C then X := A else X := B;' mehrzeilig (s. Kopf). Form
    // TRdxMapPlanner (uRdxFixRunner); AMessage braucht die Hilfe nicht
    // (feste Meldung ohne Spalte).
    class function IfThenToIf(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // Das Ziel X einer Ersetzung von IfThenToIf: der Text vor dem ersten
    // ':=' in AExpected, ohne Leerraum; '' ohne ':='. Fuer die Typfrage des
    // Adapters (DeclaredTypeOf).
    class function TargetOf(const AExpected: string): string; static;
    // Der Grund, wenn der Adapter X als Variant bzw. OleVariant kennt
    // (R_IFTHEN_VARIANT, uebersetzt - _() steht hier, weil tools/
    // i18n_extract.py nur Konstanten derselben Unit aufloest).
    class function VariantReason(const ATarget: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_131 = 'sca131';
  KW_IFTHEN = 'ifthen';
  // Die Units, deren IfThen gemeint ist - in uses (FPC: Math, StrUtils) und
  // als Qualifizierer vor dem Aufruf.
  IFTHEN_UNITS: array[0..3] of string = ('math', 'system.math', 'strutils',
    'system.strutils');
  IFTHEN_QUALIFIERS: array[0..3] of string = ('math.', 'system.math.',
    'strutils.', 'system.strutils.');
  // Davor steht eine Anweisung fuer sich (keine Zweig-Anweisung):
  // uRdxCodeMap.LIST_PREV; dahinter endet eine Anweisung ohne ';':
  // uRdxCodeMap.LIST_ENDS; die Suche nach einem with davor endet an
  // uRdxCodeMap.UNIT_BOUNDS. Bis zur Hygiene-Welle H1 standen hier
  // byte-gleiche Kopien (STMT_PREV, STMT_END_WORDS, UNIT_BOUNDS).
  // Davor ist die Anweisung ein Zweig ohne begin..end, ein case-Zweig oder
  // markiert.
  BRANCH_PREV: array[0..3] of string = ('then', 'else', 'do', ':');
  // Woerter, die in einem einfachen Zuweisungsziel nicht stehen.
  NOT_IN_TARGET: array[0..37] of string = ('if', 'then', 'else', 'do',
    'while', 'for', 'to', 'downto', 'case', 'of', 'with', 'repeat', 'until',
    'begin', 'end', 'try', 'finally', 'except', 'raise', 'goto', 'on', 'asm',
    'and', 'or', 'not', 'xor', 'in', 'is', 'as', 'div', 'mod', 'shl', 'shr',
    'var', 'const', 'inherited', 'function', 'procedure');
  // Was ausser Woertern auf oberster Ebene im Ziel steht ('A.B', 'A[i]',
  // 'P^', 'F(x).Y', '&Name', '@Proc').
  TARGET_MARKS: array[0..7] of string = ('.', '[', ']', '(', ')', '^', '&',
    '@');
  // Damit beginnt eine anonyme Methode (in einem Argument).
  ANON_WORDS: array[0..2] of string = ('function', 'procedure', 'begin');

type
  // Die Token einer Fundstelle.
  TIfThenSite = record
    Start  : TRdxToken;   // erstes Token der Anweisung (das Ziel)
    Assign : TRdxToken;   // ':='
    Open   : TRdxToken;   // '(' hinter IfThen
    Close  : TRdxToken;   // ')' dazu
    Last   : TRdxToken;   // ';' bzw. ')' ohne ';'
    Semi   : string;      // ';' oder ''
    Parts  : TArray<string>;   // Bedingung, A, B (getrimmt)
  end;

// Wie viele 'IfThen' stehen im Code von ALine? ASemiBefore: vor dem ersten
// steht ein ';' auf der Zeile (eine andere Anweisung davor).
function IfThensOnLine(AMap: TRdxCodeMap; ALine: Integer;
  out ASemiBefore: Boolean): Integer;
var
  T : TRdxToken;
begin
  Result := 0;
  ASemiBefore := False;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.Low = KW_IFTHEN then
      Inc(Result)
    else if (T.Low = ';') and (Result = 0) then
      ASemiBefore := True;
    T := After(AMap, T);
  end;
end;

// Der Anfang der Anweisung auf ALine: allein auf der Zeile, keine
// Inline-Deklaration, davor das Ende einer Anweisung bzw. der Anfang einer
// Anweisungsliste. '' oder der Grund.
function ReadStart(AMap: TRdxCodeMap; ALine: Integer;
  out AStart: TRdxToken): string;
var
  P    : TRdxToken;
  n    : Integer;
  Semi : Boolean;
begin
  AStart := Default(TRdxToken);
  n := IfThensOnLine(AMap, ALine, Semi);
  if n = 0 then
    Exit(MsgMovedSuffix(_(R_IFTHEN_MOVED)));
  if n > 1 then
    Exit(_(R_IFTHEN_MANY));
  if AMap.StartsInside(ALine) then
    Exit(MsgLineStartsInCommentOrString);
  AStart := NextToken(AMap, ALine, 1);
  if Semi or not FirstOnLine(AMap, AStart) then
    Exit(_(R_IFTHEN_NOT_ALONE));
  if InList(AStart.Low, INLINE_DECLS) then
    Exit(_(R_IFTHEN_INLINE, [TokText(AMap, AStart)]));
  P := Before(AMap, AStart);
  if InList(P.Low, BRANCH_PREV) then
    Exit(_(R_IFTHEN_BRANCH, [TokText(AMap, P)]));
  if not InList(P.Low, LIST_PREV) then
    Exit(MsgUnclearStatementOwner(TokText(AMap, P)));
  Result := '';
end;

// Das ':=' hinter dem Ziel ab AStart, alles auf ALine; das Ziel ist ein
// einfacher Ausdruck (Woerter ausser NOT_IN_TARGET, TARGET_MARKS, in
// Klammern beliebige Token ausser ';'). '' oder der Grund.
function ReadTarget(AMap: TRdxCodeMap; const AStart: TRdxToken;
  out AAssign: TRdxToken): string;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  AAssign := Default(TRdxToken);
  Depth := 0;
  T := AStart;
  while not ((Depth = 0) and (T.Low = ':=')) do
  begin
    if (T.Low = '') or (T.Line <> AStart.Line) or (T.Low = ';') then
      Exit(_(R_IFTHEN_FORM));
    if T.IsWord then
    begin
      if InList(T.Low, NOT_IN_TARGET) then
        Exit(_(R_IFTHEN_FORM));
    end
    else if (Depth = 0) and not InList(T.Low, TARGET_MARKS) then
      Exit(_(R_IFTHEN_FORM));
    Depth := Depth + ParenDelta(T);
    if Depth < 0 then
      Exit(_(R_IFTHEN_FORM));
    T := After(AMap, T);
  end;
  if SameTok(T, AStart) then
    Exit(_(R_IFTHEN_FORM));
  AAssign := T;
  Result := '';
end;

// Hinter ':=' unmittelbar 'IfThen(' (auch 'Math.IfThen(', 'System.StrUtils.
// IfThen('), die Klammer schliesst auf der Zeile. '' oder der Grund.
function ReadCall(AMap: TRdxCodeMap; const AAssign: TRdxToken;
  out AOpen, AClose: TRdxToken): string;
var
  First, T : TRdxToken;
  Q        : string;
begin
  AOpen := Default(TRdxToken);
  AClose := Default(TRdxToken);
  First := After(AMap, AAssign);
  T := First;
  Q := '';
  while T.IsWord and (T.Low <> KW_IFTHEN) and (After(AMap, T).Low = '.') do
  begin
    Q := Q + T.Low + '.';
    T := After(AMap, After(AMap, T));
  end;
  if (T.Low <> KW_IFTHEN) or (T.Line <> AAssign.Line) then
    Exit(_(R_IFTHEN_NOT_WHOLE));
  if (Q <> '') and not InList(Q, IFTHEN_QUALIFIERS) then
    Exit(_(R_IFTHEN_FOREIGN, [Trim(Copy(AMap.Raw(T.Line), First.Col,
      T.Col - 1 - First.Col))]));
  AOpen := After(AMap, T);
  if AOpen.Low <> '(' then
    Exit(_(R_IFTHEN_FORM));
  AClose := MatchClose(AMap, AOpen, 0);
  if AClose.Low = '' then
    Exit(_(R_IFTHEN_ONE_LINE));
  Result := '';
end;

// Das Ende der Anweisung hinter AClose: ';' auf der Zeile, oder kein ';'
// vor end/until/except/finally; dahinter auf der Zeile nur Leerraum oder
// Kommentar. '' oder der Grund.
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
      Exit(_(R_IFTHEN_FORM));
    ALast := N;
    ASemi := ';';
  end
  else if not InList(N.Low, LIST_ENDS) then
    Exit(_(R_IFTHEN_NOT_WHOLE));
  if not TailIsQuiet(AMap, ALast.Line, ALast.EndCol - 1) then
    Exit(_(R_IFTHEN_TAIL));
  Result := '';
end;

// Die Argumente zwischen AOpen und AClose (eine Zeile), getrennt an den
// Kommas der obersten Ebene; Strings sieht die Code-Sicht nicht als Token,
// ihre Kommas trennen also nicht. '' oder der Grund.
function SplitArgs(AMap: TRdxCodeMap; const AOpen, AClose: TRdxToken;
  out AParts: TArray<string>): string;
var
  L       : string;
  P, T    : TRdxToken;
  Depth   : Integer;
  From    : Integer;
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
      Exit(_(R_IFTHEN_ANON));
    if (T.Low = '<') and P.IsWord and (P.Line = T.Line)
       and (P.EndCol = T.Col) then
      Exit(_(R_IFTHEN_GENERIC));
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

// Die Zahl der Argumente: genau drei, keines leer. '' oder der Grund.
function ArgsReason(const AParts: TArray<string>): string;
var
  S : string;
begin
  Result := '';
  if Length(AParts) = 2 then
    Exit(_(R_IFTHEN_TWO_ARGS));
  if Length(AParts) <> 3 then
    Exit(_(R_IFTHEN_ARGS, [Length(AParts)]));
  for S in AParts do
    if S = '' then
      Exit(_(R_IFTHEN_ARGS, [Length(AParts)]));
end;

// Nennt eine uses-Klausel der Datei System.Math oder System.StrUtils (auch
// FPC: Math, StrUtils)? 'Name in ''datei.pas''' zaehlt mit dem Namen.
function UsesIfThenUnit(AMap: TRdxCodeMap): Boolean;
var
  T, U   : TRdxToken;
  Name   : string;
  InPath : Boolean;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'uses');
  while T.Low <> '' do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      Name := '';
      InPath := False;
      U := After(AMap, T);
      while (U.Low <> '') and (U.Low <> ';') do
      begin
        if U.Low = ',' then
        begin
          if InList(Name, IFTHEN_UNITS) then
            Exit(True);
          Name := '';
          InPath := False;
        end
        else if U.Low = 'in' then
          InPath := True
        else if not InPath then
          Name := Name + U.Low;
        U := After(AMap, U);
      end;
      if InList(Name, IFTHEN_UNITS) then
        Exit(True);
    end;
    T := NextTokenOnLineWith(AMap, T, 'uses');
  end;
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

// Die Fundstelle auf ALine; '' oder der Grund.
function ReadSite(AMap: TRdxCodeMap; ALine: Integer;
  out ASite: TIfThenSite): string;
begin
  ASite := Default(TIfThenSite);
  Result := ReadStart(AMap, ALine, ASite.Start);
  if Result = '' then
    Result := ReadTarget(AMap, ASite.Start, ASite.Assign);
  if Result = '' then
    Result := ReadCall(AMap, ASite.Assign, ASite.Open, ASite.Close);
  if Result = '' then
    Result := ReadEnd(AMap, ASite.Close, ASite.Last, ASite.Semi);
  if Result <> '' then
    Exit;
  if AMap.HasComment(ALine, ASite.Start.Col, ASite.Last.EndCol - 1) then
    Exit(_(R_IFTHEN_COMMENT));
  Result := SplitArgs(AMap, ASite.Open, ASite.Close, ASite.Parts);
  if Result = '' then
    Result := ArgsReason(ASite.Parts);
end;

// Was die ganze Datei sagt: eigene IfThen, uses, with davor. '' oder der
// Grund.
function FileReason(AMap: TRdxCodeMap; const AStart: TRdxToken): string;
begin
  Result := '';
  if DeclaresRoutine(AMap, 'IfThen') then
    Exit(_(R_IFTHEN_OWN));
  if not UsesIfThenUnit(AMap) then
    Exit(_(R_IFTHEN_NO_UNIT));
  if WithBefore(AMap, AStart) then
    Exit(_(R_IFTHEN_WITH));
end;

{ TRdxIfThenFix }

class function TRdxIfThenFix.IfThenToIf(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Site   : TIfThenSite;
  L      : string;
  Indent : string;
  Step   : string;
  Target : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := ReadSite(AMap, ALine, Site);
  if AReason = '' then
    AReason := FileReason(AMap, Site.Start);
  if AReason <> '' then
    Exit;
  L := AMap.Raw(ALine);
  Indent := Copy(L, 1, Site.Start.Col - 1);
  Step := IndentStep(Indent, '');
  Target := TrimRight(Copy(L, Site.Start.Col,
    Site.Assign.Col - Site.Start.Col));
  AEdit.Span := TRefactorSpan.Make(SPAN_131, ALine, Site.Start.Col, ALine,
    Site.Last.EndCol);
  AEdit.Expected := Copy(L, Site.Start.Col,
    Site.Last.EndCol - Site.Start.Col);
  AEdit.NewText := 'if ' + Site.Parts[0] + ' then' + #10
    + Indent + Step + Target + ' := ' + Site.Parts[1] + #10
    + Indent + 'else' + #10
    + Indent + Step + Target + ' := ' + Site.Parts[2] + Site.Semi;
  Result := True;
end;

class function TRdxIfThenFix.TargetOf(const AExpected: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos(':=', AExpected);
  if P > 0 then
    Result := Trim(Copy(AExpected, 1, P - 1));
end;

class function TRdxIfThenFix.VariantReason(const ATarget: string): string;
begin
  Result := _(R_IFTHEN_VARIANT, [ATarget]);
end;

end.
