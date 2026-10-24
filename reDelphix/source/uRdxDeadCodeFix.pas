unit uRdxDeadCodeFix;

// reDelphix - Editorhilfe fuer SCA011 DeadCode, OHNE ToolsAPI und ohne
// Parser: die toten Anweisungen hinter einem unbedingten Exit, raise,
// Break oder Continue loeschen - bis vor das end/until/except/finally,
// das ihre Anweisungsliste schliesst. Bedeutungsgleich: der Code lief nie
// (Changes: False); der Menuetext nennt die Zahl der Zeilen, weil toter
// Code oft bewusst geparkter Code ist (Recherche-Tabelle SCA011).
//
// DER FUND: uDeadCode meldet die Zeile des ersten Geschwisterknotens
// hinter dem Terminator (Nxt.Line - die erste tote Anweisung), einmal je
// Block; die Meldung nennt den Terminator ('Dead code after Exit', 'raise',
// 'Break', 'Continue'), keine Spalte. Der Planer prueft am Text nach:
//   - die gemeldete Zeile beginnt mit einer Anweisung, davor steht ';',
//   - die Anweisung vor diesem ';' ist genau der Terminator der Meldung
//     ('Exit;', 'Exit(..);', 'raise ..;', 'Break;', 'Continue;') und steht
//     selbst in einer Anweisungsliste (davor ';', begin, try, repeat,
//     finally, except) - nicht hinter then/else/do/':' (dann ist er
//     bedingt, und was folgt, laeuft),
//   - vorwaerts bis zum Listenende (end/until/except/finally auf derselben
//     Ebene; begin/try/case/repeat darin zaehlen ihre eigenen Schliesser).
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - ein Kommentar im Bereich, auch hinter dem Terminator auf seiner
//     Zeile ('Exit; // alt:'): er dokumentiert oft geparkten Code,
//   - eine Direktive vom Terminator bis zum Listenende (bedingter Code kann
//     den Terminator oder das Listenende verschieben),
//   - ein ':' im Bereich ausserhalb von case-Werten, on-Handlern und
//     Klammern: eine Marke (ein goto macht den Rest erreichbar - FastCode
//     'Found1:') oder eine typisierte Inline-Deklaration; ein asm-Block,
//   - ein 'else' auf oberster Ebene ohne if derselben Anweisung, ein
//     Listenende, das nicht passt, oder keines bis zum Dateiende,
//   - das Listenende steht auf der letzten Zeile des toten Codes ('Foo;
//     end;') - die Hilfe loescht nur ganze Zeilen,
//   - die Datei deklariert einen eigenen Bezeichner Exit, Break bzw.
//     Continue (dann ist der Terminator ein Aufruf, der zurueckkehrt).
//
// FPC-tauglich: die Unit bindet nur die Code-Sicht, die Ersetzung und die
// Texte. Den Adapter fuer die Tabelle (MapFix, Name = Zeilenzahl ueber
// LineCountOf) haelt uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_DEAD_NO_TERM = 'the message names no Exit, raise, Break or Continue';
  R_DEAD_MOVED = 'no statement starts the reported line';
  R_DEAD_NOT_AFTER = 'the statement before the line is not "%s"';
  R_DEAD_CONDITIONAL = '"%s" stands after "%s" - it is conditional, the '
    + 'code after it runs';
  R_DEAD_COMMENT = 'comment in the unreachable code - it may document '
    + 'parked code; delete by hand';
  R_DEAD_DIRECTIVE = 'compiler directive in the unreachable code or at '
    + 'its jump';
  R_DEAD_COLON = '":" in the unreachable code (a label or a typed '
    + 'declaration) - a goto could reach it';
  R_DEAD_ASM = 'asm block in the unreachable code';
  R_DEAD_ELSE = '"else" in the unreachable code without an "if" of its '
    + 'statement';
  R_DEAD_NO_END = 'end of the statement list not found';
  R_DEAD_SAME_LINE = 'the statement list ends on the last line of the '
    + 'unreachable code - only whole lines are deleted';
  R_DEAD_SHADOW = 'the file declares its own "%s" - it may be a routine '
    + 'that returns';

type
  TRdxDeadCodeFix = class
  public
    // SCA011: die ganzen Zeilen von ALine (erste tote Anweisung) bis zur
    // letzten Zeile vor dem Listenende loeschen.
    class function DeleteDeadCode(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // Die Zahl der Zeilen, die eine Ersetzung von DeleteDeadCode loescht
    // (fuer den Menuetext: Name des Eintrags).
    class function LineCountOf(const AEdit: TRdxEdit): Integer; static;
    // Der Terminator aus der Meldung, klein ('Dead code after Exit' ->
    // 'exit'); '' ohne oder fuer einen unbekannten.
    class function TerminatorOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText;         // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_011 = 'sca011';
  KEY_DEAD = 'Dead code after ';
  TERM_EXIT = 'exit';
  TERM_RAISE = 'raise';
  TERMINATORS: array[0..3] of string = ('exit', 'raise', 'break',
    'continue');
  // Davor steht der Terminator unbedingt in einer Anweisungsliste.
  TERM_PREV: array[0..5] of string = (';', 'begin', 'try', 'repeat',
    'finally', 'except');
  // Rueckwaerts endet hier die Anweisung des Terminators (auf oberster
  // Klammerebene; Woerter nur als Schluesselwort).
  BACK_STOPS: array[0..21] of string = (';', ':', ':=', 'begin', 'end',
    'try', 'repeat', 'until', 'finally', 'except', 'then', 'else', 'do',
    'of', 'case', 'if', 'while', 'for', 'with', 'on', 'initialization',
    'finalization');
  // Vorwaerts: diese oeffnen eine Ebene, die 'end' schliesst.
  END_BLOCKS: array[0..2] of string = ('begin', 'try', 'case');
  KW_REPEAT = 'repeat';
  KW_UNTIL = 'until';
  KW_END = 'end';
  KW_ELSE = 'else';
  KW_IF = 'if';
  KW_ON = 'on';
  KW_ASM = 'asm';
  KW_TRY = 'try';
  KW_CASE = 'case';
  // Mitten in einer try-Anweisung; auf oberster Ebene ein Listenende.
  TRY_PARTS: array[0..1] of string = ('except', 'finally');
  // Wo eine Anweisungsliste endet, sagt uRdxCodeMap.LIST_ENDS (bis zur
  // Hygiene-Welle H1 hier byte-gleich kopiert).
  // Damit beginnt keine Anweisung - die gemeldete Zeile ist verschoben.
  NOT_FIRST: array[0..10] of string = ('end', 'until', 'except', 'finally',
    'else', 'then', 'do', 'of', 'on', 'initialization', 'finalization');
  // Davor wird ein Name deklariert (wie uRdxGotoExitFix.ExitIsShadowed).
  DECL_PREV: array[0..5] of string = ('var', 'const', 'property',
    'procedure', 'function', ',');
  // Sicherung der Rueckwaerts-Suche (ein Terminator ist kurz; mehr Token
  // sind ein Zeichen, dass die Grenze nicht stimmt).
  MAX_BACK_TOKENS = 2000;

class function TRdxDeadCodeFix.TerminatorOf(const AMessage: string): string;
var
  p : Integer;
begin
  Result := '';
  p := Pos(KEY_DEAD, AMessage);
  if p = 0 then
    Exit;
  Result := LowerCase(Trim(Copy(AMessage, p + Length(KEY_DEAD), MaxInt)));
  if not InList(Result, TERMINATORS) then
    Result := '';
end;

class function TRdxDeadCodeFix.LineCountOf(const AEdit: TRdxEdit): Integer;
begin
  // Der Bereich endet auf Spalte 1 der Zeile hinter dem toten Code.
  Result := AEdit.Span.EndLine - AEdit.Span.StartLine;
end;

// Ein Wort als Schluesselwort - nicht hinter '&', '@' oder '.'.
function IsKw(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := IsKeywordAfter(T, Before(AMap, T));
end;

// Die Anweisung vor ASemi rueckwaerts: ihr erstes Token (ATerm) und das
// Token davor (AStop). False, wenn keine sichere Grenze kommt.
function StatementBefore(AMap: TRdxCodeMap; const ASemi: TRdxToken;
  out ATerm, AStop: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Depth : Integer;
  N     : Integer;
begin
  Result := False;
  ATerm := Default(TRdxToken);
  AStop := Default(TRdxToken);
  Depth := 0;
  N := 0;
  T := Before(AMap, ASemi);
  while (T.Low <> '') and (N < MAX_BACK_TOKENS) do
  begin
    if (T.Low = ')') or (T.Low = ']') then
      Inc(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
    begin
      Dec(Depth);
      if Depth < 0 then
        Exit;
    end
    else if (Depth = 0) and InList(T.Low, BACK_STOPS)
            and (not T.IsWord or IsKw(AMap, T)) then
    begin
      AStop := T;
      Exit(ATerm.Low <> '');
    end;
    ATerm := T;
    T := Before(AMap, T);
    Inc(N);
  end;
end;

// Ist die Anweisung ATerm .. ASemi genau der Terminator AWord? 'Exit;' und
// 'Exit(..);', 'Break;', 'Continue;', 'raise ..;'.
function IsTerminator(AMap: TRdxCodeMap; const ATerm, ASemi: TRdxToken;
  const AWord: string): Boolean;
var
  Nxt, CloseTok : TRdxToken;
begin
  Result := False;
  if (ATerm.Low <> AWord) or not IsKw(AMap, ATerm) then
    Exit;
  if AWord = TERM_RAISE then
    Exit(True);
  Nxt := After(AMap, ATerm);
  if SameTok(Nxt, ASemi) then
    Exit(True);
  if (AWord <> TERM_EXIT) or (Nxt.Low <> '(') then
    Exit;
  CloseTok := MatchClose(AMap, Nxt);
  Result := (CloseTok.Low <> '') and SameTok(After(AMap, CloseTok), ASemi);
end;

// Deklariert die Datei einen eigenen Bezeichner AWord (Variable, Parameter,
// Member, Routine, Marke)? Dann ist der Terminator dort vielleicht ein
// Aufruf, der zurueckkehrt. Wie uRdxGotoExitFix.ExitIsShadowed (dort
// privat) fuer ein beliebiges Wort.
function IsShadowed(AMap: TRdxCodeMap; const AWord: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), AWord);
  while T.Low <> '' do
  begin
    if (T.Low = AWord)
       and ((After(AMap, T).Low = ':')
            or InList(Before(AMap, T).Low, DECL_PREV)) then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, AWord);
  end;
end;

// Ein Schritt vorwaerts durch die tote Liste: offene Ebenen (begin, try,
// case, repeat), Klammertiefe und ob die laufende Anweisung der obersten
// Ebene ein if traegt (ein else gehoert dann zu ihr). Reason bei rsStop.
type
  TRdxListScan = record
    Stack  : array of string;
    N      : Integer;
    Parens : Integer;
    StmtIf : Boolean;
    Reason : string;
  end;

// Bricht mit dem (schon uebersetzten) Grund AReason ab.
function ScanFail(var AScan: TRdxListScan; const AReason: string): TRdxStep;
begin
  AScan.Reason := AReason;
  Result := rsStop;
end;

// Eine Ebene oeffnen (begin, try, case, repeat).
procedure ScanPush(var AScan: TRdxListScan; const ALow: string);
begin
  if AScan.N >= Length(AScan.Stack) then
    SetLength(AScan.Stack, AScan.N + 8);
  AScan.Stack[AScan.N] := ALow;
  Inc(AScan.N);
end;

// Die oberste offene Ebene; '' ohne.
function ScanTop(const AScan: TRdxListScan): string;
begin
  Result := '';
  if AScan.N > 0 then
    Result := AScan.Stack[AScan.N - 1];
end;

// Das Token T (P davor): weiter, Listenende (rsFound) oder Abbruch.
function ListStep(AMap: TRdxCodeMap; var AScan: TRdxListScan;
  const T, P: TRdxToken): TRdxStep;
begin
  Result := rsGoOn;
  if (T.Low = '(') or (T.Low = '[') then
  begin
    Inc(AScan.Parens);
    Exit;
  end;
  if (T.Low = ')') or (T.Low = ']') then
  begin
    Dec(AScan.Parens);
    if AScan.Parens < 0 then
      Result := ScanFail(AScan, _(R_DEAD_NO_END));
    Exit;
  end;
  // In Klammern: Argumente, Format-Angaben ('X:5'), anonyme Methoden mit
  // eigenem begin..end - nichts davon schliesst die Liste.
  if AScan.Parens > 0 then
    Exit;
  if T.Low = ';' then
  begin
    if AScan.N = 0 then
      AScan.StmtIf := False;
    Exit;
  end;
  if T.Low = ':' then
  begin
    // Erlaubt: ein case-Wert ('1:') auf der Ebene des case und der Typ
    // eines on-Handlers ('on E: Exception do').
    if (ScanTop(AScan) <> KW_CASE) and (Before(AMap, P).Low <> KW_ON) then
      Result := ScanFail(AScan, _(R_DEAD_COLON));
    Exit;
  end;
  if not IsKeywordAfter(T, P) then
    Exit;
  if T.Low = KW_ASM then
    Exit(ScanFail(AScan, _(R_DEAD_ASM)));
  if InList(T.Low, END_BLOCKS) or (T.Low = KW_REPEAT) then
  begin
    ScanPush(AScan, T.Low);
    Exit;
  end;
  if InList(T.Low, LIST_ENDS) and (AScan.N = 0) then
    Exit(rsFound);
  if T.Low = KW_END then
  begin
    if ScanTop(AScan) = KW_REPEAT then
      Exit(ScanFail(AScan, _(R_DEAD_NO_END)));
    Dec(AScan.N);
  end
  else if T.Low = KW_UNTIL then
  begin
    if ScanTop(AScan) <> KW_REPEAT then
      Exit(ScanFail(AScan, _(R_DEAD_NO_END)));
    Dec(AScan.N);
  end
  else if InList(T.Low, TRY_PARTS) then
  begin
    if ScanTop(AScan) <> KW_TRY then
      Result := ScanFail(AScan, _(R_DEAD_NO_END));
  end
  else if (T.Low = KW_ELSE) and (AScan.N = 0) and not AScan.StmtIf then
    Result := ScanFail(AScan, _(R_DEAD_ELSE))
  else if (T.Low = KW_IF) and (AScan.N = 0) then
    AScan.StmtIf := True;
end;

// Vorwaerts ab AFirst bis zum Listenende AStop (end/until/except/finally
// auf oberster Ebene). '' oder der Grund.
function ListEnd(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  out AStop: TRdxToken): string;
var
  Scan : TRdxListScan;
  T, P : TRdxToken;
  Step : TRdxStep;
begin
  AStop := Default(TRdxToken);
  Scan := Default(TRdxListScan);
  P := Before(AMap, AFirst);
  T := AFirst;
  while T.Low <> '' do
  begin
    Step := ListStep(AMap, Scan, T, P);
    if Step = rsFound then
    begin
      AStop := T;
      Exit('');
    end;
    if Step = rsStop then
      Exit(Scan.Reason);
    P := T;
    T := After(AMap, T);
  end;
  Result := _(R_DEAD_NO_END);
end;

// Kommentar oder Direktive zwischen dem Ende von AFrom und dem Anfang von
// ATo (Zeichenklasse 'k' der Code-Sicht)?
function CommentBetween(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): Boolean;
var
  Li, First, Last : Integer;
begin
  Result := False;
  for Li := AFrom.Line to ATo.Line do
  begin
    First := 1;
    if Li = AFrom.Line then
      First := AFrom.EndCol;
    Last := Length(AMap.Raw(Li));
    if Li = ATo.Line then
      Last := ATo.Col - 1;
    if AMap.HasComment(Li, First, Last) then
      Exit(True);
  end;
end;

class function TRdxDeadCodeFix.DeleteDeadCode(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  TermWord                 : string;
  DeadTok, Semi, Term, Stop : TRdxToken;
  EndTok                   : TRdxToken;
  LastLine, LastCol        : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  TermWord := TerminatorOf(AMessage);
  if TermWord = '' then
  begin
    AReason := _(R_DEAD_NO_TERM);
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := MsgMovedSuffix(_(R_DEAD_MOVED));
    Exit;
  end;
  if AMap.StartsInside(ALine) then
  begin
    AReason := MsgLineStartsInCommentOrString;
    Exit;
  end;
  // Die erste tote Anweisung: das erste Token der Zeile, davor ';'.
  DeadTok := NextToken(AMap, ALine, 1);
  if (DeadTok.Low = '') or (DeadTok.Line <> ALine)
     or not FirstOnLine(AMap, DeadTok)
     or (InList(DeadTok.Low, NOT_FIRST) and IsKw(AMap, DeadTok)) then
  begin
    AReason := MsgMovedSuffix(_(R_DEAD_MOVED));
    Exit;
  end;
  Semi := Before(AMap, DeadTok);
  if (Semi.Low <> ';') or not StatementBefore(AMap, Semi, Term, Stop)
     or not IsTerminator(AMap, Term, Semi, TermWord) then
  begin
    AReason := MsgMovedSuffix(_(R_DEAD_NOT_AFTER, [TermWord]));
    Exit;
  end;
  if not InList(Stop.Low, TERM_PREV) then
  begin
    AReason := _(R_DEAD_CONDITIONAL, [TokText(AMap, Term), Stop.Low]);
    Exit;
  end;
  if (TermWord <> TERM_RAISE) and IsShadowed(AMap, TermWord) then
  begin
    AReason := _(R_DEAD_SHADOW, [TokText(AMap, Term)]);
    Exit;
  end;
  AReason := ListEnd(AMap, DeadTok, EndTok);
  if AReason <> '' then
    Exit;
  // Direktive ab dem Token vor dem Terminator, Kommentar ab dem ';' des
  // Terminators - je bis vor das Listenende.
  if DirectiveBetween(AMap, Stop, EndTok.Line, EndTok.Col) then
  begin
    AReason := _(R_DEAD_DIRECTIVE);
    Exit;
  end;
  if CommentBetween(AMap, Semi, EndTok) then
  begin
    AReason := _(R_DEAD_COMMENT);
    Exit;
  end;
  // Die letzte Zeile mit totem Code (Code oder String, Kommentare gibt es
  // hier nicht mehr); das Listenende muss auf einer spaeteren beginnen.
  if not LastCharBefore(AMap, EndTok, LastLine, LastCol)
     or (LastLine < ALine) then
  begin
    AReason := MsgMovedSuffix(_(R_DEAD_MOVED));
    Exit;
  end;
  if LastLine >= EndTok.Line then
  begin
    AReason := _(R_DEAD_SAME_LINE);
    Exit;
  end;
  // Ganze Zeilen samt Zeilenende: ALine traegt die erste tote Anweisung,
  // ist also nicht leer (SpanFits); das Ende liegt auf Spalte 1 der Zeile
  // hinter dem toten Code (LastLine + 1 <= EndTok.Line).
  AEdit.Span := TRefactorSpan.Make(SPAN_011, ALine, 1, LastLine + 1, 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := '';
  Result := True;
end;

end.
