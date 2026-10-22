unit uRdxAlwaysTrueFix;

// reDelphix - Editorhilfe fuer SCA150 BoolAlwaysTrue, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11, "bedingt"): ein 'if',
// dessen Bedingung immer wahr ist, wird aufgeloest -
//   'if Length(S) >= 0 then A;'         -> 'A;'
//   'if Length(S) >= 0 then A else B;'  -> 'A;'
// Der then-Zweig lief schon immer, ein else-Zweig nie; gleiche Bedeutung.
//
// WAS DER DETEKTOR MELDET (uBoolAlwaysTrue): lexisch auf dem Text ohne
// Strings und Kommentare genau vier Formen - 'Length(...) >= 0' und
// '0 <= Length(...)' (immer True) sowie 'Length(...) < 0' und
// '0 > Length(...)' (immer False), das Argument ohne Klammern ('[^()]*').
// Gemeldet wird die Zeile, auf der der Treffer BEGINNT (das 'Length' bzw.
// die '0'); die Meldung traegt die Form, keine Spalte und keinen Ausdruck.
// Ein 'if True then' oder 'X or True' meldet er NICHT. Er meldet auch, was
// nicht immer wahr ist ('Length(S) >= 0.5', '1.0 <= Length(S)': die Grenze
// '\b' steht vor dem '.') - die Hilfe verlangt die ganze Bedingung als
// Token und lehnt diese Faelle ab.
//
// DIE EINE FORM: die immer wahre Bedingung ist die GANZE Bedingung eines
// if als Anweisung - 'if <V> then', auch 'if (<V>) then' -, das Argument
// von Length ein blosser Name bzw. eine Kette 'A.B' (Konzept: kein Aufruf
// mit Seiteneffekt; ein Name kann eine parameterlose Funktion sein, die
// danach nicht mehr laeuft - der Detektor geht davon aus, dass Length(...)
// nur gelesen wird). Der then-Zweig ist eine einfache Anweisung oder ein
// begin..end-Block (der Block bleibt als Verbundanweisung stehen), ebenso
// ein else-Zweig.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   * die immer FALSCHE Form (der Zweig lief nie - war '= 0' gemeint? Das
//     entscheidet der Mensch, Konzept (b)); eine unbekannte Meldung;
//   * kein bzw. mehr als ein Treffer der Form auf der Zeile (verschoben,
//     mehrdeutig);
//   * das Argument ist kein blosser Name (Aufruf, Ausdruck, Literal);
//   * die Bedingung ist nicht allein ('and'/'or', 'while', 'until',
//     Zuweisung, Argument) oder das if steht nicht als Anweisung (bedingter
//     Ausdruck von Delphi 13);
//   * ein Zweig ist keine einfache Anweisung und kein begin..end (if, case,
//     Schleifen, try, with, anonyme Methode auf oberster Ebene, leerer
//     Zweig) oder hinter der Anweisung folgt Unerwartetes;
//   * ein Kommentar in Bedingung oder else-Zweig (er ginge verloren) oder
//     eine Compiler-Direktive irgendwo im if.
// Der Planer ersetzt EINEN Bereich (vom if bis zum Ende des letzten Zweigs)
// durch den Text des then-Zweigs.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_AT_FORM = 'the message names no known always-true comparison';
  R_AT_FALSE = 'the condition is always False - the branch never ran; '
    + 'whether "= 0" was meant is for a human to decide';
  R_AT_MOVED = 'no comparison %s on the reported line';
  R_AT_MANY = 'the line has more than one comparison %s';
  R_AT_ARG = 'the argument of Length is not a plain name - its evaluation '
    + 'would be dropped';
  R_AT_NOT_IF = 'the comparison is not the whole condition of an "if" '
    + '(and/or, while, until, assignment)';
  R_AT_EXPR = 'the "if" is not a statement (conditional expression?)';
  R_AT_BRANCH = 'the branch after "%s" is no single statement or '
    + 'begin..end block';
  R_AT_TAIL = 'unexpected code after the "if" statement';
  R_AT_COMMENT = 'comment in the condition or in the "else" branch - it '
    + 'would be lost';
  R_AT_DIRECTIVE = 'compiler directive in the "if" statement';

  // Die Formen, wie die Meldung sie nennt (uBoolAlwaysTrue, MissingVar) -
  // Detektortext, keine msgids.
  MSG_LEN_GE  = 'Length(...) >= 0 is always True';
  MSG_ZERO_LE = '0 <= Length(...) is always True';
  MSG_LEN_LT  = 'Length(...) < 0 is always False';
  MSG_ZERO_GT = '0 > Length(...) is always False';
  // So nennen die Gruende die Form (Code, keine msgid; Argument von
  // R_AT_MOVED und R_AT_MANY).
  CODE_LEN_GE  = '"Length(..) >= 0"';
  CODE_ZERO_LE = '"0 <= Length(..)"';

type
  // Der Planer von SCA150 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxAlwaysTrueFix = class
  public
    // ALine ist die Zeile des Treffers ('Length' bzw. '0'), AMessage die
    // Meldung (sie nennt die Form). Liefert die eine Ersetzung vom if bis
    // zum Ende des letzten Zweigs oder den Grund.
    class function ResolveIf(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_150  = 'sca150';
  KW_LENGTH = 'length';
  KW_IF     = 'if';
  KW_THEN   = 'then';
  KW_ELSE   = 'else';
  KW_BEGIN  = 'begin';
  ZERO      = '0';
  // Hier endet eine einfache Anweisung (auf Klammertiefe 0, als
  // Schluesselwort; dazu ';').
  BRANCH_ENDS: array[0..4] of string = ('else', 'end', 'until', 'except',
    'finally');
  // Auf oberster Ebene einer einfachen Anweisung nicht erlaubt: ein
  // eigener Block, eine Struktur oder eine anonyme Methode.
  NOT_SIMPLE: array[0..18] of string = ('begin', 'case', 'try', 'asm',
    'record', 'if', 'then', 'while', 'for', 'repeat', 'with', 'do', 'of',
    'procedure', 'function', 'implementation', 'initialization',
    'finalization', 'label');

type
  // Die Formen der Meldung.
  TRdxAtForm = (afNone, afLenGe, afZeroLe, afFalse);

  // Ein Treffer: erstes und letztes Token des Vergleichs, die Klammern von
  // Length.
  TRdxAtCond = record
    First : TRdxToken;
    Last  : TRdxToken;
    Open  : TRdxToken;
    Close : TRdxToken;
  end;

function FormOf(const AMessage: string): TRdxAtForm;
begin
  if Pos(MSG_LEN_GE, AMessage) > 0 then
    Result := afLenGe
  else if Pos(MSG_ZERO_LE, AMessage) > 0 then
    Result := afZeroLe
  else if (Pos(MSG_LEN_LT, AMessage) > 0) or (Pos(MSG_ZERO_GT, AMessage) > 0) then
    Result := afFalse
  else
    Result := afNone;
end;

// 'Length(..)' an T - das Wort als Bezeichner (kein Glied 'X.Length'), die
// Klammern in AOpen/AClose.
function LengthCallAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out AOpen, AClose: TRdxToken): Boolean;
begin
  Result := False;
  AOpen := Default(TRdxToken);
  AClose := Default(TRdxToken);
  if (T.Low <> KW_LENGTH) or not IsKeywordAfter(T, Before(AMap, T)) then
    Exit;
  AOpen := After(AMap, T);
  if AOpen.Low <> '(' then
    Exit;
  AClose := MatchClose(AMap, AOpen);
  Result := AClose.Low <> '';
end;

// Beginnt an T ein Vergleich der Form AForm? Dann ACond.
function CondAt(AMap: TRdxCodeMap; const T: TRdxToken; AForm: TRdxAtForm;
  out ACond: TRdxAtCond): Boolean;
var
  Op, N : TRdxToken;
begin
  Result := False;
  ACond := Default(TRdxAtCond);
  if AForm = afLenGe then
  begin
    if not LengthCallAt(AMap, T, ACond.Open, ACond.Close) then
      Exit;
    Op := After(AMap, ACond.Close);
    N := After(AMap, Op);
    if (Op.Low <> '>=') or (N.Low <> ZERO) then
      Exit;
    ACond.Last := N;
  end
  else
  begin
    if T.Low <> ZERO then
      Exit;
    Op := After(AMap, T);
    N := After(AMap, Op);
    if (Op.Low <> '<=') or not LengthCallAt(AMap, N, ACond.Open, ACond.Close) then
      Exit;
    ACond.Last := ACond.Close;
  end;
  ACond.First := T;
  Result := True;
end;

// Der eine Vergleich der Form AForm, der auf ALine beginnt. '' oder der
// Grund.
function FindCond(AMap: TRdxCodeMap; ALine: Integer; AForm: TRdxAtForm;
  out ACond: TRdxAtCond): string;
var
  T    : TRdxToken;
  C    : TRdxAtCond;
  n    : Integer;
  Code : string;
begin
  ACond := Default(TRdxAtCond);
  n := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if CondAt(AMap, T, AForm, C) then
    begin
      Inc(n);
      ACond := C;
    end;
    T := After(AMap, T);
  end;
  if AForm = afLenGe then
    Code := CODE_LEN_GE
  else
    Code := CODE_ZERO_LE;
  if n = 0 then
    Result := MsgMovedSuffix(_(R_AT_MOVED, [Code]))
  else if n > 1 then
    Result := _(R_AT_MANY, [Code])
  else
    Result := '';
end;

// Das Argument von Length: Name ('.' Name)* - nichts anderes. '' oder der
// Grund.
function ArgReason(AMap: TRdxCodeMap; const ACond: TRdxAtCond): string;
var
  T        : TRdxToken;
  WantWord : Boolean;
begin
  Result := _(R_AT_ARG);
  T := After(AMap, ACond.Open);
  WantWord := True;
  while (T.Low <> '') and not SameTok(T, ACond.Close) do
  begin
    if WantWord <> T.IsWord then
      Exit;
    if not WantWord and (T.Low <> '.') then
      Exit;
    WantWord := not WantWord;
    T := After(AMap, T);
  end;
  // Leer ('Length()', 'Length(''x'')' - der String ist kein Token) oder
  // auf '.' endend.
  if not WantWord then
    Result := '';
end;

// Das if um den Vergleich: davor 'if', dahinter 'then' (auch in einem
// Klammerpaar), das if als Anweisung. '' oder der Grund.
function IfAround(AMap: TRdxCodeMap; const ACond: TRdxAtCond;
  out AIf, AThen: TRdxToken): string;
var
  PP : TRdxToken;
begin
  AIf := Before(AMap, ACond.First);
  AThen := After(AMap, ACond.Last);
  if (AIf.Low = '(') and (AThen.Low = ')') then
  begin
    AIf := Before(AMap, AIf);
    AThen := After(AMap, AThen);
  end;
  if not ((AIf.Low = KW_IF) and IsKeywordAfter(AIf, Before(AMap, AIf))
     and (AThen.Low = KW_THEN) and IsKeywordAfter(AThen, Before(AMap, AThen))) then
    Exit(_(R_AT_NOT_IF));
  PP := Before(AMap, AIf);
  if not InList(PP.Low, STATEMENT_PREV)
     or (PP.IsWord and not IsKeywordAfter(PP, Before(AMap, PP))) then
    Exit(_(R_AT_EXPR));
  Result := '';
end;

// Ein Zweig ab AStart (hinter AWord - then bzw. else): ein begin..end-Block
// oder eine einfache Anweisung bis ';' bzw. einem Block-Ende auf
// Klammertiefe 0. ATerm ist das Token hinter dem Zweig. '' oder der Grund.
function ReadBranch(AMap: TRdxCodeMap; const AStart: TRdxToken;
  const AWord: string; out ATerm: TRdxToken): string;
var
  T, P, E, L : TRdxToken;
  Depth      : Integer;
begin
  ATerm := Default(TRdxToken);
  P := Before(AMap, AStart);
  if (AStart.Low = KW_BEGIN) and IsKeywordAfter(AStart, P) then
  begin
    Result := BlockEnd(AMap, AStart, nil, E, L);
    if (Result = '') and (E.Low = '') then
      Result := MsgStatementEndNotFound;
    if Result = '' then
      ATerm := After(AMap, E);
    Exit;
  end;
  if (AStart.Low = '') or (AStart.Low = ';')
     or (IsKeywordAfter(AStart, P)
         and (InList(AStart.Low, BRANCH_ENDS) or InList(AStart.Low, NOT_SIMPLE))) then
    Exit(_(R_AT_BRANCH, [AWord]));
  Depth := 0;
  T := AStart;
  while T.Low <> '' do
  begin
    if Depth = 0 then
    begin
      if (T.Low = ';')
         or (IsKeywordAfter(T, P) and InList(T.Low, BRANCH_ENDS)) then
        Break;
      if IsKeywordAfter(T, P) and InList(T.Low, NOT_SIMPLE) then
        Exit(_(R_AT_BRANCH, [AWord]));
    end;
    Inc(Depth, ParenDelta(T));
    if Depth < 0 then
      Exit(MsgStatementEndNotFound);
    P := T;
    T := After(AMap, T);
  end;
  if T.Low = '' then
    Exit(MsgStatementEndNotFound);
  ATerm := T;
  Result := '';
end;

// Hinter dem if: ';' oder das Ende des umgebenden Blocks.
function TailReason(AMap: TRdxCodeMap; const ATerm: TRdxToken): string;
begin
  Result := '';
  if ATerm.Low = ';' then
    Exit;
  if not (IsKeywordAfter(ATerm, Before(AMap, ATerm))
          and InList(ATerm.Low, BRANCH_ENDS)) then
    Result := _(R_AT_TAIL);
end;

// Das Ende (Zeile, Spalte hinter dem letzten Zeichen) des Codes vor ATerm -
// auch ein String-Literal am Ende zaehlt (der Token-Leser ueberspringt
// Strings).
procedure EndBefore(AMap: TRdxCodeMap; const ATerm: TRdxToken;
  out ALine, AEndCol: Integer);
var
  Co : Integer;
begin
  if not LastCharBefore(AMap, ATerm, ALine, Co) then
    Co := 0;
  AEndCol := Co + 1;
end;

{ TRdxAlwaysTrueFix }

class function TRdxAlwaysTrueFix.ResolveIf(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Form                     : TRdxAtForm;
  Cond                     : TRdxAtCond;
  IfTok, ThenTok, First    : TRdxToken;
  Term1, Term              : TRdxToken;
  End1Line, End1Col        : Integer;
  EndLine, EndCol          : Integer;
  Span                     : TRefactorSpan;
begin
  AEdit := Default(TRdxEdit);
  Cond := Default(TRdxAtCond);
  IfTok := Default(TRdxToken);
  ThenTok := Default(TRdxToken);
  First := Default(TRdxToken);
  Term1 := Default(TRdxToken);
  Term := Default(TRdxToken);
  End1Line := 0;
  End1Col := 0;
  EndLine := 0;
  EndCol := 0;
  AReason := '';
  Form := FormOf(AMessage);
  if Form = afNone then
    AReason := _(R_AT_FORM)
  else if Form = afFalse then
    AReason := _(R_AT_FALSE);
  if AReason = '' then
    AReason := FindCond(AMap, ALine, Form, Cond);
  if AReason = '' then
    AReason := ArgReason(AMap, Cond);
  if AReason = '' then
    AReason := IfAround(AMap, Cond, IfTok, ThenTok);
  if AReason = '' then
  begin
    First := After(AMap, ThenTok);
    AReason := ReadBranch(AMap, First, KW_THEN, Term1);
  end;
  if AReason = '' then
  begin
    Term := Term1;
    if (Term1.Low = KW_ELSE) and IsKeywordAfter(Term1, Before(AMap, Term1)) then
      AReason := ReadBranch(AMap, After(AMap, Term1), KW_ELSE, Term);
  end;
  if AReason = '' then
    AReason := TailReason(AMap, Term);
  if AReason = '' then
  begin
    EndBefore(AMap, Term1, End1Line, End1Col);
    EndBefore(AMap, Term, EndLine, EndCol);
    if DirectiveInLines(AMap, IfTok.Line, EndLine) then
      AReason := _(R_AT_DIRECTIVE)
    else if CommentInRange(AMap, TRefactorSpan.Make(SPAN_150, IfTok.Line,
         IfTok.Col, First.Line, First.Col))
       or CommentInRange(AMap, TRefactorSpan.Make(SPAN_150, End1Line, End1Col,
         EndLine, EndCol)) then
      AReason := _(R_AT_COMMENT);
  end;
  if AReason = '' then
  begin
    Span := TRefactorSpan.Make(SPAN_150, IfTok.Line, IfTok.Col, EndLine,
      EndCol);
    AEdit.Span := Span;
    AEdit.Expected := RangeText(AMap, Span);
    AEdit.NewText := RangeText(AMap, TRefactorSpan.Make(SPAN_150, First.Line,
      First.Col, End1Line, End1Col));
  end;
  Result := AReason = '';
  if not Result then
    AEdit := Default(TRdxEdit);
end;

end.
