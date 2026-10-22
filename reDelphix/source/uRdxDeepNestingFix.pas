unit uRdxDeepNestingFix;

// reDelphix - Editorhilfe fuer SCA018 DeepNesting, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11: "bedingt -
// Waechter-Klausel nur fuer das letzte if einer Routine"):
//   begin                        begin
//     Prepare;                     Prepare;
//     if A then             ->     if not A then Exit;
//     begin                        Work;
//       Work;                      More;
//       More;                    end;
//     end;
//   end;
// Der Rumpf des if rueckt eine Stufe aus; alles darin liegt eine Ebene
// flacher. Gleiche Bedeutung: A wird wie vorher genau einmal ausgewertet;
// ist es falsch, endet die Routine wie vorher ohne weiteren Code (Exit an
// derselben Stelle, an der sonst das end erreicht wuerde).
//
// DER FUND (uDeepNesting): gemeldet wird die TIEFSTE Stelle einer Methode -
// Zeile des innersten if/for/while/repeat/case -, die Meldung 'Depth d
// (kind from line n, limit: m)' nennt Art und Zeile, nicht die aeussere
// Struktur. Der Planer geht deshalb von der gemeldeten Stelle zur Routine
// um sie (die innerste mit begin..end-Rumpf), nimmt deren LETZTE Anweisung
// und hilft nur, wenn das ein 'if A then begin B end' ist und die
// gemeldete Stelle in B liegt - sonst flachte die Waechter-Klausel die
// gemeldete Verschachtelung nicht ab. Liegt die Tiefe mehr als eine Stufe
// ueber der Grenze, bleibt der Fund (eine Ebene flacher) stehen; die Hilfe
// kann dann erneut greifen, wenn B wieder mit einem solchen if endet.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - die gemeldete Zeile traegt kein Schluesselwort der gemeldeten Art
//     (Zeile verschoben), die Meldung hat eine andere Form,
//   - keine Routine mit begin..end-Rumpf um die Stelle oder unsichere
//     Grenzen; eine Direktive im Rumpf (bedingter Code kann die letzte
//     Anweisung verschieben), eine anonyme Methode, goto/label/asm; die
//     Datei deklariert einen eigenen Bezeichner 'Exit',
//   - die letzte Anweisung ist kein 'if A then begin B end' (Code danach,
//     ein else, ein anderes Konstrukt), das if steht nicht selbst im Rumpf
//     der Routine (hinter then/else/do/einer Marke), die Bedingung traegt
//     einen bedingten Ausdruck (Delphi 13: 'if X then Y else Z'),
//   - eine Funktion ohne 'Result := ...' (bzw. Name der Funktion) als
//     eigene Anweisung auf oberster Ebene VOR dem if: Exit liesse Result
//     dort stehen, wo es bisher am Routinenende stand - gleich, aber die
//     Hilfe macht einen undefinierten Rueckgabewert nicht unauffaelliger,
//   - if, begin und end stehen nicht wie ueblich auf ihren Zeilen (begin
//     als letztes Code-Token seiner Zeile, end als erstes, dahinter nur
//     ';'), ein Kommentar im Kopf des if oder neben dem end,
//   - eine Zeile des Blocks beginnt in einem Block-Kommentar oder
//     mehrzeiligen String (Ausruecken aenderte ihn), ein Inline-'var' bzw.
//     'const' auf oberster Ebene des Blocks (sein Gueltigkeitsbereich
//     wuechse; 'for var' bleibt bei seiner Schleife), eine Blockzeile ohne
//     die Einrueckung der ersten.
// Kommentare IN B ruecken mit ihrer Zeile aus.
//
// NEGATION: 'not X' -> 'X' (X ein einfacher Operand: Name, Aufruf, Index,
// Klammer), ein einfacher Operand X -> 'not X', sonst 'not (A)'. ANNAHME:
// A ist ein Boolean-Ausdruck (if verlangt es); fuer ein Variant mit
// Ganzzahlwert waere 'not' bitweise - aus dem Text nicht beweisbar.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// PlanDeepNesting (Form TRdxFixPlanner) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_DN_MESSAGE = 'the message names no nesting kind';
  R_DN_MOVED = 'no "%s" on the reported line';
  R_DN_NO_ROUTINE = 'no routine with a begin..end body around the reported '
    + 'line';
  R_DN_BOUNDS = 'the bounds of the routine around the reported line are not '
    + 'safe to read';
  R_DN_DIRECTIVE = 'compiler directive in the routine - conditional code '
    + 'could change its last statement';
  R_DN_ANON = 'the routine contains an anonymous method';
  R_DN_JUMP = 'the routine contains goto or asm';
  R_DN_SHADOW = 'the file declares its own "Exit" - it is not the procedure '
    + 'of the RTL';
  R_DN_NOT_LAST = 'the last statement of the routine is not "if ... then '
    + 'begin ... end" - a guard clause fits only there';
  R_DN_NOT_TOP = 'the last if is not a statement of the routine body itself '
    + '("%s" before it)';
  R_DN_COND_EXPR = 'the condition contains a conditional expression (if .. '
    + 'then .. else)';
  R_DN_NOT_INSIDE = 'the reported nesting is not inside the last if of the '
    + 'routine - a guard clause would not flatten it';
  R_DN_RESULT = 'the function does not set Result by a plain statement '
    + 'before the if; by hand';
  R_DN_LAYOUT = 'if, begin and end do not stand on their own lines as usual '
    + '(code beside them)';
  R_DN_COMMENT = 'comment in the head of the if or beside its end';
  R_DN_MULTILINE = 'a line of the block starts inside a block comment or '
    + 'multi-line string - moving it left would change it';
  R_DN_INLINE = 'inline var or const at the top of the block - its scope '
    + 'would grow to the rest of the routine';
  R_DN_INDENT = 'uneven indentation in the block - line %d';

type
  TRdxDeepNestingFix = class
  public
    // SCA018: das letzte 'if A then begin B end' der Routine um ALine wird
    // zur Waechter-Klausel 'if not A then Exit;' mit B eine Stufe flacher.
    // ALine ist die gemeldete (tiefste) Stelle; die Art steht in AMessage.
    class function GuardClause(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks;       // TRdxBlocks.HeadBefore, TRdxRoutine

const
  SPAN_018 = 'sca018';
  // 'Depth 5 (if from line 12, limit: 4)' - die Meldung von uDeepNesting.
  MSG_DEPTH = 'Depth ';
  // Die Arten der Meldung (TDeepNestingDetector.KindName).
  NEST_KINDS: array[0..4] of string = ('if', 'for', 'while', 'repeat',
    'case');
  KW_IF    = 'if';
  KW_THEN  = 'then';
  KW_BEGIN = 'begin';
  KW_END   = 'end';
  KW_NOT   = 'not';
  KW_FOR   = 'for';
  KW_RESULT = 'result';
  // Hier endet die Suche nach der Routine um die Stelle: UNIT_BOUNDS
  // (uRdxCodeMap, seit der Folgewelle B1 zentral).
  // Im Rumpf gesperrt (Sprungziele, Assembler).
  JUMP_WORDS: array[0..1] of string = ('goto', 'asm');
  // Davor wird ein Name deklariert (Variable, Parameter, Member).
  EXIT_DECL_PREV: array[0..5] of string = ('var', 'const', 'property',
    'procedure', 'function', ',');
  // Rueckwaerts in der Bedingung: hier endete sie, ohne dass ein if kam.
  COND_STOPS: array[0..12] of string = ('begin', 'end', 'do', 'of', 'try',
    'repeat', 'until', 'case', 'while', 'for', 'with', 'finally', 'except');
  // ... und diese stehen nur in einem bedingten Ausdruck darin.
  COND_EXPR_WORDS: array[0..1] of string = ('then', 'else');
  // Routinen mit Rueckgabewert.
  RESULT_HEADS: array[0..1] of string = ('function', 'operator');
  // Inline-Deklarationen, die an ihrem Block haengen.
  INLINE_WORDS: array[0..1] of string = ('var', 'const');
  // Kein einfacher Operand: Operatoren und 'inherited'.
  NOT_OPERAND: array[0..11] of string = ('and', 'or', 'xor', 'not', 'div',
    'mod', 'shl', 'shr', 'in', 'is', 'as', 'inherited');
  GUARD_THEN = ' then Exit;';

type
  // Das letzte if der Routine.
  TIfParts = record
    IfTok    : TRdxToken;
    ThenTok  : TRdxToken;
    BeginTok : TRdxToken;
    EndTok   : TRdxToken;
  end;

// Die Art aus 'Depth d (kind from ...'; '' ohne.
function KindOf(const AMessage: string): string;
var
  p, q : Integer;
begin
  Result := '';
  if Copy(AMessage, 1, Length(MSG_DEPTH)) <> MSG_DEPTH then
    Exit;
  p := Pos('(', AMessage);
  if p = 0 then
    Exit;
  q := p + 1;
  while (q <= Length(AMessage)) and CharInSet(AMessage[q], ['a'..'z']) do
    Inc(q);
  Result := Copy(AMessage, p + 1, q - p - 1);
  if not InList(Result, NEST_KINDS) then
    Result := '';
end;

// Das erste Schluesselwort AKind auf ALine; '' oder der Grund.
function ReportedToken(AMap: TRdxCodeMap; ALine: Integer;
  const AKind: string; out ATok: TRdxToken): string;
var
  T : TRdxToken;
begin
  ATok := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = AKind) and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      ATok := T;
      Exit('');
    end;
    T := After(AMap, T);
  end;
  Result := MsgMovedSuffix(_(R_DN_MOVED, [AKind]));
end;

// Die innerste Routine mit begin..end-Rumpf um AAt mit den Gruenden
// dieser Unit; '' oder der Grund. Die Suche ist der Baustein
// uRdxBlocks.BeginBodyAround (bis zur Hygiene-Welle H1 hier als Kopie
// ausgeschrieben): ein Kopf mit unsicheren Grenzen beendet sie.
function EnclosingRoutine(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): string;
begin
  case BeginBodyAround(AMap, AAt, ARoutine) of
    rbfUnsure: Result := _(R_DN_BOUNDS);
    rbfNone:   Result := _(R_DN_NO_ROUTINE);
  else
    Result := '';
  end;
end;

// Deklariert die Datei einen eigenen Bezeichner 'Exit' (wie
// uRdxGotoExitFix)?
function ExitIsShadowed(AMap: TRdxCodeMap): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'exit');
  while T.Low <> '' do
  begin
    if (T.Low = 'exit')
       and ((After(AMap, T).Low = ':')
            or InList(Before(AMap, T).Low, EXIT_DECL_PREV)) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, 'exit');
  end;
end;

// Was im Rumpf steht, das die Hilfe nicht liest. '' oder der Grund.
function BodyReason(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  if DirectiveBetween(AMap, ARoutine.Body, ARoutine.EndTok.Line,
       ARoutine.EndTok.Col) then
    Exit(_(R_DN_DIRECTIVE));
  P := ARoutine.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, ARoutine.EndTok) do
  begin
    if IsKeywordAfter(T, P) then
    begin
      if InList(T.Low, ROUTINE_WORDS) then
        Exit(_(R_DN_ANON));
      if InList(T.Low, JUMP_WORDS) then
        Exit(_(R_DN_JUMP));
    end;
    P := T;
    T := After(AMap, T);
  end;
  if ExitIsShadowed(AMap) then
    Result := _(R_DN_SHADOW);
end;

// Das Gegenstueck (Oeffner) zum end AEnd, rueckwaerts gezaehlt; Low = ''
// ohne (der Rumpfanfang AStop ist erreicht).
function OpenerOf(AMap: TRdxCodeMap; const AEnd, AStop: TRdxToken): TRdxToken;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  T := Before(AMap, AEnd);
  while TokBefore(AStop, T) do
  begin
    P := Before(AMap, T);
    if IsKeywordAfter(T, P) then
    begin
      if T.Low = KW_END then
        Inc(Depth)
      else if IsEndOpener(T.Low) then
      begin
        if Depth = 0 then
          Exit(T);
        Dec(Depth);
      end;
    end;
    T := P;
  end;
end;

// Das if zum then AThen: rueckwaerts ueber die Bedingung. '' oder der Grund.
function IfOf(AMap: TRdxCodeMap; const AThen, AStop: TRdxToken;
  out AIf: TRdxToken): string;
var
  T, P  : TRdxToken;
  Paren : Integer;
begin
  AIf := Default(TRdxToken);
  Paren := 0;
  T := Before(AMap, AThen);
  while TokBefore(AStop, T) do
  begin
    P := Before(AMap, T);
    // Rueckwaerts oeffnet ein Schliesser die Klammerebene.
    Dec(Paren, ParenDelta(T));
    if (T.Low = ';') or (T.Low = ':=') then
      Exit(_(R_DN_NOT_LAST));
    if IsKeywordAfter(T, P) then
    begin
      if InList(T.Low, COND_EXPR_WORDS) then
        Exit(_(R_DN_COND_EXPR));
      if InList(T.Low, COND_STOPS) then
        Exit(_(R_DN_NOT_LAST));
      if T.Low = KW_IF then
      begin
        // Ein if in Klammern ist ein bedingter Ausdruck.
        if Paren <> 0 then
          Exit(_(R_DN_COND_EXPR));
        AIf := T;
        Exit('');
      end;
    end;
    T := P;
  end;
  Result := _(R_DN_NOT_LAST);
end;

// Die letzte Anweisung der Routine als 'if A then begin B end'. '' oder
// der Grund.
function LastIf(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  out AParts: TIfParts): string;
var
  P, E2, Last : TRdxToken;
begin
  AParts := Default(TIfParts);
  Result := _(R_DN_NOT_LAST);
  P := Before(AMap, ARoutine.EndTok);
  if P.Low = ';' then
    P := Before(AMap, P);
  if (P.Low <> KW_END) or not IsKeywordAfter(P, Before(AMap, P)) then
    Exit;
  AParts.EndTok := P;
  AParts.BeginTok := OpenerOf(AMap, P, ARoutine.Body);
  if AParts.BeginTok.Low <> KW_BEGIN then
    Exit;
  AParts.ThenTok := Before(AMap, AParts.BeginTok);
  if (AParts.ThenTok.Low <> KW_THEN)
     or not IsKeywordAfter(AParts.ThenTok, Before(AMap, AParts.ThenTok)) then
    Exit;
  Result := IfOf(AMap, AParts.ThenTok, ARoutine.Body, AParts.IfTok);
  if Result <> '' then
    Exit;
  if SameTok(After(AMap, AParts.IfTok), AParts.ThenTok) then
    Exit(_(R_DN_NOT_LAST));
  P := Before(AMap, AParts.IfTok);
  if (P.Low <> ';') and not SameTok(P, ARoutine.Body) then
    Exit(_(R_DN_NOT_TOP, [TokText(AMap, P)]));
  // Gegenprobe vorwaerts: die end-Bilanz ab begin schliesst am selben end.
  BlockEnd(AMap, AParts.BeginTok, nil, E2, Last);
  if not SameTok(E2, AParts.EndTok) then
    Exit(_(R_DN_NOT_LAST));
end;

// Setzt eine eigene Anweisung auf oberster Ebene vor AIf Result (bzw. den
// Namen der Funktion)? Nicht hinter then/else/do, nicht in einem Block.
function ResultSetBefore(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AIf: TRdxToken): Boolean;
var
  T, P         : TRdxToken;
  Depth, Paren : Integer;
begin
  Result := False;
  Depth := 0;
  Paren := 0;
  P := ARoutine.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, AIf) do
  begin
    Inc(Paren, ParenDelta(T));
    if IsKeywordAfter(T, P) then
    begin
      if IsEndOpener(T.Low) or (T.Low = 'repeat') then
        Inc(Depth)
      else if (T.Low = KW_END) or (T.Low = 'until') then
        Dec(Depth)
      else if (Depth = 0) and (Paren = 0)
         and ((T.Low = KW_RESULT) or (T.Low = ARoutine.NameTok.Low))
         and (After(AMap, T).Low = ':=')
         and ((P.Low = ';') or SameTok(P, ARoutine.Body)) then
        Exit(True);
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Nur Leerraum auf ALine ab ACol?
function BlankFrom(const ALine: string; ACol: Integer): Boolean;
begin
  Result := SkipBlanks(ALine, ACol) > Length(ALine);
end;

// if, begin und end auf ihren Zeilen, kein Kommentar im Kopf und neben dem
// end, keine Blockzeile in einem Block-Kommentar oder String. '' oder der
// Grund. Einen leeren Block prueft niemand: die gemeldete Stelle liegt
// schon in ihm (GuardClause, R_DN_NOT_INSIDE), und begin steht als letztes,
// end als erstes auf seiner Zeile - die Stelle steht also auf einer
// Blockzeile.
function LayoutReason(AMap: TRdxCodeMap; const AParts: TIfParts): string;
var
  Li, c, First : Integer;
  L            : string;
begin
  Result := '';
  if not FirstOnLine(AMap, AParts.IfTok) or AMap.StartsInside(AParts.IfTok.Line)
     or (AParts.EndTok.Line <= AParts.BeginTok.Line)
     or not FirstOnLine(AMap, AParts.EndTok) then
    Exit(_(R_DN_LAYOUT));
  // Kopf: vom if bis zum Zeilenende hinter begin.
  for Li := AParts.IfTok.Line to AParts.BeginTok.Line do
  begin
    L := AMap.Raw(Li);
    First := 1;
    if Li = AParts.IfTok.Line then
      First := AParts.IfTok.Col;
    if AMap.HasComment(Li, First, Length(L))
       or ((Li > AParts.IfTok.Line) and AMap.StartsInside(Li)) then
      Exit(_(R_DN_COMMENT));
  end;
  if not BlankFrom(AMap.Raw(AParts.BeginTok.Line), AParts.BeginTok.EndCol) then
    Exit(_(R_DN_LAYOUT));
  // end: davor nichts, dahinter hoechstens ';'.
  L := AMap.Raw(AParts.EndTok.Line);
  if AMap.StartsInside(AParts.EndTok.Line) then
    Exit(_(R_DN_LAYOUT));
  c := SkipBlanks(L, AParts.EndTok.EndCol);
  if (c <= Length(L)) and (L[c] = ';') and AMap.IsCode(AParts.EndTok.Line, c) then
    c := SkipBlanks(L, c + 1);
  if c <= Length(L) then
  begin
    if AMap.HasComment(AParts.EndTok.Line, c, Length(L)) then
      Exit(_(R_DN_COMMENT));
    Exit(_(R_DN_LAYOUT));
  end;
  // Der Block: keine Zeile in einem Block-Kommentar oder String.
  for Li := AParts.BeginTok.Line + 1 to AParts.EndTok.Line - 1 do
    if AMap.StartsInside(Li) then
      Exit(_(R_DN_MULTILINE));
end;

// Ein Inline-var/const auf oberster Ebene des Blocks? '' oder der Grund.
function InlineReason(AMap: TRdxCodeMap; const AParts: TIfParts): string;
var
  T, P         : TRdxToken;
  Depth, Paren : Integer;
begin
  Result := '';
  Depth := 0;
  Paren := 0;
  P := AParts.BeginTok;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, AParts.EndTok) do
  begin
    Inc(Paren, ParenDelta(T));
    if IsKeywordAfter(T, P) then
    begin
      if IsEndOpener(T.Low) or (T.Low = 'repeat') then
        Inc(Depth)
      else if (T.Low = KW_END) or (T.Low = 'until') then
        Dec(Depth)
      else if (Depth = 0) and (Paren = 0) and InList(T.Low, INLINE_WORDS)
         and (P.Low <> KW_FOR) then
        Exit(_(R_DN_INLINE));
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// Der Text zwischen dem Ende von AFrom und dem Anfang von ATo, ohne
// Leerraum aussen (Zeilen mit #10).
function TextBetween(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;
begin
  Result := Trim(RangeText(AMap, TRefactorSpan.Make(SPAN_018, AFrom.Line,
    AFrom.EndCol, ATo.Line, ATo.Col)));
end;

// Ist ab AFrom bis vor AStop ein einfacher Operand - ein Name oder eine
// Klammer, dahinter nur '.Name', '(..)', '[..]' und '^'?
function IsOperand(AMap: TRdxCodeMap; const AFrom, AStop: TRdxToken): Boolean;
var
  T, W : TRdxToken;
begin
  T := AFrom;
  if T.Low = '(' then
    T := AfterClose(AMap, T)
  else if T.IsWord and not InList(T.Low, NOT_OPERAND) then
    T := After(AMap, T)
  else
    Exit(False);
  while (T.Low <> '') and TokBefore(T, AStop) do
  begin
    if T.Low = '.' then
    begin
      W := After(AMap, T);
      if not W.IsWord then
        Exit(False);
      T := After(AMap, W);
    end
    else if (T.Low = '(') or (T.Low = '[') then
      T := AfterClose(AMap, T)
    else if T.Low = '^' then
      T := After(AMap, T)
    else
      Exit(False);
  end;
  Result := SameTok(T, AStop);
end;

// Die verneinte Bedingung (s. Kopf, NEGATION).
function Negated(AMap: TRdxCodeMap; const AParts: TIfParts): string;
var
  First, Rest : TRdxToken;
begin
  First := After(AMap, AParts.IfTok);
  Rest := After(AMap, First);
  if (First.Low = KW_NOT) and IsKeywordAfter(First, AParts.IfTok)
     and IsOperand(AMap, Rest, AParts.ThenTok) then
    Exit(TextBetween(AMap, First, AParts.ThenTok));
  Result := TextBetween(AMap, AParts.IfTok, AParts.ThenTok);
  if IsOperand(AMap, First, AParts.ThenTok) then
    Result := KW_NOT + ' ' + Result
  else
    Result := KW_NOT + ' (' + Result + ')';
end;

// Die Blockzeilen eine Stufe flacher: auf die Einrueckung des if, mit #10
// verbunden. Die Stufe nimmt die erste Blockzeile, die nicht mit einem
// Kommentar beginnt. '' oder der Grund.
function DedentedBlock(AMap: TRdxCodeMap; const AParts: TIfParts;
  out ABody: string): string;
var
  SB                 : TStringBuilder;
  Li, Col            : Integer;
  L, Tr, Deep, Pref  : string;
begin
  Result := '';
  ABody := '';
  Tr := IndentOf(AMap.Raw(AParts.IfTok.Line));
  Pref := '';
  for Li := AParts.BeginTok.Line + 1 to AParts.EndTok.Line - 1 do
  begin
    L := AMap.Raw(Li);
    Col := SkipBlanks(L, 1);
    if (Col > Length(L)) or (AMap.ClassAt(Li, Col) = 'k') then
      Continue;
    Deep := IndentOf(L);
    if Copy(Deep, 1, Length(Tr)) <> Tr then
      Exit(_(R_DN_INDENT, [Li]));
    Pref := Deep;
    Break;
  end;
  if Pref = '' then
    Pref := Tr;
  SB := TStringBuilder.Create;
  try
    for Li := AParts.BeginTok.Line + 1 to AParts.EndTok.Line - 1 do
    begin
      L := AMap.Raw(Li);
      if SkipBlanks(L, 1) <= Length(L) then
      begin
        if Copy(L, 1, Length(Pref)) <> Pref then
          Exit(_(R_DN_INDENT, [Li]));
        L := Tr + Copy(L, Length(Pref) + 1, MaxInt);
      end;
      if Li > AParts.BeginTok.Line + 1 then
        SB.Append(#10);
      SB.Append(L);
    end;
    ABody := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TRdxDeepNestingFix }

class function TRdxDeepNestingFix.GuardClause(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Kind    : string;
  Body    : string;
  Report  : TRdxToken;
  Routine : TRdxRoutine;
  Parts   : TIfParts;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Body := '';
  Report := Default(TRdxToken);
  Routine := Default(TRdxRoutine);
  Parts := Default(TIfParts);
  Kind := KindOf(AMessage);
  if Kind = '' then
  begin
    AReason := _(R_DN_MESSAGE);
    Exit;
  end;
  AReason := ReportedToken(AMap, ALine, Kind, Report);
  if AReason = '' then
    AReason := EnclosingRoutine(AMap, Report, Routine);
  if AReason = '' then
    AReason := BodyReason(AMap, Routine);
  if AReason = '' then
    AReason := LastIf(AMap, Routine, Parts);
  if (AReason = '') and not (TokBefore(Parts.BeginTok, Report)
                             and TokBefore(Report, Parts.EndTok)) then
    AReason := _(R_DN_NOT_INSIDE);
  if (AReason = '') and InList(Routine.Keyword.Low, RESULT_HEADS)
     and not ResultSetBefore(AMap, Routine, Parts.IfTok) then
    AReason := _(R_DN_RESULT);
  if AReason = '' then
    AReason := LayoutReason(AMap, Parts);
  if AReason = '' then
    AReason := InlineReason(AMap, Parts);
  if AReason = '' then
    AReason := DedentedBlock(AMap, Parts, Body);
  if AReason <> '' then
    Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_018, Parts.IfTok.Line, Parts.IfTok.Col,
    Parts.EndTok.Line, Length(AMap.Raw(Parts.EndTok.Line)) + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := KW_IF + ' ' + Negated(AMap, Parts) + GUARD_THEN + #10 + Body;
  Result := True;
end;

end.
