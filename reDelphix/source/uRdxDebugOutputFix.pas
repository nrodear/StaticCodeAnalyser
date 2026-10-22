unit uRdxDebugOutputFix;

// reDelphix - Editorhilfe fuer SCA017 DebugOutput, OHNE ToolsAPI und ohne
// Parser: die gemeldete Debug-Ausgabe (WriteLn, ShowMessage,
// ShowMessagePos, OutputDebugString) als ganze Anweisung
//   (1) in '{$IFDEF DEBUG}' .. '{$ENDIF}' setzen - je eine eigene Zeile
//       davor und dahinter, eingerueckt wie die Anweisung. Der Debug-Build
//       gibt weiter aus, der Release-Build nicht mehr; der Detektor wertet
//       einen DEBUG-Bereich als Absicht (uDebugOutput, LineInDebugRange);
//   (2) zweiter Eintrag: die Anweisung loeschen (ganze Zeilen).
// Beide aendern das Verhalten (E2): (1) nur im Release-Build - FPC/Lazarus
// definiert DEBUG nicht von selbst, dort wirkt (1) wie (2) -, (2) in jedem
// Build; die Argumente werden dann nicht mehr ausgewertet.
//
// DER FUND: uDebugOutput meldet die Zeile des Aufruf-Knotens (nkCall: das
// erste Token der Anweisung; nkAssign: die Zeile der ZUWEISUNG, wenn der
// Aufruf in einer anonymen Methode rechts steht) und den Namen klein in der
// Meldung ('Debug output: writeln'), keine Spalte. Der Planer sucht den
// Aufruf auf der Zeile selbst und prueft die Anweisungsgrenzen.
//
// ANGEBOTEN nur fuer eine ganze Anweisung in einer Anweisungsliste
// (davor ';', begin, try, repeat, finally, except, initialization,
// finalization), allein auf ihrer Zeile bzw. ueber Zeilen bis zu ihrem
// ';', unqualifiziert oder als 'System.'.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - einzige Anweisung hinter then/else/do ohne begin, eines case-Zweigs
//     oder hinter einer Marke (':'): ohne die Anweisung - im Release bzw.
//     geloescht - bindete die naechste Anweisung an den Zweig (SCA077-
//     Falle; Baustein "ganze Anweisung" der Recherche),
//   - kein oder mehr als ein passender Aufruf auf der Zeile (Zeile
//     verschoben, mehrdeutig), ein Member-Aufruf ('Log.WriteLn', den der
//     Detektor nicht meldet), anderer Code auf den Zeilen der Anweisung,
//     kein ';' am Ende,
//   - ein Kommentar oder eine Direktive auf den Zeilen der Anweisung, ein
//     Bedingungsblock, der unmittelbar davor oeffnet bzw. dahinter
//     schliesst ("schon eine Direktive darum"; Leerzeilen zaehlen nicht,
//     ein '{$ENDIF}' davor oder '{$R+}' sperren nicht) oder ein offener
//     Bedingungsblock, der DEBUG nennt ('{$IFNDEF DEBUG}', '{$IFDEF
//     DEBUG} .. {$ELSE}'),
//   - nur (2): die Anweisung ist die einzige ihres Blocks (es bliebe ein
//     leerer Block, SCA077); (1) laesst den Block im Quelltext stehen.
//
// FPC-tauglich: die Unit bindet nur die Code-Sicht, die Ersetzung und die
// Texte. Den Adapter fuer die Tabelle (MapFix) haelt uRdxFixTable.

interface

uses
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_DBG_NO_NAME = 'the message names no call';
  R_DBG_MOVED = 'no call to %s on the reported line';
  R_DBG_MANY = 'the line calls %s more than once';
  R_DBG_BRANCH = 'the call is the only statement after "%s" without begin '
    + '- without it the next statement would belong to the branch';
  R_DBG_SHARED = 'the lines of the call carry other code';
  R_DBG_NO_SEMI = 'the call does not end with its own ";"';
  R_DBG_COMMENT = 'comment on the lines of the call - it may explain it; '
    + 'decide by hand';
  R_DBG_DIRECTIVE = 'compiler directive on the lines of the call';
  R_DBG_AROUND = 'a conditional directive already encloses the call (on '
    + 'the line before or after it)';
  R_DBG_UNDER_DEBUG = 'the call already sits in a conditional block that '
    + 'names DEBUG';
  R_DBG_LAST_LINE = 'the call ends on the last line of the file';

type
  TRdxDebugOutputFix = class
  public
    // SCA017, erster Eintrag: die Anweisung in '{$IFDEF DEBUG}' ..
    // '{$ENDIF}' (eigene Zeilen, Einrueckung der Anweisung).
    class function WrapInDebug(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // SCA017, zweiter Eintrag: die Anweisung loeschen (ihre ganzen Zeilen).
    class function DeleteCall(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
    // Der Name aus der Meldung ('Debug output: writeln' -> 'writeln',
    // klein); '' ohne.
    class function CallNameOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText;         // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_017 = 'sca017';
  KEY_DEBUG = 'Debug output: ';
  SYSTEM_UNIT = 'system';
  DEBUG_WORD = 'debug';
  DIR_OPEN = '{$IFDEF DEBUG}';
  DIR_CLOSE = '{$ENDIF}';
  // Davor steht eine Anweisung in einer Anweisungsliste: uRdxCodeMap.
  // LIST_PREV; dort endet eine Anweisungsliste (DeleteCall: einzige
  // Anweisung?): uRdxCodeMap.LIST_ENDS. Bis zur Hygiene-Welle H1 standen
  // hier mengengleiche Kopien.
  // Davor steht die Anweisung allein in einem Zweig (oder hinter einer
  // Marke bzw. einem case-Wert).
  BRANCH_PREV: array[0..3] of string = ('then', 'else', 'do', ':');
  // Davor ist ein Wort kein Aufruf ('@WriteLn', '&WriteLn').
  NOT_CALL_PREV: array[0..1] of string = ('@', '&');
  // Bedingungsbloecke (InDebugCondition).
  COND_OPEN: array[0..3] of string = ('ifdef', 'ifndef', 'if', 'ifopt');
  COND_ELSE: array[0..1] of string = ('else', 'elseif');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');

type
  // Die gemeldete Anweisung: erstes Token (System bzw. der Aufruf), der
  // Aufruf, das Token davor, das ';' am Ende und das Token dahinter.
  TRdxDebugSite = record
    Start : TRdxToken;
    Call  : TRdxToken;
    Prev  : TRdxToken;
    Semi  : TRdxToken;
    Next  : TRdxToken;
  end;

class function TRdxDebugOutputFix.CallNameOf(const AMessage: string): string;
var
  p, i : Integer;
begin
  Result := '';
  p := Pos(KEY_DEBUG, AMessage);
  if p = 0 then
    Exit;
  i := p + Length(KEY_DEBUG);
  while (i <= Length(AMessage)) and IsIdentChar(AMessage[i]) do
    Inc(i);
  Result := LowerCase(Copy(AMessage, p + Length(KEY_DEBUG),
    i - p - Length(KEY_DEBUG)));
end;

// Ist T ein Aufruf, wie ihn der Detektor meldet: unqualifiziert oder als
// 'System.X' (ein anderer Qualifier ist eine eigene Methode, uDebugOutput
// laesst ihn aus)?
function IsPlainCall(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  P, Q : TRdxToken;
begin
  P := Before(AMap, T);
  if P.Low = '.' then
  begin
    Q := Before(AMap, P);
    Result := (Q.Low = SYSTEM_UNIT) and (Before(AMap, Q).Low <> '.');
  end
  else
    Result := not InList(P.Low, NOT_CALL_PREV);
end;

// Genau ein Aufruf AName auf ALine (IsPlainCall); '' und der Aufruf in
// ACall, sonst der Grund.
function CallOnLine(AMap: TRdxCodeMap; ALine: Integer; const AName: string;
  out ACall: TRdxToken): string;
var
  T : TRdxToken;
  N : Integer;
begin
  ACall := Default(TRdxToken);
  N := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = AName) and IsPlainCall(AMap, T) then
    begin
      Inc(N);
      ACall := T;
    end;
    T := After(AMap, T);
  end;
  if N = 0 then
    Result := MsgMovedSuffix(_(R_DBG_MOVED, [AName]))
  else if N > 1 then
    Result := _(R_DBG_MANY, [AName])
  else
    Result := '';
end;

// Kommentar oder Direktive irgendwo auf den Zeilen AFrom..ATo?
function CommentOnLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;
var
  Li : Integer;
begin
  Result := False;
  for Li := AFrom to ATo do
    if AMap.HasComment(Li, 1, Length(AMap.Raw(Li))) then
      Exit(True);
end;

// Die naechste nicht leere Zeile ab ALine in Richtung AStep (+1/-1); 0
// ohne.
function NonBlankLine(AMap: TRdxCodeMap; ALine, AStep: Integer): Integer;
begin
  Result := ALine;
  while (Result >= 1) and (Result <= AMap.LineCount)
        and (Trim(AMap.Raw(Result)) = '') do
    Inc(Result, AStep);
  if (Result < 1) or (Result > AMap.LineCount) then
    Result := 0;
end;

// Steht auf ALine eine Direktive (aus Code heraus), deren Wort in AWords
// steht ('ifdef', 'endif' ...)?
function CondOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const AWords: array of string): Boolean;
var
  Co  : Integer;
  Arg : Boolean;
begin
  Result := False;
  for Co := 1 to Length(AMap.Raw(ALine)) do
    if OpensDirective(AMap, ALine, Co)
       and InList(DirectiveWord(AMap, ALine, Co, Arg), AWords) then
      Exit(True);
end;

// Steht ALine in einem offenen Bedingungsblock, dessen Bedingung DEBUG
// nennt ('{$IFNDEF DEBUG}', '{$IF Defined(DEBUG)}', auch im ELSE-Zweig)?
// Gelesen werden nur Direktiven aus Code heraus (DirectiveAt), ab
// Dateianfang; nur Zeilen mit '{$' bzw. '(*$' kosten einen Lauf.
function InDebugCondition(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Stack   : array of Boolean;
  N, Li   : Integer;
  Co, i   : Integer;
  L, W    : string;
  Arg     : Boolean;
  Names   : Boolean;
begin
  Result := False;
  SetLength(Stack, 0);
  N := 0;
  for Li := 1 to ALine - 1 do
  begin
    L := AMap.Raw(Li);
    if (Pos('{$', L) = 0) and (Pos('(*$', L) = 0) then
      Continue;
    for Co := 1 to Length(L) do
    begin
      if not OpensDirective(AMap, Li, Co) then
        Continue;
      W := DirectiveWord(AMap, Li, Co, Arg);
      Names := HasIdentWord(LowerCase(DirectiveArgs(AMap, Li, Co)),
        DEBUG_WORD);
      if InList(W, COND_OPEN) then
      begin
        if N >= Length(Stack) then
          SetLength(Stack, N + 8);
        Stack[N] := Names;
        Inc(N);
      end
      else if InList(W, COND_ELSE) and (N > 0) then
        Stack[N - 1] := Stack[N - 1] or Names
      else if InList(W, COND_CLOSE) and (N > 0) then
        Dec(N);
    end;
  end;
  for i := 0 to N - 1 do
    if Stack[i] then
      Exit(True);
end;

// Die gemeldete Anweisung und alle Sperren, die beide Eintraege teilen.
// '' oder der Grund.
function ReadSite(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  out ASite: TRdxDebugSite): string;
var
  Name     : string;
  OpenTok  : TRdxToken;
  CloseTok : TRdxToken;
  Nb       : Integer;
begin
  ASite := Default(TRdxDebugSite);
  Name := TRdxDebugOutputFix.CallNameOf(AMessage);
  if Name = '' then
    Exit(_(R_DBG_NO_NAME));
  if (ALine < 1) or (ALine > AMap.LineCount) then
    Exit(MsgMovedSuffix(_(R_DBG_MOVED, [Name])));
  if AMap.StartsInside(ALine) then
    Exit(MsgLineStartsInCommentOrString);
  Result := CallOnLine(AMap, ALine, Name, ASite.Call);
  if Result <> '' then
    Exit;
  ASite.Start := ASite.Call;
  if Before(AMap, ASite.Call).Low = '.' then
    ASite.Start := Before(AMap, Before(AMap, ASite.Call));
  ASite.Prev := Before(AMap, ASite.Start);
  if InList(ASite.Prev.Low, BRANCH_PREV) then
    Exit(_(R_DBG_BRANCH, [ASite.Prev.Low]));
  if not InList(ASite.Prev.Low, LIST_PREV) then
    Exit(MsgUnclearStatementOwner(ASite.Prev.Low));
  if (ASite.Start.Line <> ALine) or not FirstOnLine(AMap, ASite.Start) then
    Exit(_(R_DBG_SHARED));
  // Das Ende der Anweisung: hinter der Argumentliste bzw. dem Namen.
  OpenTok := After(AMap, ASite.Call);
  if OpenTok.Low = '(' then
  begin
    CloseTok := MatchClose(AMap, OpenTok);
    if CloseTok.Low = '' then
      Exit(MsgStatementEndNotFound);
    ASite.Semi := After(AMap, CloseTok);
  end
  else
    ASite.Semi := OpenTok;
  if ASite.Semi.Low <> ';' then
    Exit(_(R_DBG_NO_SEMI));
  // Hinter dem ';' kein Code mehr; ein Kommentar oder eine Direktive dort
  // sperrt unten mit eigenem Grund.
  if not TailIsComment(AMap, ASite.Semi.Line, ASite.Semi.Col) then
    Exit(_(R_DBG_SHARED));
  ASite.Next := After(AMap, ASite.Semi);
  // Direktive vor Kommentar: DirectiveInLines nennt die genauere Sperre
  // (HasComment sieht beide als 'k').
  if DirectiveInLines(AMap, ALine, ASite.Semi.Line) then
    Exit(_(R_DBG_DIRECTIVE));
  if CommentOnLines(AMap, ALine, ASite.Semi.Line) then
    Exit(_(R_DBG_COMMENT));
  // Schon eine Direktive darum: davor oeffnet ein Bedingungsblock (oder
  // ein ELSE-Zweig), dahinter schliesst einer. Ein '{$ENDIF}' davor (etwa
  // der Hilfe an der Anweisung darueber) und '{$R+}' sperren nicht.
  Nb := NonBlankLine(AMap, ALine - 1, -1);
  if (Nb > 0) and (CondOnLine(AMap, Nb, COND_OPEN)
                   or CondOnLine(AMap, Nb, COND_ELSE)) then
    Exit(_(R_DBG_AROUND));
  Nb := NonBlankLine(AMap, ASite.Semi.Line + 1, 1);
  if (Nb > 0) and (CondOnLine(AMap, Nb, COND_CLOSE)
                   or CondOnLine(AMap, Nb, COND_ELSE)) then
    Exit(_(R_DBG_AROUND));
  if InDebugCondition(AMap, ALine) then
    Exit(_(R_DBG_UNDER_DEBUG));
  Result := '';
end;

class function TRdxDebugOutputFix.WrapInDebug(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Site   : TRdxDebugSite;
  Indent : string;
  Last   : Integer;
begin
  AEdit := Default(TRdxEdit);
  AReason := ReadSite(AMap, ALine, AMessage, Site);
  Result := AReason = '';
  if not Result then
    Exit;
  // Der Bereich beginnt auf Spalte 1 der Zeile ALine (sie traegt die
  // Anweisung, ist also nicht leer) und endet hinter der Zeile des ';' -
  // deren Zeilenende bleibt (SpanFits: EndCol - 1 <= Laenge).
  Indent := Copy(AMap.Raw(ALine), 1, Site.Start.Col - 1);
  Last := Site.Semi.Line;
  AEdit.Span := TRefactorSpan.Make(SPAN_017, ALine, 1, Last,
    Length(AMap.Raw(Last)) + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := Indent + DIR_OPEN + #10 + AEdit.Expected + #10 + Indent
    + DIR_CLOSE;
end;

class function TRdxDebugOutputFix.DeleteCall(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Site : TRdxDebugSite;
begin
  AEdit := Default(TRdxEdit);
  AReason := ReadSite(AMap, ALine, AMessage, Site);
  if (AReason = '') and (Site.Prev.Low <> ';')
     and ((Site.Next.Low = '') or InList(Site.Next.Low, LIST_ENDS)) then
    AReason := MsgOnlyStatementEmptyBlock(Site.Prev.Low);
  if (AReason = '') and (Site.Semi.Line >= AMap.LineCount) then
    AReason := _(R_DBG_LAST_LINE);
  Result := AReason = '';
  if not Result then
    Exit;
  // Ganze Zeilen samt Zeilenende: von Spalte 1 der (nicht leeren) Zeile
  // ALine bis Spalte 1 der Zeile hinter dem ';'.
  AEdit.Span := TRefactorSpan.Make(SPAN_017, ALine, 1, Site.Semi.Line + 1, 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := '';
end;

end.
