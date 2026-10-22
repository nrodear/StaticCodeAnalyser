unit uRdxEmptyFinallyFix;

// reDelphix - Editorhilfe SCA083 EmptyFinallyBlock, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11):
//   'try A; B; finally end;' -> 'A; B;' - try, finally und end fallen weg,
//   der Rumpf rueckt eine Stufe aus. Ein try..finally ohne Aufraeum-Code
//   tut nichts: Ausnahmen laufen weiter nach aussen, Exit/Break/Continue
//   springen wie vorher. Gleiche Bedeutung.
//
// WAS DER DETEKTOR MELDET (uEmptyFinallyBlock): das Wort finally, dahinter
// nur Leerraum und end - auf der Text-Sicht OHNE Kommentare. Er meldet also
// auch 'finally // TODO: Obj freigeben' und 'finally {$IFDEF X} end'; die
// Meldung traegt weder Spalte noch Namen, nur die Zeile des finally.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * Kommentar oder Direktive zwischen finally und end - ein Kommentar ist
//     Absicht ('//dec(FUpdateLock)', 'TODO'), keine Hilfe;
//   * auf der Zeile nicht genau ein finally (kein Treffer = Zeile
//     verschoben, mehrere = mehrdeutig); das zugehoerige try nicht per
//     Blockpaarung (begin/case/try/asm/record gegen end) zu finden;
//   * das try steht nicht in einer Anweisungsliste (davor ';', begin, try,
//     finally, except, repeat, initialization, finalization): hinter then,
//     else, do oder einer Marke braeuchte der Rumpf ein begin..end (der
//     mORMot-Fall 'if C then try X finally end') - eine eigene Hilfe, nicht
//     diese;
//   * try, finally und end stehen nicht je allein auf ihren Zeilen (nur
//     'finally end;' auf EINER Zeile geht), Kommentar oder Code dahinter;
//   * var, const, label, goto oder asm im Rumpf (ein Inline-var gilt dann
//     im umgebenden Block, ein Sprungziel verliert seinen Block; var und
//     const nur auf der obersten Ebene - in einem geschachtelten
//     begin..end bleibt der Block, in Klammern sind sie Parameter-
//     modifikatoren einer anonymen Methode), eine
//     Direktive in den Zeilen, ein Block-Kommentar oder mehrzeiliger String,
//     der eine Rumpfzeile beginnt (Einruecken aendert ihn);
//   * eine Rumpfzeile, die nicht mit der Einrueckung der ersten
//     Rumpfzeile beginnt (Fortsetzungs- und Kommentarzeilen am Rand) - das
//     Ausruecken liesse sie ungleich zurueck;
//   * ein leerer Rumpf (es bliebe nichts).
// Fehlt dem Rumpf das ';' vor finally und folgt auf end ein ';', setzt der
// Planer es hinter die letzte Anweisung (vor einen Kommentar auf der Zeile):
// das ';' hinter end gehoert sonst der Anweisung davor.
//
// Der Planer ersetzt EINEN Bereich (try-Zeile bis end-Zeile) durch den
// ausgerueckten Rumpf; Zeilenenden und Einrueckungsart (Tab oder Leerzeichen)
// des Umfelds bleiben.

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

const
  R_EFB_NOT_EMPTY = 'der finally-Block ist nicht leer';
  R_EFB_COMMENT   = 'Kommentar oder Direktive im finally-Block - Absicht, '
    + 'keine Hilfe';
  R_EFB_NO_TRY    = 'das zugehoerige try ist nicht eindeutig zu finden';
  R_EFB_BRANCH    = 'das try steht hinter then, else, do oder einer Marke - '
    + 'ohne begin..end verlore der Zweig seinen Rumpf';
  R_EFB_TRY_LINE  = 'try steht nicht allein auf seiner Zeile (Code oder '
    + 'Kommentar daneben)';
  R_EFB_FIN_LINE  = 'finally und end stehen nicht allein auf ihren Zeilen '
    + '(Code oder Kommentar daneben)';
  R_EFB_END_TAIL  = 'hinter end folgt weder ";" noch das Ende des '
    + 'umgebenden Blocks';
  R_EFB_SPECIAL   = 'der Rumpf enthaelt var, const, label, goto oder asm - '
    + 'Gueltigkeitsbereich oder Sprungziel aendert sich';
  R_EFB_DIRECTIVE = 'Compiler-Direktive im try..end';
  R_EFB_MULTILINE = 'der Rumpf beginnt in einem Block-Kommentar oder '
    + 'mehrzeiligen String';
  R_EFB_EMPTY_BODY = 'der try-Rumpf ist leer';
  R_EFB_INDENT    = 'Einrueckung des Rumpfs uneinheitlich - Zeile %d';

type
  // Der Planer von SCA083 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxEmptyFinallyFix = class
  public
    // ALine ist die Zeile des finally (die Meldung traegt keine Spalte);
    // AMessage wird nicht gebraucht. Liefert die eine Ersetzung von der
    // try-Zeile bis zur end-Zeile oder den Grund.
    class function Unwrap(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;     // TRefactorSpan.Make

const
  SPAN_083 = 'sca083';
  // Davor beginnt eine Anweisung IN einer Anweisungsliste.
  LIST_PREV: array[0..7] of string = (';', 'begin', 'try', 'finally',
    'except', 'repeat', 'initialization', 'finalization');
  // Hinter 'end' ohne ';' darf nur das Ende des umgebenden Blocks folgen.
  FOLLOW_OK: array[0..3] of string = ('end', 'until', 'finally', 'except');
  // Im Rumpf gesperrt (s. Kopf).
  BODY_BAD: array[0..4] of string = ('var', 'const', 'label', 'goto', 'asm');
  // Davon nur auf der obersten Ebene des Rumpfs: ein Inline-var in einem
  // geschachtelten begin..end behaelt seinen Block, ein 'const'/'var' in
  // Klammern ist ein Parametermodifikator (anonyme Methode).
  SCOPE_WORDS: array[0..1] of string = ('var', 'const');
  // Hier beginnt der zweite Teil eines try - gehoert nicht in den Rumpf.
  TRY_PART_WORDS: array[0..1] of string = ('finally', 'except');
  KW_FINALLY = 'finally';
  KW_TRY     = 'try';
  KW_END     = 'end';
  SQUEEZED_FINALLY_END  = 'finallyend';
  SQUEEZED_FINALLY_ENDS = 'finallyend;';

type
  // Die drei Schluesselwoerter des Konstrukts.
  TTryParts = record
    TryTok : TRdxToken;
    Fin    : TRdxToken;
    EndTok : TRdxToken;
  end;

// Ist T das Schluesselwort finally (kein 'X.Finally', kein '&Finally')?
function IsFinallyKeyword(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := (T.Low = KW_FINALLY) and IsKeywordAfter(T, Before(AMap, T));
end;

// Genau ein finally auf ALine. '' oder der Grund.
function FindFinally(AMap: TRdxCodeMap; ALine: Integer;
  out AFin: TRdxToken): string;
var
  S : TRdxLineSearch;
begin
  S := Default(TRdxLineSearch);
  S.Test    := IsFinallyKeyword;
  S.What    := 'kein finally';
  S.ManyFmt := '%d finally';
  Result := OneTokenOnLine(AMap, ALine, S, AFin);
end;

// Zwischen finally und end nur Leerraum?
function BlankBetween(AMap: TRdxCodeMap; const AFin, AEnd: TRdxToken): Boolean;
var
  Li, j, First, Last : Integer;
  L                  : string;
begin
  Result := True;
  for Li := AFin.Line to AEnd.Line do
  begin
    L := AMap.Raw(Li);
    First := 1;
    Last := Length(L);
    if Li = AFin.Line then
      First := AFin.EndCol;
    if Li = AEnd.Line then
      Last := AEnd.Col - 1;
    for j := First to Last do
      if not IsBlank(L[j]) then
        Exit(False);
  end;
end;

// Steht hinter finally das end, und dazwischen nichts als Leerraum? Sonst
// nicht leer bzw. ein Kommentar darin (der Detektor sieht Kommentare nicht).
function EmptyReason(AMap: TRdxCodeMap; const AFin: TRdxToken;
  out AEnd: TRdxToken): string;
begin
  Result := '';
  AEnd := After(AMap, AFin);
  if (AEnd.Low <> KW_END) or not IsKeywordAfter(AEnd, AFin) then
    Exit(R_EFB_NOT_EMPTY);
  if not BlankBetween(AMap, AFin, AEnd) then
    Result := R_EFB_COMMENT;
end;

// Das try zum finally: die end-Bilanz rueckwaerts (end +1, Oeffner -1; der
// Oeffner auf Tiefe 0 muss ein try sein). Dabei ein Wort aus BODY_BAD im
// Rumpf -> Sperre; var/const nur auf Block- und Klammertiefe 0
// (SCOPE_WORDS).
function FindTry(AMap: TRdxCodeMap; const AFin: TRdxToken;
  out ATry: TRdxToken): string;
var
  T, P  : TRdxToken;
  Depth : Integer;
  Paren : Integer;
begin
  Result := R_EFB_NO_TRY;
  ATry := Default(TRdxToken);
  Depth := 0;
  Paren := 0;
  T := Before(AMap, AFin);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    // Rueckwaerts oeffnet ein Schliesser die Klammerebene.
    Dec(Paren, ParenDelta(T));
    if IsKeywordAfter(T, P) then
    begin
      if InList(T.Low, BODY_BAD)
         and (((Depth = 0) and (Paren = 0)) or not InList(T.Low, SCOPE_WORDS)) then
        Exit(R_EFB_SPECIAL);
      if T.Low = KW_END then
        Inc(Depth)
      else if IsEndOpener(T.Low) then
      begin
        if Depth = 0 then
        begin
          if T.Low = KW_TRY then
          begin
            ATry := T;
            Result := '';
          end;
          Exit;
        end;
        Dec(Depth);
      end
      else if (Depth = 0) and InList(T.Low, TRY_PART_WORDS) then
        Exit;
    end;
    T := P;
  end;
end;

// Das end, das die Bilanz ab dem try schliesst, ist das end hinter finally,
// und das try steht in einer Anweisungsliste.
function ContextReason(AMap: TRdxCodeMap; const AParts: TTryParts): string;
var
  E2, Last, P : TRdxToken;
begin
  Result := '';
  BlockEnd(AMap, AParts.TryTok, nil, E2, Last);
  if not SameTok(E2, AParts.EndTok) then
    Exit(R_EFB_NO_TRY);
  P := Before(AMap, AParts.TryTok);
  if not InList(P.Low, LIST_PREV) then
    Result := R_EFB_BRANCH;
end;

// try, finally und end je allein auf ihren Zeilen ('finally end;' auf einer
// Zeile geht). ASemi: das end traegt das ';'. Ohne ';' darf nur das Ende des
// umgebenden Blocks folgen.
function LayoutReason(AMap: TRdxCodeMap; const AParts: TTryParts;
  out ASemi: Boolean): string;
var
  Li     : Integer;
  Joined : string;
  Nx     : TRdxToken;
begin
  Result := '';
  ASemi := False;
  if Squeezed(AMap.Raw(AParts.TryTok.Line)) <> KW_TRY then
    Exit(R_EFB_TRY_LINE);
  Joined := '';
  for Li := AParts.Fin.Line to AParts.EndTok.Line do
    Joined := Joined + Squeezed(AMap.Raw(Li));
  if Joined = SQUEEZED_FINALLY_ENDS then
    ASemi := True
  else if Joined = SQUEEZED_FINALLY_END then
  begin
    Nx := After(AMap, AParts.EndTok);
    if not (IsKeywordAfter(Nx, AParts.EndTok) and InList(Nx.Low, FOLLOW_OK)) then
      Result := R_EFB_END_TAIL;
  end
  else
    Result := R_EFB_FIN_LINE;
end;

// Direktive im try..end, Rumpfzeile mitten in einem Kommentar oder String.
function BodyReason(AMap: TRdxCodeMap; const AParts: TTryParts): string;
var
  Li : Integer;
begin
  Result := '';
  if DirectiveInLines(AMap, AParts.TryTok.Line, AParts.EndTok.Line) then
    Exit(R_EFB_DIRECTIVE);
  for Li := AParts.TryTok.Line + 1 to AParts.EndTok.Line do
    if AMap.StartsInside(Li) then
      Exit(R_EFB_MULTILINE);
end;

// Eine Stufe, um die der Rumpf unter dem try eingerueckt ist: die erste
// Rumpfzeile, die nicht mit einem Kommentar beginnt. '' (Rumpf auf der
// Ebene des try) geht; weniger Einrueckung oder eine andere Art nicht.
function StepReason(AMap: TRdxCodeMap; const AParts: TTryParts;
  out AStep: string): string;
var
  Li, Col  : Integer;
  Tr, Deep : string;
begin
  Result := '';
  AStep := '';
  Tr := IndentOf(AMap.Raw(AParts.TryTok.Line));
  for Li := AParts.TryTok.Line + 1 to AParts.Fin.Line - 1 do
  begin
    Col := SkipBlanks(AMap.Raw(Li), 1);
    if (Col > Length(AMap.Raw(Li))) or (AMap.ClassAt(Li, Col) = 'k') then
      Continue;
    Deep := IndentOf(AMap.Raw(Li));
    if Deep = Tr then
      Exit;
    if (Length(Deep) > Length(Tr)) and (Copy(Deep, 1, Length(Tr)) = Tr) then
      AStep := Copy(Deep, Length(Tr) + 1, MaxInt)
    else
      Result := Format(R_EFB_INDENT, [Li]);
    Exit;
  end;
  Result := R_EFB_EMPTY_BODY;
end;

// Die Rumpfzeilen ohne die Stufe AStep hinter der Einrueckung des try,
// mit #10 verbunden. ASemiLine/ASemiCol: hinter dieser Zeichen-Spalte kommt
// ein ';' dazu (ASemiLine = 0: keines). '' im Grund, sonst die erste Zeile
// ohne die erwartete Einrueckung.
function DedentedBody(AMap: TRdxCodeMap; const AParts: TTryParts;
  const AStep: string; ASemiLine, ASemiCol: Integer;
  out ABody: string): string;
var
  SB          : TStringBuilder;
  Li          : Integer;
  L, Tr, Pref : string;
begin
  Result := '';
  Tr := IndentOf(AMap.Raw(AParts.TryTok.Line));
  Pref := Tr + AStep;
  SB := TStringBuilder.Create;
  try
    for Li := AParts.TryTok.Line + 1 to AParts.Fin.Line - 1 do
    begin
      L := AMap.Raw(Li);
      if Li = ASemiLine then
        L := Copy(L, 1, ASemiCol) + ';' + Copy(L, ASemiCol + 1, MaxInt);
      if SkipBlanks(L, 1) <= Length(L) then
      begin
        if Copy(L, 1, Length(Pref)) <> Pref then
          Exit(Format(R_EFB_INDENT, [Li]));
        L := Tr + Copy(L, Length(Pref) + 1, MaxInt);
      end;
      if Li > AParts.TryTok.Line + 1 then
        SB.Append(#10);
      SB.Append(L);
    end;
    ABody := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Die Ersetzung selbst: try-Zeile bis end-Zeile durch den ausgerueckten
// Rumpf.
function BuildEdit(AMap: TRdxCodeMap; const AParts: TTryParts; ASemi: Boolean;
  out AEdit: TRdxEdit): string;
var
  Step, Body     : string;
  SemiLine, SemiCol, AddLine : Integer;
begin
  Result := StepReason(AMap, AParts, Step);
  if Result <> '' then Exit;
  // Das letzte Zeichen des Rumpfs (Code oder String); ein fehlendes ';'
  // setzt der Planer dahinter, wenn das end eines traegt.
  if not LastCharBefore(AMap, AParts.Fin, SemiLine, SemiCol)
     or (SemiLine <= AParts.TryTok.Line) then
    Exit(R_EFB_EMPTY_BODY);
  AddLine := 0;
  if ASemi and not ((AMap.Raw(SemiLine)[SemiCol] = ';')
                    and AMap.IsCode(SemiLine, SemiCol)) then
    AddLine := SemiLine;
  Result := DedentedBody(AMap, AParts, Step, AddLine, SemiCol, Body);
  if Result <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_083, AParts.TryTok.Line, 1,
    AParts.EndTok.Line, Length(AMap.Raw(AParts.EndTok.Line)) + 1);
  AEdit.Expected := RangeText(AMap, AEdit.Span);
  AEdit.NewText := Body;
end;

{ TRdxEmptyFinallyFix }

class function TRdxEmptyFinallyFix.Unwrap(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Parts : TTryParts;
  Semi  : Boolean;
begin
  AEdit := Default(TRdxEdit);
  Parts := Default(TTryParts);
  Semi := False;
  AReason := FindFinally(AMap, ALine, Parts.Fin);
  if AReason = '' then
    AReason := EmptyReason(AMap, Parts.Fin, Parts.EndTok);
  if AReason = '' then
    AReason := FindTry(AMap, Parts.Fin, Parts.TryTok);
  if AReason = '' then
    AReason := ContextReason(AMap, Parts);
  if AReason = '' then
    AReason := LayoutReason(AMap, Parts, Semi);
  if AReason = '' then
    AReason := BodyReason(AMap, Parts);
  if AReason = '' then
    AReason := BuildEdit(AMap, Parts, Semi, AEdit);
  Result := AReason = '';
  if not Result then
    AEdit := Default(TRdxEdit);
end;

end.
