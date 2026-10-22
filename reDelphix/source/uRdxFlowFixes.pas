unit uRdxFlowFixes;

// reDelphix - Quick-Fixes an ganzen Anweisungen, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Recherche_2026-10-11, Charge H2 "Bedingungen
// und Spruenge", Baustein "ganze Anweisung"):
//   SCA098 RedundantConditional: 'if C then X := True else X := False'
//          -> 'X := C', Gegenrichtung 'X := not C' - Klammern nur um ein
//          zusammengesetztes C; Zeilenumbrueche in C bleiben.
//   SCA080 RedundantJump: das ueberfluessige 'Exit;' bzw. 'Continue;'
//          loeschen (steht es allein auf der Zeile, die ganze Zeile); hinter
//          dem else eines if faellt 'else Exit' weg.
//   SCA047 SelfAssignment: 'X := X;' loeschen (allein auf der Zeile: die
//          ganze Zeile).
// Alle drei sind bedeutungsgleich. Was nur der Quellstellen-Dienst weiss -
// X als Boolean (SCA098) bzw. als Variable (SCA047) deklariert, ein
// with-Block um die Zeile -, prueft der Aufrufer (TRdxFixRunner).
//
// SCA080 UND FINALLY: ein Sprung aus einem finally heraus verwirft eine
// laufende Exception, ihn zu loeschen liesse sie wieder durch - deshalb
// liess die Charge der Zeilen-Hilfen (f7370425) SCA080 aus. Mikroprobe
// 2026-10-12: Delphi 12 (dcc32: E2126 'Cannot BREAK, CONTINUE or EXIT out
// of a FINALLY clause') und FPC 3.2.2 (Fehler 06040 'Control flow
// statements are not allowed in a finally block') uebersetzen ihn nicht,
// in uebersetzbarem Code kommt er also nicht vor. Die Hilfe lehnt ihn
// trotzdem ab: Code unter einer inaktiven Direktive sieht kein Compiler.
//
// SCA150 BoolAlwaysTrue bekommt KEINE Hilfe (in Charge H2 optional):
//   (1) die Meldung nennt weder Spalte noch Ausdruck;
//   (2) im Realwelt-Korpus gibt es keinen Fund, im Lazarus-Korpus einen -
//       der Korpus-Harness, das Mass jeder Charge, kann sie nicht messen;
//   (3) die bedeutungsgleiche Variante (a) 'if Length(s) >= 0 then A else
//       B' -> 'A' bzw. 'if Length(s) < 0 then A;' -> weg loescht einen
//       ganzen Zweig: Zweigende und haengendes else brauchen den Baustein
//       Blockpaarung, den H2 nicht bringt; und 'Length' muss die
//       RTL-Funktion sein - eine Methode Length aus einer anderen Unit ist
//       im Text nicht auszuschliessen (dasselbe Restrisiko wie bei
//       SCA080/Exit, hier aber ohne Korpus, es zu wiegen);
//   (4) Variante (b) '>= 0' -> '> 0' raet die Absicht (gekennzeichnet,
//       ChangesBehavior) ohne einen einzigen Beleg.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

type
  // Ergebnis der Planer: die Ersetzung und was der Aufrufer mit dem
  // Quellstellen-Dienst noch pruefen muss.
  TRdxFlowPlan = record
    Edit         : TRdxEdit;
    // Name fuer Menuetext und Pruefung - schon aus der Meldung, auch wenn
    // der Planer ablehnt; nach einem Treffer wie im Quelltext. SCA098: das
    // Ziel X als EIN Bezeichner ('FActive' - so meldet es uRedundant-
    // Conditional, und CondAt vergleicht ein Wort); SCA047: auch ein Pfad
    // ('Pt.Y'); SCA080: Exit bzw. Continue. Bis zur Review Woche G07-12
    // nannte der Kommentar 'Pt.Y' auch fuer SCA098.
    Target       : string;
    // SCA098: 'then False else True' - der neue Wert ist 'not C'.
    Negated      : Boolean;
    // SCA098: C ist der Form nach Boolean - ein Vergleich (=, <>, <, >,
    // <=, >=, in, is) auf oberster Ebene (das Ergebnis ist Boolean, auch
    // bei Variant-Operanden) oder and/or/xor/not ueber Teilen, die selbst
    // so gebaut sind, True/False oder blosse Bezeichner sind -
    // vorausgesetzt, jeder Bezeichner in CondIdents ist Boolean (das
    // prueft der Aufrufer). Ein Aufruf, ein Pfad oder Arithmetik als
    // Operand: False.
    CondBoolean  : Boolean;
    CondIdents   : TArray<string>;
  end;

  // Die Planer an ganzen Anweisungen (SCA098, SCA080, SCA047): reine
  // Textlogik auf der Code-Sicht. Was nur der Quellstellen-Dienst weiss -
  // X als Boolean bzw. Variable bewiesen, ein with-Block um die Zeile -,
  // prueft der Aufrufer (TRdxFixRunner) am Plan (Target, CondIdents).
  TRdxFlowFixes = class
  public
    // SCA098: das eine 'if C then X := W1 else X := W2' auf ALine - X, W1
    // und W2 wie in der Meldung ('`if Cond then X := True else X := False`
    // can be simplified ...') - wird 'X := C' bzw. (W1 = False)
    // 'X := not C'. Keine Hilfe bei einem Kommentar oder einer Direktive in
    // der Anweisung, einem bedingten Ausdruck, begin..end-Zweigen, einem
    // Ausdruck hinter W2 und zwei solchen Anweisungen auf der Zeile (die
    // Meldung nennt keine Spalte).
    class function RedundantConditional(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxFlowPlan;
      out AReason: string): Boolean; static;

    // SCA080: das 'exit;' bzw. 'continue;' der Meldung ('`exit;` directly
    // before `end` ...') auf ALine loeschen. Gegenprobe wie uRedundantJump:
    // dahinter nur die end-Kette bis zum Routinenende, 'end.' oder 'until';
    // Exit nicht in einer Schleife. Keine Hilfe als einzige Anweisung
    // hinter then/do, eines case-Zweigs, eines else von case/except oder
    // eines Blocks (es bliebe 'if C then' bzw. ein leerer Block stehen),
    // bei mehreren Sprunganweisungen auf der Zeile, einem Kommentar auf
    // der Zeile, einer eigenen Routine Exit/Continue in der Unit und im
    // finally-Teil. Hinter dem else eines if faellt 'else Exit' weg.
    class function RedundantJump(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxFlowPlan;
      out AReason: string): Boolean; static;

    // SCA047: das eine 'X := X' auf ALine (X wie in der Meldung
    // 'Self-assignment: X := X (...)', auch Pfade wie 'Pt.Y' und 'R^.F')
    // loeschen. Keine Hilfe fuer Result und den Namen einer Routine der
    // Unit (rechts koennte ein Aufruf stehen), bei einem 'class operator
    // Assign' in der Unit, einem Kommentar auf der Zeile, als einzige
    // Anweisung hinter then/else/do, eines case-Zweigs oder eines Blocks
    // und ueber mehrere Zeilen.
    class function SelfAssignment(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxFlowPlan;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  // Nur die Schnittstelle braucht uRdxBufferMath/uRdxCodeMap im interface;
  // die Fragen an die ganze Datei (DeclaresRoutine, NextTokenOnLineWith) und
  // die Bereichs-Helfer kommen seit Charge B2S-a aus uRdxCodeMap - bis
  // dahin band die Unit dafuer uRdxSimpleFixes ein (Review R3-07).
  // StartsStatement und ElseBelongsToIf ebenso seit der Folgewelle des
  // Wochen-Reviews (G07-13) - bis dahin aus uRdxStructFixes.
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _() und die gemeinsamen Texte (Msg...): Gruende in der
                     // reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_098 = 'sca098';
  SPAN_080 = 'sca080';
  SPAN_047 = 'sca047';
  // Hier endet eine Anweisung ohne ';': STATEMENT_STOPS (uRdxCodeMap; bis
  // zur Folgewelle des Wochen-Reviews hier als STMT_STOPS).
  BOOL_WORDS: array[0..1] of string = ('true', 'false');
  // Steht einer davon auf oberster Ebene von C, ist C Boolean.
  COMPARE_OPS: array[0..7] of string = ('=', '<>', '<', '>', '<=', '>=',
    'in', 'is');
  // Woerter, die einen Ausdruck zusammensetzen - kein Operand.
  WORD_OPS: array[0..11] of string = ('and', 'or', 'xor', 'not', 'div',
    'mod', 'shl', 'shr', 'in', 'is', 'as', 'inherited');
  // Verknuepfen Boolean-Teile (BoolForm); MAX_BOOL_LEVEL begrenzt die
  // Klammertiefe der Rekursion.
  BOOL_OPS: array[0..2] of string = ('and', 'or', 'xor');
  MAX_BOOL_LEVEL = 16;
  // Anhaenge eines Operanden: Aufruf, Index, Dereferenz.
  OPERAND_SUFFIXES: array[0..2] of string = ('(', '[', '^');
  // Bis hier sucht ThenOf das then - dahinter beginnt keine Bedingung mehr.
  NOT_IN_CONDITION: array[0..3] of string = ('begin', 'end', 'do', 'of');
  JUMP_WORDS: array[0..2] of string = ('exit', 'continue', 'break');
  // SCA080: hinter einer end-Kette aus mindestens zwei end beginnt hier
  // etwas Neues (wie uRedundantJump).
  CHAIN_TERMS: array[0..11] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'class', 'initialization',
    'finalization', 'implementation', 'exports', 'resourcestring',
    'threadvar');
  // Routinen- und Abschnittsgrenzen der Rueckwaerts-Suchen (wie
  // uRedundantJump.JumpInsideLoop).
  ROUTINE_BOUNDS: array[0..11] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'initialization',
    'finalization', 'implementation', 'interface', 'unit', 'program',
    'library');
  // Vor der ersten Anweisung einer Anweisungsliste.
  LIST_OPENERS: array[0..7] of string = ('begin', 'try', 'finally',
    'except', 'repeat', 'initialization', 'finalization', 'otherwise');
  // Das Ende einer Anweisungsliste (LIST_ENDS) und die Zweige ohne begin
  // (BRANCH_WORDS) stehen in uRdxCodeMap.
  // Davor beginnt kein Pfad ('A.B', 'R^.F', '&X', '@X').
  PATH_JOINERS: array[0..3] of string = ('.', '^', '&', '@');
  KEY_SELF   = 'Self-assignment: ';
  KEY_ASSIGN = ' := ';
  // msgid (E29) fuer SCA080 und SCA047 - %s = MsgDecideByHand; der Trenner
  // '; ' bleibt im Satz (deutsch bisher '...; von Hand entscheiden').
  R_LINE_COMMENT = 'comment on the line - it may explain the place; %s';

type
  // Eine ganze Anweisung (DeleteEdit): ihr erstes Token, das Token davor
  // und dahinter, Zeile und Spalte hinter ihrem letzten Zeichen (mit ';').
  TRdxStmtSite = record
    First   : TRdxToken;
    Prev    : TRdxToken;
    Next    : TRdxToken;
    EndLine : Integer;
    EndCol  : Integer;
  end;

  // SCA098: die Token einer Fundstelle - if, then, Ziel X, die Werte W1
  // und W2 und das Token dahinter.
  TRdxCondSite = record
    IfTok     : TRdxToken;
    ThenTok   : TRdxToken;
    Target    : TRdxToken;   // X im then-Zweig
    FirstVal  : TRdxToken;   // W1
    SecondVal : TRdxToken;   // W2
    Stop      : TRdxToken;   // das Token hinter W2
  end;

  // SCA098: Token ab First bis vor Stop (C oder ein Teil davon).
  TRdxTokRange = record
    First : TRdxToken;
    Stop  : TRdxToken;
  end;

  // SCA098: Ziel (wie in der Meldung) und Werte (klein) aus der Meldung.
  TRdxCondMsg = record
    Target : string;
    First  : string;
    Second : string;
  end;

  // SCA098: IsOperand - offene Klammern und ob ein Operand(-Teil)
  // folgen muss (am Anfang und hinter '.').
  TRdxOperandScan = record
    Depth : Integer;
    Want  : Boolean;
    function Step(const T: TRdxToken): Boolean;
  end;

  // SCA080: Rueckwaerts-Suche nach einer Schleife um den Sprung (wie
  // uRedundantJump.JumpInsideLoop): ob auf der aktuellen Ebene schon ein
  // ';' gekreuzt wurde - die offenen Bloecke zaehlt TRdxBackBalance
  // (uRdxCodeMap; bis zur Folgewelle des Wochen-Reviews das Feld Depth).
  TRdxLoopScan = record
    SawSemi : Boolean;
    function StepWord(const T: TRdxToken; ADepth: Integer): TRdxStep;
  end;

{ ---- gemeinsam ---- }

// Kommentar oder Direktive irgendwo auf ALine - auf der GANZEN Zeile, auch
// vor oder hinter der Anweisung? Anders als CommentInRange (nur der
// Bereich, den die Ersetzung ueberschreibt, zeichengenau): SCA080 und
// SCA047 loeschen eine Anweisung, die ein Kommentar daneben vielleicht
// erklaert (R_LINE_COMMENT) - der Bereich allein saehe ihn nicht.
function LineHasComment(AMap: TRdxCodeMap; ALine: Integer): Boolean;
begin
  Result := AMap.HasComment(ALine, 1, Length(AMap.Raw(ALine)));
end;

// Was steht vor der Anweisung (APrev) und dahinter (ANext)? '' in einer
// Anweisungsliste - hinter ';' oder als erste einer Liste, hinter der noch
// eine folgt; sonst der Grund (einziger Zweig, case-Zweig, einzige
// Anweisung eines Blocks: es bliebe 'if C then' bzw. ein leerer Block).
function ContextReason(const APrev, ANext: TRdxToken): string;
begin
  Result := '';
  if APrev.Low = ';' then Exit;
  // Der Zweig ist eine eigene msgid, nicht MsgOnlyStatementEmptyBlock: der
  // Wortlaut ('Zweig stehen', ohne SCA077) bleibt (c_groups Abschnitt 3).
  if InList(APrev.Low, BRANCH_WORDS) then
    Result := _('only statement after %s - an empty branch would remain',
      [APrev.Low])
  else if APrev.Low = ':' then
    Result := _('only statement of a case branch or after a label')
  else if not InList(APrev.Low, LIST_OPENERS) then
    Result := MsgUnclearStatementOwner(APrev.Low)
  else if (ANext.Low = '') or InList(ANext.Low, LIST_ENDS) then
    Result := MsgOnlyStatementEmptyBlock(APrev.Low);
end;

// Die Anweisung ASite loeschen: steht sie allein auf ihrer Zeile, die
// ganze Zeile; steht davor auf derselben Zeile ASite.Prev, ab dessen Ende
// (der Leerraum davor geht mit); sonst bis vor das naechste Token. ''
// oder der Grund.
function DeleteEdit(AMap: TRdxCodeMap; const ASite: TRdxStmtSite;
  const ARole: string; out AEdit: TRdxEdit): string;
var
  Li, From, Upto : Integer;
  L              : string;
begin
  Result := '';
  AEdit := Default(TRdxEdit);
  Li := ASite.First.Line;
  if ASite.EndLine <> Li then
    Exit(_('the statement spans several lines'));
  L := AMap.Raw(Li);
  if (SkipBlanks(L, 1) = ASite.First.Col)
     and (SkipBlanks(L, ASite.EndCol) > Length(L))
     and (Li < AMap.LineCount) then
  begin
    AEdit.Span := TRefactorSpan.Make(ARole, Li, 1, Li + 1, 1);
    AEdit.Expected := L + #10;
    Exit;
  end;
  From := ASite.First.Col;
  Upto := ASite.EndCol;
  if ASite.Prev.Line = Li then
    From := ASite.Prev.EndCol
  else if ASite.Next.Line = Li then
    Upto := ASite.Next.Col;
  AEdit.Span := TRefactorSpan.Make(ARole, Li, From, Li, Upto);
  AEdit.Expected := Copy(L, From, Upto - From);
end;

{ ---- SCA098 ---- }

// X, W1 und W2 aus '`if Cond then X := True else X := False` can be ...'.
function CondMessageOf(const AMessage: string; out AMsg: TRdxCondMsg): Boolean;
var
  P, Q, R, S, E : Integer;
begin
  AMsg := Default(TRdxCondMsg);
  P := Pos(' then ', AMessage);
  Q := Pos(KEY_ASSIGN, AMessage, P + 1);
  R := Pos(' else ', AMessage, Q + 1);
  S := Pos(KEY_ASSIGN, AMessage, R + 1);
  E := Pos('`', AMessage, S + 1);
  if (P = 0) or (Q = 0) or (R = 0) or (S = 0) or (E = 0) then
    Exit(False);
  AMsg.Target := Copy(AMessage, P + 6, Q - P - 6);
  AMsg.First := LowerCase(Copy(AMessage, Q + 4, R - Q - 4));
  AMsg.Second := LowerCase(Copy(AMessage, S + 4, E - S - 4));
  Result := (AMsg.Target <> '') and (AMsg.First <> AMsg.Second)
    and InList(AMsg.First, BOOL_WORDS) and InList(AMsg.Second, BOOL_WORDS);
end;

// Ab dem if das then der Bedingung (ausserhalb von Klammern). False bei
// ';', einem Blockwort oder dem Dateiende davor.
function ThenOf(AMap: TRdxCodeMap; const AIf: TRdxToken;
  out AThen: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  AThen := Default(TRdxToken);
  Depth := 0;
  T := After(AMap, AIf);
  while (T.Low <> '') and (T.Low <> ';') do
  begin
    Inc(Depth, ParenDelta(T));
    if (Depth = 0) and (T.Low = 'then') then
    begin
      AThen := T;
      Exit(True);
    end;
    if (Depth = 0) and InList(T.Low, NOT_IN_CONDITION) then
      Exit;
    T := After(AMap, T);
  end;
end;

// Steht an T (ein if) 'if C then X := W1 else X := W2' mit X, W1 und W2
// aus der Meldung? ASite traegt die Token; ob hinter W2 die Anweisung
// endet, prueft CondReason.
function CondAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AMsg: TRdxCondMsg; out ASite: TRdxCondSite): Boolean;
var
  Asg1, ElseTok, Target2, Asg2 : TRdxToken;
begin
  Result := False;
  ASite := Default(TRdxCondSite);
  if (T.Low <> 'if') or not IsKeywordAfter(T, APrev)
     or not ThenOf(AMap, T, ASite.ThenTok) then
    Exit;
  ASite.IfTok := T;
  ASite.Target := After(AMap, ASite.ThenTok);
  Asg1 := After(AMap, ASite.Target);
  ASite.FirstVal := After(AMap, Asg1);
  ElseTok := After(AMap, ASite.FirstVal);
  Target2 := After(AMap, ElseTok);
  Asg2 := After(AMap, Target2);
  ASite.SecondVal := After(AMap, Asg2);
  ASite.Stop := After(AMap, ASite.SecondVal);
  Result := ASite.Target.IsWord and SameText(ASite.Target.Low, AMsg.Target)
    and (Asg1.Low = ':=') and (ASite.FirstVal.Low = AMsg.First)
    and (ElseTok.Low = 'else') and (Target2.Low = ASite.Target.Low)
    and (Asg2.Low = ':=') and (ASite.SecondVal.Low = AMsg.Second);
end;

// Das eine Muster der Meldung auf ALine. '' oder der Grund.
function CondOn(AMap: TRdxCodeMap; ALine: Integer; const AMsg: TRdxCondMsg;
  out ASite: TRdxCondSite): string;
var
  T, Prev : TRdxToken;
  S       : TRdxCondSite;
  n       : Integer;
begin
  Result := '';
  ASite := Default(TRdxCondSite);
  n := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if CondAt(AMap, T, Prev, AMsg, S) then
    begin
      Inc(n);
      ASite := S;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  if n = 0 then
    Result := MsgMovedSuffix(_('no "if .. then %s := .. else %s := .." on '
      + 'the reported line', [AMsg.Target, AMsg.Target]))
  else if n > 1 then
    Result := _('line %d carries %d such if statements - ambiguous (the '
      + 'message names no column)', [ALine, n]);
end;

// Endet die Anweisung hinter W2, steht nichts zwischen if und W2, was
// verloren ginge, und ist das if eine Anweisung? '' oder der Grund.
function CondReason(AMap: TRdxCodeMap; const ASite: TRdxCondSite): string;
var
  S : TRdxToken;
begin
  Result := '';
  S := ASite.Stop;
  if (S.Low <> ';') and (S.Low <> '') and not InList(S.Low, STATEMENT_STOPS) then
    Exit(_('the expression continues after "%s" - not a plain if..else',
      [ASite.SecondVal.Low]));
  if CommentInRange(AMap, TRefactorSpan.Make(SPAN_098, ASite.IfTok.Line,
       ASite.IfTok.Col, ASite.SecondVal.Line, ASite.SecondVal.EndCol)) then
    Exit(_('comment or directive in the statement - it would be lost'));
  if SameTok(After(AMap, ASite.IfTok), ASite.ThenTok) then
    Exit(_('empty condition'));
  if not StartsStatement(AMap, ASite.IfTok) then
    Result := _('the if is inside an expression (conditional expression, '
      + 'Delphi 13) - not a statement');
end;

// Der Text von hinter AFrom (das if, beim gestrichenen 'not' dieses) bis
// vor das then - mit Strings und Zeilenumbruechen.
function CondText(AMap: TRdxCodeMap; const AFrom, AThen: TRdxToken): string;
var
  L1, C1, L2, C2 : Integer;
begin
  Result := '';
  if FirstCharAfter(AMap, AFrom, L1, C1)
     and LastCharBefore(AMap, AThen, L2, C2) then
    Result := RangeText(AMap, TRefactorSpan.Make(SPAN_098, L1, C1, L2,
      C2 + 1));
end;

{ TRdxOperandScan }

// Ein Token von IsOperand: in Klammern zaehlt nur die Tiefe; sonst
// False, wenn das Stueck mit T zusammengesetzt ist.
function TRdxOperandScan.Step(const T: TRdxToken): Boolean;
begin
  Result := True;
  if Depth > 0 then
  begin
    Inc(Depth, ParenDelta(T));
    Exit;
  end;
  if Want then
    Result := (T.Low = '(') or (T.IsWord and not InList(T.Low, WORD_OPS))
  else if T.Low <> '.' then
    Result := InList(T.Low, OPERAND_SUFFIXES);
  Want := T.Low = '.';
  if ParenDelta(T) > 0 then
    Inc(Depth);
end;

// Sind die Token ab AFirst bis vor AThen ein einzelner Operand - ein
// Bezeichnerpfad mit Aufruf-, Index- oder '^'-Anhaengen oder ein ganzer
// Klammerausdruck? Dann bindet 'not' an das ganze Stueck, Klammern braucht
// es nicht. Leer: False.
function IsOperand(AMap: TRdxCodeMap; const AFirst, AThen: TRdxToken): Boolean;
var
  T    : TRdxToken;
  Scan : TRdxOperandScan;
begin
  Scan := Default(TRdxOperandScan);
  Scan.Want := True;
  T := AFirst;
  while (T.Low <> '') and not SameTok(T, AThen) do
  begin
    if not Scan.Step(T) then
      Exit(False);
    T := After(AMap, T);
  end;
  Result := not Scan.Want;
end;

// Steht ein Vergleich auf oberster Ebene des Bereichs (ausserhalb von
// Klammern)?
function RangeCompares(AMap: TRdxCodeMap; const ARange: TRdxTokRange): Boolean;
var
  T, P  : TRdxToken;
  Depth : Integer;
begin
  Result := False;
  Depth := 0;
  P := Before(AMap, ARange.First);
  T := ARange.First;
  while (T.Low <> '') and not SameTok(T, ARange.Stop) do
  begin
    Inc(Depth, ParenDelta(T));
    if (Depth = 0) and InList(T.Low, COMPARE_OPS)
       and (not T.IsWord or IsKeywordAfter(T, P)) then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

function BoolForm(AMap: TRdxCodeMap; const ARange: TRdxTokRange;
  var AIdents: TArray<string>; ALevel: Integer): Boolean; forward;

// Ein Teil ohne and/or/xor auf oberster Ebene: 'not'* vor True/False,
// einem blossen Bezeichner (nach AIdents) oder einem ganzen
// Klammerausdruck, der selbst der Form nach Boolean ist.
function PartIsBool(AMap: TRdxCodeMap; const ARange: TRdxTokRange;
  var AIdents: TArray<string>; ALevel: Integer): Boolean;
var
  T, Close : TRdxToken;
  Inner    : TRdxTokRange;
begin
  T := ARange.First;
  while T.Low = 'not' do
    T := After(AMap, T);
  if SameTok(T, ARange.Stop) or InList(T.Low, WORD_OPS) then
    Exit(False);
  if T.IsWord and SameTok(After(AMap, T), ARange.Stop) then
  begin
    if not InList(T.Low, BOOL_WORDS) then
    begin
      SetLength(AIdents, Length(AIdents) + 1);
      AIdents[High(AIdents)] := Copy(AMap.Raw(T.Line), T.Col, T.Len);
    end;
    Exit(True);
  end;
  if T.Low <> '(' then
    Exit(False);
  Close := MatchClose(AMap, T);
  if (Close.Low = '') or not SameTok(After(AMap, Close), ARange.Stop) then
    Exit(False);
  Inner.First := After(AMap, T);
  Inner.Stop := Close;
  Result := (ALevel < MAX_BOOL_LEVEL)
    and BoolForm(AMap, Inner, AIdents, ALevel + 1);
end;

// Ist der Bereich der Form nach Boolean (s. TRdxFlowPlan.CondBoolean)?
// Bezeichner, deren Typ das entscheidet, kommen nach AIdents.
function BoolForm(AMap: TRdxCodeMap; const ARange: TRdxTokRange;
  var AIdents: TArray<string>; ALevel: Integer): Boolean;
var
  T     : TRdxToken;
  Part  : TRdxTokRange;
  Depth : Integer;
begin
  if RangeCompares(AMap, ARange) then
    Exit(True);
  Depth := 0;
  Part.First := ARange.First;
  T := ARange.First;
  while (T.Low <> '') and not SameTok(T, ARange.Stop) do
  begin
    Inc(Depth, ParenDelta(T));
    if (Depth = 0) and InList(T.Low, BOOL_OPS) then
    begin
      Part.Stop := T;
      if not PartIsBool(AMap, Part, AIdents, ALevel) then
        Exit(False);
      Part.First := After(AMap, T);
    end;
    T := After(AMap, T);
  end;
  Part.Stop := ARange.Stop;
  Result := PartIsBool(AMap, Part, AIdents, ALevel);
end;

// Die Ersetzung: 'if .. W2' -> 'X := C' bzw. 'X := not C'. Ziel und
// Zuweisung wie im then-Zweig geschrieben ('Result:=').
procedure CondEdit(AMap: TRdxCodeMap; const ASite: TRdxCondSite;
  var APlan: TRdxFlowPlan);
var
  L, Prefix, Cond : string;
  C               : TRdxTokRange;
begin
  L := AMap.Raw(ASite.Target.Line);
  APlan.Target := Copy(L, ASite.Target.Col, ASite.Target.Len);
  if ASite.FirstVal.Line = ASite.Target.Line then
    Prefix := Copy(L, ASite.Target.Col, ASite.FirstVal.Col - ASite.Target.Col)
  else
    Prefix := APlan.Target + KEY_ASSIGN;
  Cond := CondText(AMap, ASite.IfTok, ASite.ThenTok);
  APlan.Negated := ASite.FirstVal.Low = 'false';
  C.First := After(AMap, ASite.IfTok);
  C.Stop := ASite.ThenTok;
  APlan.CondIdents := nil;
  APlan.CondBoolean := BoolForm(AMap, C, APlan.CondIdents, 0);
  // Gegenrichtung: ist C 'not R' mit einem Operanden R, faellt das not weg
  // ('if not Ready then Done := False else Done := True' -> 'Done :=
  // Ready'); bis zur Review Woche G07-15 hiess es 'not (not Ready)'. 'not
  // A = B' ist '(not A) = B' - R waere kein Operand, es bleibt beim
  // geklammerten 'not (..)'.
  if APlan.Negated and (C.First.Low = 'not')
     and IsOperand(AMap, After(AMap, C.First), ASite.ThenTok) then
    Cond := CondText(AMap, C.First, ASite.ThenTok)
  else if APlan.Negated then
  begin
    if not IsOperand(AMap, C.First, ASite.ThenTok) then
      Cond := '(' + Cond + ')';
    Cond := 'not ' + Cond;
  end;
  APlan.Edit.Span := TRefactorSpan.Make(SPAN_098, ASite.IfTok.Line,
    ASite.IfTok.Col, ASite.SecondVal.Line, ASite.SecondVal.EndCol);
  APlan.Edit.Expected := RangeText(AMap, APlan.Edit.Span);
  APlan.Edit.NewText := Prefix + Cond;
end;

class function TRdxFlowFixes.RedundantConditional(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxFlowPlan;
  out AReason: string): Boolean;
var
  Msg  : TRdxCondMsg;
  Site : TRdxCondSite;
begin
  APlan := Default(TRdxFlowPlan);
  Site := Default(TRdxCondSite);
  if not CondMessageOf(AMessage, Msg) then
    AReason := _('the message has no target or values')
  else
  begin
    APlan.Target := Msg.Target;
    AReason := CondOn(AMap, ALine, Msg, Site);
  end;
  if AReason = '' then
    AReason := CondReason(AMap, Site);
  if AReason = '' then
    CondEdit(AMap, Site, APlan);
  Result := AReason = '';
end;

{ ---- SCA080 ---- }

// 'exit' bzw. 'continue' aus '`exit;` directly before `end` ...'; ''
// ohne diese Form.
function JumpOf(const AMessage: string): string;
var
  Q : Integer;
begin
  Result := '';
  Q := Pos(';`', AMessage);
  if (Copy(AMessage, 1, 1) = '`') and (Q > 2) then
    Result := LowerCase(Copy(AMessage, 2, Q - 2));
  if not InList(Result, ['exit', 'continue']) then
    Result := '';
end;

// Der eine Sprung AWord mit ';' dahinter auf ALine; jede weitere
// Sprunganweisung (Exit, Continue, Break) auf der Zeile macht ihn
// mehrdeutig. '' oder der Grund.
function JumpOn(AMap: TRdxCodeMap; ALine: Integer; const AWord: string;
  out AJump, ASemi: TRdxToken): string;
var
  T, Prev, N   : TRdxToken;
  Jumps, Hits  : Integer;
begin
  Result := '';
  AJump := Default(TRdxToken);
  ASemi := Default(TRdxToken);
  Jumps := 0;
  Hits := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    N := After(AMap, T);
    if IsKeywordAfter(T, Prev) and InList(T.Low, JUMP_WORDS) then
    begin
      Inc(Jumps);
      if (T.Low = AWord) and (N.Low = ';') then
      begin
        Inc(Hits);
        AJump := T;
        ASemi := N;
      end;
    end;
    Prev := T;
    T := N;
  end;
  // Die Gruende wie bei jeder Token-Suche (OneTokenReason) - die Zaehlung
  // bleibt eigen: jeder Sprung zaehlt, nicht nur der gemeldete. What und
  // das Muster uebersetzt der Aufrufer (Texte umstellen): What als ganze
  // Nominalphrase, das Muster unformatiert (%d = Zahl der Spruenge).
  if Hits = 0 then
    Result := OneTokenReason(ALine, 0, _('no "%s;"', [AWord]), '')
  else if Jumps > 1 then
    Result := OneTokenReason(ALine, Jumps, '', _('%d jump statements'))
  else if ASemi.Line <> AJump.Line then
    Result := _('jump and ";" on different lines');
end;

// Folgt hinter ASemi nur die end-Kette bis zum Routinenende, 'end.' oder
// 'until'? Wie uRedundantJump: ein end allein nur vor Dateiende, '.'
// bzw. until; ab zwei end auch vor dem Kopf einer Routine oder eines
// Abschnitts.
function ChainEnds(AMap: TRdxCodeMap; const ASemi: TRdxToken): Boolean;
var
  T    : TRdxToken;
  Ends : Integer;
begin
  Ends := 0;
  T := After(AMap, ASemi);
  while T.Low = 'end' do
  begin
    Inc(Ends);
    T := After(AMap, T);
    if T.Low = ';' then
      T := After(AMap, T);
  end;
  Result := (Ends > 0) and ((T.Low = '') or (T.Low = '.')
    or (T.Low = 'until') or ((Ends >= 2) and InList(T.Low, CHAIN_TERMS)));
end;

{ TRdxLoopScan }

// Ein Schluesselwort rueckwaerts (ADepth: offene Bloecke, TRdxBackBalance):
// rsFound im Rumpf einer Schleife, rsStop an einer Routinengrenze. Ein
// begin/case/try/asm auf oberster Ebene ist der Anfang des umschliessenden
// Blocks - dort beginnt eine neue Anweisungsfolge (SawSemi zurueck); die
// Bloecke darin zaehlt die Bilanz.
function TRdxLoopScan.StepWord(const T: TRdxToken; ADepth: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = 'repeat' then
  begin
    if ADepth = 0 then
      Result := rsFound;
  end
  else if (T.Low = 'for') or (T.Low = 'while') then
  begin
    // Ein schon gekreuztes ';' heisst: die einanweisige Schleife ist zu
    // Ende, der Sprung steht dahinter ('while .. do Inc(Run); Exit;').
    if (ADepth = 0) and not SawSemi then
      Result := rsFound;
  end
  else if InList(T.Low, ['begin', 'case', 'try', 'asm']) then
  begin
    if ADepth = 0 then
      SawSemi := False;
  end
  else if InList(T.Low, ROUTINE_BOUNDS) then
    Result := rsStop;
end;

// Steht der Sprung im Rumpf einer Schleife? Dann ist Exit eine
// Frueh-Rueckkehr, kein No-Op (uRedundantJump: Schleifen-Gate). Die
// Bilanz fuehrt TRdxBackBalance - nur 'record' laesst diese Suche aus: sie
// zaehlte es nie als Oeffner (Bestand seit uRedundantJump; Review Woche
// G07-03 nennt die Luecke, die Folgewelle zieht nur die Bilanz zusammen
// und aendert kein Ergebnis).
function JumpInsideLoop(AMap: TRdxCodeMap; const AJump: TRdxToken): Boolean;
var
  Scan : TRdxLoopScan;
  W    : TRdxBackBalance;
  Step : TRdxStep;
begin
  Scan := Default(TRdxLoopScan);
  W.Start(AMap, AJump);
  while W.Next do
  begin
    Step := rsGoOn;
    if (W.Tok.Low = ';') and (W.Depth = 0) then
      Scan.SawSemi := True
    else if IsKeywordAfter(W.Tok, W.Prev) then
      Step := Scan.StepWord(W.Tok, W.Depth);
    if Step <> rsGoOn then
      Exit(Step = rsFound);
    if W.Tok.Low <> 'record' then
      W.Balance;
  end;
  Result := False;
end;

// InFinally, ein Schluesselwort rueckwaerts (ADepth: offene Bloecke,
// TRdxBackBalance - die umschliessenden verlassen sie auf Tiefe 0):
// rsFound im finally-Teil, rsStop an einer Routinengrenze (auch einer
// anonymen Methode).
function FinallyStep(const T: TRdxToken; ADepth: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if (ADepth = 0) and (T.Low = 'finally') then
    Result := rsFound
  else if InList(T.Low, ROUTINE_BOUNDS) then
    Result := rsStop;
end;

// Steht der Sprung (auch in einem Block darin) im finally-Teil eines try?
function InFinally(AMap: TRdxCodeMap; const AJump: TRdxToken): Boolean;
var
  W    : TRdxBackBalance;
  Step : TRdxStep;
begin
  W.Start(AMap, AJump);
  while W.Next do
  begin
    if IsKeywordAfter(W.Tok, W.Prev) then
    begin
      Step := FinallyStep(W.Tok, W.Depth);
      if Step <> rsGoOn then
        Exit(Step = rsFound);
    end;
    W.Balance;
  end;
  Result := False;
end;

// SCA080 (ueberfluessiger Sprung): Gegenprobe wie der Detektor und die
// Sperren ohne Bezug zur Form der Zeile. '' oder der Grund. Nicht zu
// verwechseln mit LeavesDestructorReason (uRdxResultFixes, SCA097: ein
// Sprung verlaesst den Destruktor vor inherited) und SpanJumpReason
// (uRdxTryFixes: ein Sprung im Bereich eines try/finally) - bis zur
// Nachpruefung B2S hiessen alle drei JumpReason (Review R3-05/R5-03).
function RedundantJumpReason(AMap: TRdxCodeMap; const AJump, ASemi: TRdxToken): string;
begin
  Result := '';
  if LineHasComment(AMap, AJump.Line) then
    Exit(_(R_LINE_COMMENT, [MsgDecideByHand]));
  // Hinter '; ' steht das gemeinsame Ende als %s (MsgLineMoved) - der
  // Trenner ist kein ' - ', MsgMovedSuffix passt nicht.
  if not ChainEnds(AMap, ASemi) then
    Exit(_('code follows the jump - no redundant jump; %s', [MsgLineMoved]));
  if (AJump.Low = 'exit') and JumpInsideLoop(AMap, AJump) then
    Exit(_('Exit in a loop is an early return, not a no-op'));
  if InFinally(AMap, AJump) then
    Exit(_('jump in the finally part - Delphi (E2126) and FPC (06040) do not '
      + 'compile it; %s', [MsgCheckByHand]));
  if DeclaresRoutine(AMap, AJump.Low) then
    Result := _('the unit declares its own routine %s - the jump may call it',
      [AJump.Low]);
end;

// 'else Exit;' am Ende eines if: ab hinter dem then-Zweig bis hinter den
// Sprung loeschen, das ';' bleibt. Der Bereich beginnt AUF dem letzten
// Zeichen des then-Zweigs, das neu geschrieben wird - hinter dem
// Zeilenende darf keiner beginnen (SpanFits). '' oder der Grund.
function ElseJumpEdit(AMap: TRdxCodeMap; const AElse, AJump: TRdxToken;
  out AEdit: TRdxEdit): string;
var
  Li, Co : Integer;
  Span   : TRefactorSpan;
begin
  AEdit := Default(TRdxEdit);
  // Den Grund von ElseBelongsToIf uebersetzt uRdxCodeMap; hier steht er
  // als %s im eigenen Satz (Texte umstellen: der Aufrufer uebersetzt).
  if not ElseBelongsToIf(AMap, AElse, Result) then
    Exit(_('%s - the jump is the only statement there', [Result]));
  if not LastCharBefore(AMap, AElse, Li, Co) then
    Exit(_('no then branch before the else'));
  Span := TRefactorSpan.Make(SPAN_080, Li, Co, AJump.Line, AJump.EndCol);
  if CommentInRange(AMap, Span) then
    Exit(_('comment between the then branch and the jump - it would be '
      + 'lost'));
  AEdit.Span := Span;
  AEdit.Expected := RangeText(AMap, Span);
  AEdit.NewText := Copy(AMap.Raw(Li), Co, 1);
end;

// Die Ersetzung je nach dem, was vor dem Sprung steht. '' oder der Grund.
function JumpEdit(AMap: TRdxCodeMap; const AJump, ASemi: TRdxToken;
  out AEdit: TRdxEdit): string;
var
  Site : TRdxStmtSite;
begin
  Site := Default(TRdxStmtSite);
  Site.First := AJump;
  Site.Prev := Before(AMap, AJump);
  Site.Next := After(AMap, ASemi);
  Site.EndLine := ASemi.Line;
  Site.EndCol := ASemi.EndCol;
  if Site.Prev.Low = 'else' then
    Exit(ElseJumpEdit(AMap, Site.Prev, AJump, AEdit));
  AEdit := Default(TRdxEdit);
  Result := ContextReason(Site.Prev, Site.Next);
  if Result = '' then
    Result := DeleteEdit(AMap, Site, SPAN_080, AEdit);
end;

class function TRdxFlowFixes.RedundantJump(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxFlowPlan;
  out AReason: string): Boolean;
var
  JumpWord    : string;   // nicht 'Word': verdeckte System.Word (Review R3-06)
  Jump, Semi  : TRdxToken;
begin
  APlan := Default(TRdxFlowPlan);
  Jump := Default(TRdxToken);
  Semi := Default(TRdxToken);
  JumpWord := JumpOf(AMessage);
  if JumpWord = '' then
    AReason := _('the message has no jump statement')
  else
  begin
    APlan.Target := UpperCase(Copy(JumpWord, 1, 1)) + Copy(JumpWord, 2, MaxInt);
    AReason := JumpOn(AMap, ALine, JumpWord, Jump, Semi);
  end;
  if AReason = '' then
    AReason := RedundantJumpReason(AMap, Jump, Semi);
  if AReason = '' then
  begin
    APlan.Target := Copy(AMap.Raw(Jump.Line), Jump.Col, Jump.Len);
    AReason := JumpEdit(AMap, Jump, Semi, APlan.Edit);
  end;
  Result := AReason = '';
end;

{ ---- SCA047 ---- }

// L aus 'Self-assignment: L := R (no-op or copy-paste)'; '' ohne diese
// Form.
function SelfTargetOf(const AMessage: string): string;
var
  Q : Integer;
begin
  Result := '';
  Q := Pos(KEY_ASSIGN, AMessage);
  if (Pos(KEY_SELF, AMessage) = 1) and (Q > Length(KEY_SELF) + 1) then
    Result := Trim(Copy(AMessage, Length(KEY_SELF) + 1,
      Q - Length(KEY_SELF) - 1));
end;

// Der Pfad ohne Leerraum und klein ('Pt . Y' -> 'pt.y') - wie der
// Detektor vergleicht (Normalize). Zeichen fuer Zeichen, ohne
// Verkettung in der Schleife (SCA110).
function PathKey(const S: string): string;
var
  i, n : Integer;
begin
  SetLength(Result, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if not CharInSet(S[i], [' ', #9, #10, #13]) then
    begin
      Inc(n);
      Result[n] := S[i];
    end;
  SetLength(Result, n);
  Result := LowerCase(Result);
end;

// Ab ATok ein Pfad 'A', 'A.B', 'R^.F': der Quelltext von seinem ersten
// bis zum letzten Token als PathKey (ein Kommentar darin bleibt stehen -
// dann passt der Schluessel nicht); ATok wird zum Token dahinter, ALast zum
// letzten des Pfads. '' ohne Wort am Anfang.
function PathAt(AMap: TRdxCodeMap; var ATok: TRdxToken;
  out ALast: TRdxToken): string;
var
  First, N : TRdxToken;
begin
  Result := '';
  ALast := Default(TRdxToken);
  if not ATok.IsWord then Exit;
  First := ATok;
  ALast := ATok;
  ATok := After(AMap, ATok);
  N := After(AMap, ATok);
  while (ATok.Low = '^') or ((ATok.Low = '.') and N.IsWord) do
  begin
    if ATok.Low = '.' then
      ATok := N;
    ALast := ATok;
    ATok := After(AMap, ATok);
    N := After(AMap, ATok);
  end;
  Result := PathKey(RangeText(AMap, TRefactorSpan.Make(SPAN_047, First.Line,
    First.Col, ALast.Line, ALast.EndCol)));
end;

// Steht an T 'P := P' mit dem Pfad P = AKey, und endet die Anweisung
// dahinter? Dann True und ASite.
function SelfAt(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  const AKey: string; out ASite: TRdxStmtSite): Boolean;
var
  Cur, Last : TRdxToken;
begin
  Result := False;
  ASite := Default(TRdxStmtSite);
  if InList(APrev.Low, PATH_JOINERS) then Exit;
  Cur := T;
  if (PathAt(AMap, Cur, Last) <> AKey) or (Cur.Low <> ':=') then Exit;
  Cur := After(AMap, Cur);
  if PathAt(AMap, Cur, Last) <> AKey then Exit;
  ASite.First := T;
  ASite.Prev := APrev;
  ASite.Next := Cur;
  ASite.EndLine := Last.Line;
  ASite.EndCol := Last.EndCol;
  if Cur.Low = ';' then
  begin
    ASite.Next := After(AMap, Cur);
    ASite.EndLine := Cur.Line;
    ASite.EndCol := Cur.EndCol;
  end;
  Result := (Cur.Low = ';') or (Cur.Low = '') or InList(Cur.Low, STATEMENT_STOPS);
end;

// 'AArg := AArg' an T (OneTokenOnLine, SelfOn).
function IsSelfAssignOf(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  S : TRdxStmtSite;
begin
  Result := SelfAt(AMap, T, Before(AMap, T), AArg, S);
end;

// Die eine Selbstzuweisung AKey auf ALine. '' oder der Grund.
function SelfOn(AMap: TRdxCodeMap; ALine: Integer; const AKey: string;
  out ASite: TRdxStmtSite): string;
var
  S   : TRdxLineSearch;
  Hit : TRdxToken;
begin
  ASite := Default(TRdxStmtSite);
  S := Default(TRdxLineSearch);
  S.Test    := IsSelfAssignOf;
  S.Arg     := AKey;
  // What als ganze uebersetzte Nominalphrase; ManyFmt ist ein MUSTER
  // (%d = Zahl der Treffer, %s = ManyArg) - der Pfad aus der Meldung steht
  // als Argument in ManyArg, nie im Muster (Vertrag von TRdxLineSearch; bis
  // zur Review Woche G07-16 stand er im Muster).
  S.What    := _('no self-assignment "%s := %s"', [AKey, AKey]);
  S.ManyFmt := _('%d self-assignments of %s');
  S.ManyArg := AKey;
  Result := OneTokenOnLine(AMap, ALine, S, Hit);
  if Result = '' then
    SelfAt(AMap, Hit, Before(AMap, Hit), AKey, ASite);
end;

// Ein 'class operator Assign' in der Unit (Delphi 10.4: verwaltete
// Records)? Dann ruft eine Zuweisung Code. Nur die Zeilen, die 'operator'
// nennen (NextTokenOnLineWith, Review R3-03 - bis Charge FC ein Lauf ueber
// jedes Token der Datei je SCA047-Fund).
function DeclaresAssignOperator(AMap: TRdxCodeMap): Boolean;
const
  KW_OPERATOR = 'operator';
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_OPERATOR);
  while T.Low <> '' do
  begin
    if (T.Low = KW_OPERATOR) and (After(AMap, T).Low = 'assign') then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, KW_OPERATOR);
  end;
end;

// Die Sperren ohne Typwissen. '' oder der Grund.
function SelfReason(AMap: TRdxCodeMap; const ASite: TRdxStmtSite;
  const AKey: string): string;
var
  Root : string;
begin
  Result := '';
  Root := ASite.First.Low;
  if LineHasComment(AMap, ASite.First.Line) then
    Exit(_(R_LINE_COMMENT, [MsgDecideByHand]));
  // Der Katalog empfiehlt dort das Unterdruecken (sca-rules.json SCA047).
  // Eigene msgid: 'von Hand entscheiden oder unterdruecken' ist ein anderer
  // Satz als MsgDecideByHand (c_groups Abschnitt 3).
  if Root = 'result' then
    Exit(_('Result := Result may silence a compiler message (Delphi W1035, '
      + 'FPC "Function result does not seem to be set") - removed, it would '
      + 'come back; decide by hand or suppress'));
  if (AKey = Root) and DeclaresRoutine(AMap, Root) then
    Exit(_('%s is also the name of a routine of this unit - the right side '
      + 'may be a (recursive) call', [Root]));
  if DeclaresAssignOperator(AMap) then
    Exit(_('the unit declares a class operator Assign - an assignment can '
      + 'run code there'));
  Result := ContextReason(ASite.Prev, ASite.Next);
end;

// Das Ziel wie im Quelltext (der linke Pfad der Anweisung).
function SourcePath(AMap: TRdxCodeMap; const AFirst: TRdxToken): string;
var
  Cur, Last : TRdxToken;
begin
  Cur := AFirst;
  PathAt(AMap, Cur, Last);
  if Last.Line = AFirst.Line then
    Result := Copy(AMap.Raw(AFirst.Line), AFirst.Col, Last.EndCol - AFirst.Col)
  else
    Result := Copy(AMap.Raw(AFirst.Line), AFirst.Col, AFirst.Len);
end;

class function TRdxFlowFixes.SelfAssignment(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxFlowPlan;
  out AReason: string): Boolean;
var
  Key  : string;
  Site : TRdxStmtSite;
begin
  APlan := Default(TRdxFlowPlan);
  Site := Default(TRdxStmtSite);
  APlan.Target := SelfTargetOf(AMessage);
  Key := PathKey(APlan.Target);
  if Key = '' then
    AReason := _('the message has no target')
  else
    AReason := SelfOn(AMap, ALine, Key, Site);
  if AReason = '' then
    AReason := SelfReason(AMap, Site, Key);
  if AReason = '' then
  begin
    APlan.Target := SourcePath(AMap, Site.First);
    AReason := DeleteEdit(AMap, Site, SPAN_047, APlan.Edit);
  end;
  Result := AReason = '';
end;

end.
