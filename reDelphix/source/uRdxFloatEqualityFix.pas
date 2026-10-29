unit uRdxFloatEqualityFix;

// reDelphix - Editorhilfe fuer SCA144 FloatEquality, OHNE ToolsAPI und ohne
// Parser (reine Textlogik, laeuft auch im FPC-Pruefstand): der exakte
// Vergleich zweier Gleitkommawerte wird ein Vergleich mit Toleranz.
//     if Ratio = 0.5 then      ->  if SameValue(Ratio, 0.5) then
//     if Ratio = 0 then        ->  if IsZero(Ratio) then
//     while A <> B do          ->  while not SameValue(A, B) do
// System.Math (FPC: Math) fuegt der Adapter in uRdxFixTable an (AppendUses
// wie SysUtils bei SCA085/SCA139); diese Unit liefert nur die Ersetzung
// des Vergleichs und die Gruende.
//
// DER FUND: uFloatEquality meldet die Zeile des Vergleichs, keine Spalte;
// die Meldung nennt den Vergleich als '(<links> <op> <rechts>)' -
// Bezeichner (ohne Punkt) oder Zahlen. Der Planer sucht genau diese drei
// Token auf der Zeile.
//
// AENDERT DAS VERHALTEN (Kennzeichnung, E2): SameValue und IsZero
// vergleichen mit dem Standard-Epsilon von System.Math statt exakt. Das ist
// der Fix - ein gewollt exakter Vergleich (Schalter- oder Sentinelwert)
// bekommt damit eine andere Bedeutung.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - der Vergleich steht nicht (genau einmal) auf der Zeile, ein Kommentar
//     steht darin, oder die Meldung nennt keinen Vergleich;
//   - der Vergleich ist nicht der GANZE Ausdruck einer Bedingung oder
//     Zuweisung: davor steht nicht if/while/until/'('/':='/',', dahinter
//     nicht then/do/')'/';'/','/else/end. Der Operatorrang ist der Grund:
//     'if A = B and C' heisst 'A = (B and C)', 'not A = B' heisst
//     '(not A) = B', und der Detektor meldet bei 'a + b = c' den
//     Teilausdruck 'b = c';
//   - das Waechter-Idiom 'if X = 0 then X := ...' (der exakte Vergleich
//     mit 0 setzt dort einen Vorgabewert - der Detektor stuft es herab);
//   - der then-Zweig prueft einen Operanden selbst mit Toleranz (IsZero,
//     SameValue, SingleSameValue ... mit ihm als Argument): der exakte
//     Vergleich ist dort Absicht - 'if Value <> 0.0 then if
//     SingleSameValue(Value, 0.0) then Value := 0.0' normalisiert fast-null
//     Werte, IsZero davor uebersprange genau sie (Realwelt-Test rwE29,
//     TES5Edit wbDataFormat.pas:3315);
//   - die Datei deklariert selbst ein SameValue bzw. IsZero, oder vor der
//     Zeile steht in der Routine ein 'with' (ein Operand oder die Funktion
//     koennte an ein Member binden).
// Der TYPBEWEIS gehoert in den Adapter (Hausregel uRdxFixTable): er fragt
// DeclaredTypeOf je Bezeichner und reicht die Typen an TypeReason; dazu
// InWithBlock und die Herabstufung des Detektors (fcLow) an ContextReason.
// Bewiesen sein muessen Single, Double, Extended oder Real - Currency ist
// Festkomma und vergleicht exakt, ein unbekannter Typ heisst keine Hilfe
// (der Detektor sammelt Float-Variablen nur nach Namen). Single mit etwas
// anderem als Single (auch einem Literal) gesperrt: die drei Ueberladungen
// von SameValue koennten mehrdeutig sein (E2251).
//
// OHNE ToolsAPI, ohne uEngineApi: bindet nur Code-Sicht, Ersetzung und
// Texte (FPC-tauglich).

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Gruende der Ablehnung als englische msgids (Tests vergleichen mit _()).
  R_FLOAT_MSG = 'the message does not name the comparison';
  R_FLOAT_NO_VAR = 'no variable in "%s"';
  R_FLOAT_MOVED = 'comparison "%s" not on the reported line';
  R_FLOAT_MANY = 'the line has the comparison "%s" more than once - '
    + 'ambiguous';
  R_FLOAT_COMMENT = 'comment inside "%s"';
  R_FLOAT_BEFORE = '"%s" is part of a larger expression ("%s" before it) - '
    + 'only a whole condition or assignment is rewritten';
  R_FLOAT_AFTER = '"%s" is part of a larger expression ("%s" after it) - '
    + 'only a whole condition or assignment is rewritten';
  R_FLOAT_LIST = '"%s" stands in a list that is not a call argument '
    + '(enumeration, set or declaration)';
  R_FLOAT_GUARD = '"%s" guards a default value (if X = 0 then X := ...) - '
    + 'the exact comparison is intended there';
  R_FLOAT_TOLERANT = '"%s" guards a tolerance check of the same value (line '
    + '%d) - the exact comparison is intended there';
  R_FLOAT_OWN = 'the file declares its own %s - it is not the function of '
    + 'System.Math';
  R_FLOAT_WITH = 'with statement in the routine - an operand or %s could '
    + 'bind to a member';
  R_FLOAT_LOW = 'the detector rates the comparison as intended (guard or '
    + 'sentinel value) - the exact comparison is right there';
  R_FLOAT_UNKNOWN = 'type of %s not proven here - only Single, Double, '
    + 'Extended and Real operands are rewritten';
  R_FLOAT_CURRENCY = '%s is Currency - a fixed-point type compares exactly, '
    + 'SameValue would add a tolerance';
  R_FLOAT_NOT_FLOAT = '%s is declared as %s - not Single, Double, Extended '
    + 'or Real';
  R_FLOAT_SINGLE = 'Single %s compared with %s - the SameValue overloads '
    + 'could be ambiguous (E2251)';

  // Die Funktionen der Ersetzung (Name im Menuetext).
  CALL_SAME_VALUE = 'SameValue';
  CALL_IS_ZERO    = 'IsZero';

type
  TRdxFloatEqualityFix = class
  public
    // SCA144: der Vergleich aus der Meldung auf ALine -> SameValue(L, R)
    // bzw. IsZero(X) bei einer Null-Seite, bei '<>' mit 'not' davor. Form
    // von TRdxMapPlanner (uRdxFixRunner).
    class function ToleranceCompare(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Die drei Teile des Vergleichs aus der Meldung
    // ('Float equality (Ratio = 0.5) is ...'); False ohne diese Form.
    class function Operands(const AMessage: string; out ALeft, AOp,
      ARight: string): Boolean; static;

    // Die Funktion der Ersetzung fuer den Menuetext: IsZero, wenn eine
    // Seite eine Null ist (0, 0.0, 00), sonst SameValue; '' ohne Vergleich
    // in der Meldung.
    class function CallName(const AMessage: string): string; static;

    // Eine Zahl (erstes Zeichen eine Ziffer, wie der Detektor sie meldet)
    // statt eines Bezeichners? Der Adapter fragt DeclaredTypeOf nur fuer
    // Bezeichner.
    class function IsLiteral(const AOperand: string): Boolean; static;

    // Typbeweis (Adapter): die deklarierten Typen der beiden Seiten (klein,
    // DeclaredTypeOf; bei einer Zahl gleichgueltig). '' oder der Grund.
    class function TypeReason(const ALeft, ALeftType, ARight,
      ARightType: string): string; static;

    // Was nur der Adapter weiss: der Detektor hat den Fund herabgestuft
    // (fcLow: Waechter- oder Sentinel-Vergleich, exakt gewollt), die Zeile
    // liegt in einem with-Block (InWithBlock). '' oder der Grund.
    class function ContextReason(ALowConfidence, AInWith: Boolean;
      const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,   // TRefactorSpan.Make
  uRdxText;        // _(): in die reDelphix-Sprache, nie uLocalization

const
  SPAN_144 = 'sca144';
  MSG_HEAD = 'Float equality (';
  // Davor beginnt der Vergleich als ganzer Ausdruck.
  FLOAT_BEFORE: array[0..5] of string = ('if', 'while', 'until', '(', ':=',
    ',');
  // Dahinter endet er.
  FLOAT_AFTER: array[0..6] of string = ('then', 'do', ')', ';', ',', 'else',
    'end');
  // Bewiesene Gleitkommatypen (DeclaredTypeOf liefert klein).
  FLOAT_TYPES: array[0..3] of string = ('single', 'double', 'extended',
    'real');
  TYPE_SINGLE   = 'single';
  TYPE_CURRENCY = 'currency';
  // Davor bzw. dahinter deklariert ein Name etwas (DeclaresName).
  DECL_BEFORE: array[0..3] of string = ('property', 'var', 'const', 'out');
  DECL_AFTER: array[0..2] of string = (':', '=', ',');
  // So weit sucht OpenerBefore rueckwaerts (Token).
  MAX_BACK = 400;
  // Auf oberster Ebene beenden diese Token die Suche nach der Klammer.
  LIST_STOP: array[0..7] of string = (';', 'begin', 'then', 'else', 'do',
    'type', 'const', 'var');
  // Diese Woerter oeffnen einen Block mit end (TolerantCheckLine).
  END_OPENERS: array[0..3] of string = ('begin', 'case', 'try', 'asm');
  // Toleranzvergleiche: genau IsZero oder ein Name, der auf SameValue endet
  // (SameValue, SingleSameValue, DoubleSameValue ...).
  CALL_IS_ZERO_LOW = 'iszero';
  SAME_VALUE_LOW = 'samevalue';
  // So weit liest TolerantCheckLine den then-Zweig (Token).
  MAX_BRANCH = 2000;

// Eine Null wie der Detektor sie liest: '0', '00', '0.0', '0.00'.
function IsZeroText(const S: string): Boolean;
var
  i   : Integer;
  Dot : Boolean;
begin
  Result := False;
  if (S = '') or (S[1] <> '0') or (S[Length(S)] = '.') then
    Exit;
  Dot := False;
  for i := 1 to Length(S) do
    if S[i] = '.' then
    begin
      if Dot then
        Exit;
      Dot := True;
    end
    else if S[i] <> '0' then
      Exit;
  Result := True;
end;

class function TRdxFloatEqualityFix.IsLiteral(const AOperand: string): Boolean;
begin
  Result := (AOperand <> '') and CharInSet(AOperand[1], ['0'..'9']);
end;

class function TRdxFloatEqualityFix.Operands(const AMessage: string;
  out ALeft, AOp, ARight: string): Boolean;
var
  P     : Integer;
  Inner : string;
begin
  ALeft := '';
  AOp := '';
  ARight := '';
  Result := False;
  P := Pos(MSG_HEAD, AMessage);
  if P = 0 then
    Exit;
  Inner := Copy(AMessage, P + Length(MSG_HEAD), MaxInt);
  P := Pos(')', Inner);
  if P = 0 then
    Exit;
  Inner := Copy(Inner, 1, P - 1);
  P := Pos(' ', Inner);
  if P = 0 then
    Exit;
  ALeft := Copy(Inner, 1, P - 1);
  Inner := Copy(Inner, P + 1, MaxInt);
  P := Pos(' ', Inner);
  if P = 0 then
    Exit;
  AOp := Copy(Inner, 1, P - 1);
  ARight := Copy(Inner, P + 1, MaxInt);
  Result := (ALeft <> '') and (ARight <> '') and (Pos(' ', ARight) = 0)
    and ((AOp = '=') or (AOp = '<>'));
end;

class function TRdxFloatEqualityFix.CallName(const AMessage: string): string;
var
  L, Op, R : string;
begin
  Result := '';
  if not Operands(AMessage, L, Op, R) then
    Exit;
  if IsZeroText(L) or IsZeroText(R) then
    Result := CALL_IS_ZERO
  else
    Result := CALL_SAME_VALUE;
end;

// Beginnt an T (auf ALine) der Operand AText? Eine Zahl wird zeichenweise
// gelesen - die Code-Sicht zerlegt '0.5' in drei Token -, ein Bezeichner
// als Token. AEndCol: hinter dem Operanden.
function OperandAt(AMap: TRdxCodeMap; ALine: Integer; const T: TRdxToken;
  const AText: string; out AEndCol: Integer): Boolean;
var
  L    : string;
  i, n : Integer;
begin
  Result := False;
  AEndCol := 0;
  if (AText = '') or (T.Low = '') or (T.Line <> ALine) then
    Exit;
  if TRdxFloatEqualityFix.IsLiteral(AText) then
  begin
    L := AMap.Raw(ALine);
    n := Length(AText);
    if not CharInSet(T.Low[1], ['0'..'9']) then
      Exit;
    // Mitten in einer laengeren Zahl ('1.5' fuer die Meldung '5').
    if (T.Col > 1) and (IsIdentChar(L[T.Col - 1]) or (L[T.Col - 1] = '.')) then
      Exit;
    if not SameText(Copy(L, T.Col, n), AText) then
      Exit;
    for i := T.Col to T.Col + n - 1 do
      if not AMap.IsCode(ALine, i) then
        Exit;
    // Die Zahl geht weiter ('0.55' fuer die Meldung '0.5').
    if (T.Col + n <= Length(L))
       and (IsIdentChar(L[T.Col + n]) or (L[T.Col + n] = '.')) then
      Exit;
    AEndCol := T.Col + n;
  end
  else
  begin
    if not T.IsWord or (T.Low <> LowerCase(AText)) then
      Exit;
    AEndCol := T.EndCol;
  end;
  Result := True;
end;

// Deklariert die Datei den Namen ANameLow (klein) selbst - Routine,
// Variable, Feld, Konstante, Property, Parameter, Typ? Ein Treffer zu viel
// sperrt nur. Private Hilfe dieser Unit (uRdxCodeMap kennt nur
// DeclaresRoutine).
function DeclaresName(AMap: TRdxCodeMap; const ANameLow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := True;
  if DeclaresRoutine(AMap, ANameLow) then
    Exit;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ANameLow);
  while T.Low <> '' do
  begin
    if (T.Low = ANameLow)
       and (InList(After(AMap, T).Low, DECL_AFTER)
            or InList(Before(AMap, T).Low, DECL_BEFORE)) then
      Exit;
    T := NextTokenOnLineWith(AMap, T, ANameLow);
  end;
  Result := False;
end;

// Steht vor ATok in seiner Routine ein 'with'? Rueckwaerts bis zum Kopf der
// Routine (IsRoutineHead) bzw. 'implementation'; ein with in einer
// verschachtelten Routine davor zaehlt mit (sperrt nur). Private Hilfe
// dieser Unit (wie TRdxSimpleFixes.WithBefore, ohne die Planer-Unit).
function WithBefore(AMap: TRdxCodeMap; const ATok: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := Before(AMap, ATok);
  while T.Low <> '' do
  begin
    if (T.Low = 'with') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(True);
    if (T.Low = 'implementation') or IsRoutineHead(AMap, T) then
      Exit;
    T := Before(AMap, T);
  end;
end;

// Die oeffnende Klammer ('(' oder '['), in der ATok steht - rueckwaerts
// ueber geschlossene Klammerpaare hinweg; Low = '' ohne, auch wenn vorher
// auf oberster Ebene ein Token aus LIST_STOP kommt oder MAX_BACK Token
// gelesen sind.
function OpenerBefore(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
var
  T     : TRdxToken;
  Depth : Integer;
  Steps : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  Steps := 0;
  T := Before(AMap, ATok);
  while (T.Low <> '') and (Steps < MAX_BACK) do
  begin
    // Rueckwaerts gelesen: ')' schliesst eine Gruppe davor (-1), '('
    // oeffnet die, in der ATok steht, sobald die Tiefe positiv wird.
    Depth := Depth + ParenDelta(T);
    if Depth > 0 then
      Exit(T);
    if (Depth = 0) and InList(T.Low, LIST_STOP) then
      Exit;
    Inc(Steps);
    T := Before(AMap, T);
  end;
end;

// Steht der Vergleich hinter '(' bzw. ',' in einer Argumentliste oder
// geklammerten Bedingung? Nicht in einer Aufzaehlung 'TFoo = (A = 1, B =
// 2)', einer Menge '[..]' oder ohne Klammer (Deklarationsliste).
function InArgumentList(AMap: TRdxCodeMap; const APrev: TRdxToken): Boolean;
var
  O : TRdxToken;
begin
  if APrev.Low = '(' then
    O := APrev
  else
    O := OpenerBefore(AMap, APrev);
  Result := (O.Low = '(') and (Before(AMap, O).Low <> '=');
end;

// Das Waechter-Idiom 'if X = 0 then X := ...' hinter dem Vergleich: ANext
// ist das Token dahinter, AVarLow der Bezeichner (klein).
function IsDefaultGuard(AMap: TRdxCodeMap; const ANext: TRdxToken;
  const AVarLow: string): Boolean;
var
  V : TRdxToken;
begin
  Result := False;
  if ANext.Low <> 'then' then
    Exit;
  V := After(AMap, ANext);
  Result := V.IsWord and (V.Low = AVarLow) and (After(AMap, V).Low = ':=');
end;

// Ist ALow der Name eines Toleranzvergleichs (IsZero, *SameValue)?
function IsToleranceCall(const ALow: string): Boolean;
var
  n : Integer;
begin
  n := Length(SAME_VALUE_LOW);
  Result := (ALow = CALL_IS_ZERO_LOW) or ((Length(ALow) >= n)
    and (Copy(ALow, Length(ALow) - n + 1, n) = SAME_VALUE_LOW));
end;

// Prueft der then-Zweig hinter AThen einen der Bezeichner ANames (klein)
// mit Toleranz - 'IsZero(X)', 'SingleSameValue(X, 0.0)'? Gelesen wird bis
// zum Ende der Anweisung: ';' bzw. else auf Tiefe 0, das end eines
// umschliessenden Blocks; Bloecke mit end (END_OPENERS) zaehlen. Die Zeile
// des Aufrufs, 0 ohne.
function TolerantCheckLine(AMap: TRdxCodeMap; const AThen: TRdxToken;
  const ANames: array of string): Integer;
var
  T, Open, Close, A : TRdxToken;
  Depth, Steps      : Integer;
begin
  Result := 0;
  Depth := 0;
  Steps := 0;
  T := After(AMap, AThen);
  while (T.Low <> '') and (Steps < MAX_BRANCH) do
  begin
    if InList(T.Low, END_OPENERS) then
      Inc(Depth)
    else if T.Low = 'end' then
    begin
      Dec(Depth);
      if Depth < 0 then
        Exit;
    end
    else if (Depth = 0) and ((T.Low = ';') or (T.Low = 'else')) then
      Exit
    else if T.IsWord and IsToleranceCall(T.Low) then
    begin
      Open := After(AMap, T);
      if Open.Low = '(' then
      begin
        Close := MatchClose(AMap, Open);
        A := After(AMap, Open);
        while (Close.Low <> '') and (A.Low <> '') and TokBefore(A, Close) do
        begin
          if A.IsWord and InList(A.Low, ANames) then
            Exit(T.Line);
          A := After(AMap, A);
        end;
      end;
    end;
    Inc(Steps);
    T := After(AMap, T);
  end;
end;

class function TRdxFloatEqualityFix.ToleranceCompare(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Left, Op, Right, Cmp, Call, Raw, Args, VarText : string;
  T, OpTok, RTok, LTok, P, N : TRdxToken;
  LEnd, REnd, Count, FirstREnd : Integer;
  ZeroLeft, ZeroRight : Boolean;
  Names : array[0..1] of string;
  Li    : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  if not Operands(AMessage, Left, Op, Right) then
  begin
    AReason := _(R_FLOAT_MSG);
    Exit;
  end;
  Cmp := Left + ' ' + Op + ' ' + Right;
  if IsLiteral(Left) and IsLiteral(Right) then
  begin
    AReason := _(R_FLOAT_NO_VAR, [Cmp]);
    Exit;
  end;
  if (ALine < 1) or (ALine > AMap.LineCount) then
  begin
    AReason := MsgMovedSuffix(_(R_FLOAT_MOVED, [Cmp]));
    Exit;
  end;

  // Genau ein Vorkommen der drei Token auf der Zeile (Code-Sicht).
  Count := 0;
  FirstREnd := 0;
  LTok := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if OperandAt(AMap, ALine, T, Left, LEnd) then
    begin
      OpTok := NextToken(AMap, ALine, LEnd);
      if (OpTok.Line = ALine) and (OpTok.Low = Op) then
      begin
        RTok := After(AMap, OpTok);
        if OperandAt(AMap, ALine, RTok, Right, REnd) then
        begin
          Inc(Count);
          if Count = 1 then
          begin
            LTok := T;
            FirstREnd := REnd;
          end;
        end;
      end;
    end;
    T := After(AMap, T);
  end;
  if Count = 0 then
  begin
    AReason := MsgMovedSuffix(_(R_FLOAT_MOVED, [Cmp]));
    Exit;
  end;
  if Count > 1 then
  begin
    AReason := _(R_FLOAT_MANY, [Cmp]);
    Exit;
  end;
  REnd := FirstREnd;
  if AMap.HasNonCode(ALine, LTok.Col, REnd - 1) then
  begin
    AReason := _(R_FLOAT_COMMENT, [Cmp]);
    Exit;
  end;

  // Der ganze Ausdruck: Grenzen links und rechts (Operatorrang, s. Kopf).
  P := Before(AMap, LTok);
  if not InList(P.Low, FLOAT_BEFORE) then
  begin
    AReason := _(R_FLOAT_BEFORE, [Cmp, TokText(AMap, P)]);
    Exit;
  end;
  N := NextToken(AMap, ALine, REnd);
  if not InList(N.Low, FLOAT_AFTER) then
  begin
    AReason := _(R_FLOAT_AFTER, [Cmp, TokText(AMap, N)]);
    Exit;
  end;
  if ((P.Low = '(') or (P.Low = ',')) and not InArgumentList(AMap, P) then
  begin
    AReason := _(R_FLOAT_LIST, [Cmp]);
    Exit;
  end;

  Raw := AMap.Raw(ALine);
  ZeroLeft := IsZeroText(Left);
  ZeroRight := IsZeroText(Right);
  if ZeroRight then
    VarText := Copy(Raw, LTok.Col, Length(Left))
  else
    VarText := Copy(Raw, REnd - Length(Right), Length(Right));
  if (ZeroLeft or ZeroRight)
     and IsDefaultGuard(AMap, N, LowerCase(VarText)) then
  begin
    AReason := _(R_FLOAT_GUARD, [Cmp]);
    Exit;
  end;
  if N.Low = 'then' then
  begin
    // Literale nennt der Zweig nicht als Bezeichner - '' passt nie.
    if IsLiteral(Left) then
      Names[0] := ''
    else
      Names[0] := LowerCase(Left);
    if IsLiteral(Right) then
      Names[1] := ''
    else
      Names[1] := LowerCase(Right);
    Li := TolerantCheckLine(AMap, N, Names);
    if Li > 0 then
    begin
      AReason := _(R_FLOAT_TOLERANT, [Cmp, Li]);
      Exit;
    end;
  end;

  Call := CallName(AMessage);
  if DeclaresName(AMap, LowerCase(Call)) then
  begin
    AReason := _(R_FLOAT_OWN, [Call]);
    Exit;
  end;
  if WithBefore(AMap, LTok) then
  begin
    AReason := _(R_FLOAT_WITH, [Call]);
    Exit;
  end;

  if ZeroLeft or ZeroRight then
    Args := VarText
  else
    Args := Copy(Raw, LTok.Col, Length(Left)) + ', '
      + Copy(Raw, REnd - Length(Right), Length(Right));
  AEdit.Span := TRefactorSpan.Make(SPAN_144, ALine, LTok.Col, ALine, REnd);
  AEdit.Expected := Copy(Raw, LTok.Col, REnd - LTok.Col);
  AEdit.NewText := Call + '(' + Args + ')';
  if Op = '<>' then
    AEdit.NewText := 'not ' + AEdit.NewText;
  Result := True;
end;

// Ein Operand: eine Zahl braucht keinen Beweis, ein Bezeichner einen
// Gleitkommatyp. '' oder der Grund.
function OperandTypeReason(const AName, ATypeLow: string): string;
begin
  Result := '';
  if TRdxFloatEqualityFix.IsLiteral(AName) or InList(ATypeLow, FLOAT_TYPES) then
    Exit;
  if ATypeLow = '' then
    Result := _(R_FLOAT_UNKNOWN, [AName])
  else if ATypeLow = TYPE_CURRENCY then
    Result := _(R_FLOAT_CURRENCY, [AName])
  else
    Result := _(R_FLOAT_NOT_FLOAT, [AName, ATypeLow]);
end;

class function TRdxFloatEqualityFix.TypeReason(const ALeft, ALeftType,
  ARight, ARightType: string): string;
var
  LSingle, RSingle : Boolean;
begin
  Result := OperandTypeReason(ALeft, LowerCase(ALeftType));
  if Result = '' then
    Result := OperandTypeReason(ARight, LowerCase(ARightType));
  if Result <> '' then
    Exit;
  // IsZero hat nur ein Argument - eine Single-Seite ist dort eindeutig.
  if IsZeroText(ALeft) or IsZeroText(ARight) then
    Exit;
  LSingle := (not IsLiteral(ALeft)) and SameText(ALeftType, TYPE_SINGLE);
  RSingle := (not IsLiteral(ARight)) and SameText(ARightType, TYPE_SINGLE);
  if LSingle and not RSingle then
    Result := _(R_FLOAT_SINGLE, [ALeft, ARight])
  else if RSingle and not LSingle then
    Result := _(R_FLOAT_SINGLE, [ARight, ALeft]);
end;

class function TRdxFloatEqualityFix.ContextReason(ALowConfidence,
  AInWith: Boolean; const AMessage: string): string;
var
  Call : string;
begin
  Result := '';
  if ALowConfidence then
    Exit(_(R_FLOAT_LOW));
  if AInWith then
  begin
    Call := CallName(AMessage);
    if Call = '' then
      Call := CALL_SAME_VALUE;
    Result := _(R_FLOAT_WITH, [Call]);
  end;
end;

end.
