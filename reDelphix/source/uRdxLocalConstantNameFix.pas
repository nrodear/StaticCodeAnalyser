unit uRdxLocalConstantNameFix;

// reDelphix - Editorhilfe fuer SCA119 LocalConstantName, OHNE ToolsAPI und
// ohne Parser: die lokale Konstante 'MaxRetries = 3' im Deklarationsteil
// einer Routine heisst danach 'MAX_RETRIES', und mit ihr jeder Verweis in
// der Routine (auch in lokalen Routinen dahinter, die sie sehen). Ausserhalb
// der Routine bleibt alles, wie es ist; Kommentare und Strings sieht die
// Code-Sicht nicht als Code - sie behalten den alten Namen.
//
// DER FUND: uNamingExt meldet die Konstanten der const-Abschnitte, die
// DIREKTE Kinder einer Methode sind - lokale Routinen verwirft der Parser
// (uParser2.ParseMethodImpl), Inline-Konstanten im Rumpf meldet der
// Detektor bewusst nicht. Zeile ist die des Namens, die Meldung nennt Name
// und Routine: 'Local const MaxRetries in TFoo.Bar - consider
// UPPER_SNAKE_CASE ...'. Ausgenommen sind Namen bis zwei Zeichen, solche
// schon in UPPER_SNAKE_CASE (nur A-Z, 0-9, '_'), String-/Char-Konstanten,
// strukturierte Konstanten und typisierte Konstanten, denen die Routine
// zuweist.
//
// DER NEUE NAME (UpperSnakeOf): vor einem Grossbuchstaben ein '_', wenn
// davor ein Kleinbuchstabe oder eine Ziffer steht oder er ein Akronym
// beendet (davor gross, dahinter klein), dann alles gross - 'MaxRetries'
// -> 'MAX_RETRIES', 'HTTPPort' -> 'HTTP_PORT', 'cMax' -> 'C_MAX',
// 'Base64Len' -> 'BASE64_LEN'; vorhandene '_' bleiben. Das Ergebnis traegt
// nur A-Z, 0-9 und '_' - der Detektor schweigt danach. Ein Praefix wie 'c'
// ist Namenswahl: den Namen kann der Benutzer danach von Hand kuerzen.
//
// BEDEUTUNGSGLEICH, weil die Konstante in ihrer Routine jeden gleichen
// Namen verschattet und JEDER Verweis darauf mit umbenannt wird:
//   - der neue Name kommt im Code der Datei nicht vor (Gross/klein egal;
//     nur Gross/klein geaendert - 'Max' -> 'MAX' - ist derselbe Bezeichner,
//     dann entfaellt die Frage),
//   - umbenannt werden die Verweise HINTER der Deklaration bis zum Ende der
//     Routine; ein Verweis mit Punkt davor ('Self.MaxRetries') ist ein
//     Member und bleibt.
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - keine Deklaration 'Name =' bzw. 'Name:' der Meldung auf der Zeile
//     (verschoben), mehrere, nicht in einem const-Abschnitt, nicht im
//     Deklarationsteil einer Routine, eine andere Routine als die der
//     Meldung, unsichere Routinengrenzen,
//   - Kommentar oder Direktive in der Deklaration (bis zu ihrem ';'),
//   - ein 'with' in der Routine (ein Verweis koennte ein Member sein),
//     ein {$I} in der Routine, eine Direktive in der Routine nennt den
//     Namen ('{$IF MaxRetries > 2}'), eine Direktive der Datei den neuen,
//   - der Name steht in der Routine VOR der Deklaration (dort meint er etwas
//     anderes),
//   - der Name wird hinter der Deklaration neu deklariert oder als Name
//     benutzt: Parameter, Variable, Konstante, Typ, Marke oder Routine einer
//     lokalen Routine bzw. anonymen Methode, Feld eines lokalen Records,
//     Feldname in einer Record-Konstante, Inline-'var'/'const' im Rumpf,
//     'Name :=' (benanntes Argument), '@@Name' (asm-Marke) - im
//     Deklarationsteil vorsichtig auch '(Name)', '(Name, ..' und ', Name)'
//     (Aufzaehlung oder Konstantenliste),
//   - Zeichen ausserhalb A-Z, a-z, 0-9, '_' im Namen (UPPER_SNAKE_CASE
//     kann sie nicht tragen), ein Name schon in UPPER_SNAKE_CASE (Fund
//     veraltet).
//
// MEHRERE ERSETZUNGEN je Fund (wie SCA164/SCA147, uRdxRoutineFixes): je
// Verweis eine, in EINEM Undo-Schritt. Den Adapter fuer die Tabelle
// (TRdxFixFrame mit eigener Plan-Form) schreibt uRdxFixTable; diese Unit
// ist reine Textlogik (Code-Sicht, Routinengrenzen aus uRdxBlocks,
// uRdxText) - sie laeuft auch im FPC-Pruefstand.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_LCN_FORM = 'the message does not name the constant and its routine';
  R_LCN_NON_ASCII = 'the name "%s" contains characters outside A-Z, a-z, 0-9 '
    + 'and "_" - UPPER_SNAKE_CASE cannot hold them';
  R_LCN_STALE = 'the constant "%s" is already written in UPPER_SNAKE_CASE';
  R_LCN_MOVED = 'no declaration of the constant "%s" on the reported line';
  R_LCN_MANY = 'the line declares "%s" more than once';
  R_LCN_NOT_CONST = '"%s" on the reported line is not declared in a const '
    + 'section';
  R_LCN_NO_ROUTINE = '"%s" is not declared in the declaration part of a '
    + 'routine';
  R_LCN_BOUNDS = 'the bounds of the routine around "%s" are not safe to read';
  R_LCN_OTHER_ROUTINE = 'the constant stands in the routine %s, the finding '
    + 'names %s';
  R_LCN_COMMENT = 'comment or compiler directive in the declaration of "%s"';
  R_LCN_NO_END = 'end of the declaration of "%s" not found';
  R_LCN_WITH = 'with statement in the routine - a use of "%s" could be a '
    + 'member of the with expression';
  R_LCN_INCLUDE = 'include file in the routine (line %d) - it may use "%s"';
  R_LCN_DIRECTIVE = 'a compiler directive names "%s"';
  R_LCN_TAKEN = 'the name "%s" already occurs in the code of the file';
  R_LCN_BEFORE = '"%s" occurs on line %d before its declaration - there it '
    + 'means something else';
  R_LCN_SHADOW = 'line %d declares "%s" again or uses it as a name '
    + '(parameter, field, nested declaration)';
  R_LCN_NAMED_ARG = '"%s :=" on line %d - a named argument or an assignment';

type
  // Ergebnis des Planers: alle Ersetzungen (EIN Undo-Schritt) und der neue
  // Name fuer den Menuetext ('Rename ... to %s') - schon gesetzt, wenn der
  // Planer erst spaeter ablehnt. OldName: der Name aus der Meldung.
  TRdxLocalConstantNamePlan = record
    Edits   : TArray<TRdxEdit>;
    OldName : string;
    Name    : string;
  end;

  TRdxLocalConstantNameFix = class
  public
    // SCA119: die lokale Konstante der Meldung auf ALine in UPPER_SNAKE_CASE
    // umbenennen, mit allen Verweisen der Routine (s. Kopf). Die Form von
    // TRdxPlannerOf<TRdxLocalConstantNamePlan> (uRdxFixTable).
    class function RenameConstant(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxLocalConstantNamePlan;
      out AReason: string): Boolean; static;
    // Name und Routine aus der Meldung ('Local const X in R - consider
    // ...'); '' ohne diese Form.
    class function ConstNameOf(const AMessage: string;
      out ARoutine: string): string; static;
    // AName in UPPER_SNAKE_CASE (s. Kopf); nur fuer ASCII-Namen gedacht.
    class function UpperSnakeOf(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxBlocks,       // TRdxBlocks.HeadBefore/ReadRoutine, TRdxRoutine
  uRdxText;         // _(), MsgMovedSuffix, MsgStaleSuffix

const
  SPAN_119 = 'sca119';
  KEY_HEAD = 'Local const ';
  KEY_IN   = ' in ';
  KEY_TAIL = ' - consider';
  // Hier endet die Suche nach der Routine um die Deklaration.
  UNIT_BOUNDS: array[0..6] of string = ('implementation', 'interface',
    'initialization', 'finalization', 'unit', 'program', 'library');
  // Rueckwaerts ab der Deklaration: das erste dieser Woerter nennt den
  // Abschnitt (nur 'const' ist richtig).
  SECTION_WORDS: array[0..14] of string = ('const', 'var', 'type', 'label',
    'threadvar', 'resourcestring', 'begin', 'asm', 'end', 'procedure',
    'function', 'constructor', 'destructor', 'operator', 'implementation');
  // Davor wird ein Name deklariert (Abschnitt, Parametermodifizierer).
  DECL_WORDS: array[0..7] of string = ('var', 'const', 'type', 'out',
    'constref', 'label', 'threadvar', 'resourcestring');
  // Davor und dahinter (DECL_NEXT) steht im Deklarationsteil ein Name in
  // einer Liste: Parameter, Aufzaehlung, Variablen ('(A, B: T)', '(X)').
  DECL_PREV: array[0..2] of string = (';', '(', ',');
  DECL_NEXT: array[0..3] of string = (',', ')', ';', '=');
  // Inline-Deklarationen im Rumpf.
  INLINE_WORDS: array[0..1] of string = ('var', 'const');

class function TRdxLocalConstantNameFix.UpperSnakeOf(
  const AName: string): string;
var
  i     : Integer;
  C, Pv : Char;
begin
  Result := '';
  for i := 1 to Length(AName) do
  begin
    C := AName[i];
    if (i > 1) and CharInSet(C, ['A'..'Z']) then
    begin
      Pv := AName[i - 1];
      if CharInSet(Pv, ['a'..'z', '0'..'9'])
         or (CharInSet(Pv, ['A'..'Z']) and (i < Length(AName))
             and CharInSet(AName[i + 1], ['a'..'z'])) then
        Result := Result + '_';
    end;
    Result := Result + UpCase(C);
  end;
end;

class function TRdxLocalConstantNameFix.ConstNameOf(const AMessage: string;
  out ARoutine: string): string;
var
  P, Q, R : Integer;
begin
  Result := '';
  ARoutine := '';
  P := Pos(KEY_HEAD, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_HEAD));
  Q := Pos(KEY_IN, AMessage, P);
  if Q <= P then Exit;
  R := Pos(KEY_TAIL, AMessage, Q);
  if R <= Q + Length(KEY_IN) then Exit;
  Result := Copy(AMessage, P, Q - P);
  ARoutine := Copy(AMessage, Q + Length(KEY_IN), R - Q - Length(KEY_IN));
end;

// Nur ASCII-Bezeichnerzeichen, erstes keine Ziffer.
function IsAsciiName(const S: string): Boolean;
var
  i : Integer;
begin
  Result := (S <> '') and not CharInSet(S[1], ['0'..'9']);
  for i := 1 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(False);
end;

// Wie uNamingExt.IsUpperSnake: nur A-Z, 0-9, '_'.
function IsUpperSnake(const S: string): Boolean;
var
  i : Integer;
begin
  Result := S <> '';
  for i := 1 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', '0'..'9', '_']) then
      Exit(False);
end;

// Die Deklaration 'ALow =' bzw. 'ALow:' am Anfang einer Deklaration (davor
// 'const' oder ';') auf ALine: '' mit dem Namens-Token, sonst der Grund.
function FindDecl(AMap: TRdxCodeMap; ALine: Integer; const AName,
  ALow: string; out ADecl: TRdxToken): string;
var
  T, P, N : TRdxToken;
  Count   : Integer;
begin
  ADecl := Default(TRdxToken);
  Count := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.Low = ALow then
    begin
      P := Before(AMap, T);
      N := After(AMap, T);
      if ((N.Low = '=') or (N.Low = ':'))
         and ((P.Low = ';')
              or ((P.Low = 'const') and IsKeywordAfter(P, Before(AMap, P))))
      then
      begin
        Inc(Count);
        ADecl := T;
      end;
    end;
    T := After(AMap, T);
  end;
  if Count = 0 then
    Result := MsgMovedSuffix(_(R_LCN_MOVED, [AName]))
  else if Count > 1 then
    Result := _(R_LCN_MANY, [AName])
  else
    Result := '';
end;

// Rueckwaerts ab ADecl das erste Abschnittswort (SECTION_WORDS) als
// Schluesselwort; '' am Dateianfang.
function SectionOf(AMap: TRdxCodeMap; const ADecl: TRdxToken): string;
var
  P, PP : TRdxToken;
begin
  Result := '';
  P := Before(AMap, ADecl);
  while P.Low <> '' do
  begin
    PP := Before(AMap, P);
    if InList(P.Low, SECTION_WORDS) and IsKeywordAfter(P, PP) then
      Exit(P.Low);
    P := PP;
  end;
end;

// Die innerste Routine, in deren Deklarationsteil (hinter dem Kopf, vor
// dem Rumpf) ADecl steht. Ein Kopf mit unsicheren Grenzen beendet die
// Suche (er koennte der gesuchte sein). '' oder der Grund.
function DeclaringRoutine(AMap: TRdxCodeMap; const ADecl: TRdxToken;
  const AName: string; out ARoutine: TRdxRoutine): string;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  T := ADecl;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, S) do
  begin
    if S.Stop then
      Break;
    if S.Reason <> '' then
      Exit(_(R_LCN_BOUNDS, [AName]));
    if (S.Routine.Body.Low <> '')
       and TokBefore(S.Routine.HeaderEnd, ADecl)
       and TokBefore(ADecl, S.Routine.Body) then
    begin
      ARoutine := S.Routine;
      Exit('');
    end;
  end;
  Result := _(R_LCN_NO_ROUTINE, [AName]);
end;

// Das ';', das die Deklaration ab ADecl beendet (Klammertiefe 0, vor dem
// Rumpf von ARoutine); Low = '' ohne.
function DeclEnd(AMap: TRdxCodeMap; const ADecl: TRdxToken;
  const ARoutine: TRdxRoutine): TRdxToken;
var
  Depth : Integer;
begin
  Depth := 0;
  Result := After(AMap, ADecl);
  while (Result.Low <> '') and TokBefore(Result, ARoutine.Body) do
  begin
    Inc(Depth, ParenDelta(Result));
    if (Result.Low = ';') and (Depth = 0) then
      Exit;
    Result := After(AMap, Result);
  end;
  Result := Default(TRdxToken);
end;

// Ein 'with' als Schluesselwort in der Routine?
function RoutineHasWith(AMap: TRdxCodeMap; const R: TRdxRoutine): Boolean;
var
  P, X : TRdxToken;
begin
  Result := False;
  P := Before(AMap, R.Head);
  X := R.Head;
  while (X.Low <> '') and not TokBefore(R.Last, X) do
  begin
    if (X.Low = 'with') and IsKeywordAfter(X, P) then
      Exit(True);
    P := X;
    X := After(AMap, X);
  end;
end;

// Nennt eine Direktive in den Zeilen AFrom..ATo ALow als Wort?
function DirectiveNames(AMap: TRdxCodeMap; AFrom, ATo: Integer;
  const ALow: string): Boolean;
var
  Li, c : Integer;
  L     : string;
begin
  Result := False;
  for Li := AFrom to ATo do
  begin
    L := AMap.Raw(Li);
    if Pos('$', L) = 0 then Continue;
    for c := 1 to Length(L) do
      if OpensDirective(AMap, Li, c)
         and HasIdentWord(LowerCase(DirectiveArgs(AMap, Li, c)), ALow) then
        Exit(True);
  end;
end;

// Steht im Code der Datei ein Token ALow?
function CodeNames(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
      Exit(True);
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Steht ein Name (P und PP davor, N dahinter) im Deklarationsteil an einer
// Stelle, an der ein Name deklariert wird - oder vorsichtig an einer, die
// so aussieht?
// ':' dahinter (Parameter, Variable, Feld, Feldname einer Record-
// Konstante), ein Routinenwort oder ein Abschnittswort davor, ';' '(' ','
// davor mit ',' ')' ';' '=' dahinter (Namensliste, Aufzaehlung, Konstante
// 'A = 1; Name = 2').
function IsDeclSlot(const P, PP, N: TRdxToken): Boolean;
begin
  Result := (N.Low = ':')
    or InList(P.Low, ROUTINE_WORDS)
    or (InList(P.Low, DECL_WORDS) and IsKeywordAfter(P, PP))
    or (InList(P.Low, DECL_PREV) and InList(N.Low, DECL_NEXT));
end;

// Im Rumpf: steht hinter P der Name einer Inline-Deklaration ('var Name',
// 'const Name', 'for var Name', 'var A, Name: T')?
function IsInlineDecl(AMap: TRdxCodeMap; const P: TRdxToken): Boolean;
var
  Q, W : TRdxToken;
begin
  Q := P;
  while Q.Low = ',' do
  begin
    W := Before(AMap, Q);
    if not W.IsWord then
      Exit(False);
    Q := Before(AMap, W);
  end;
  Result := InList(Q.Low, INLINE_WORDS) and IsKeywordAfter(Q, Before(AMap, Q));
end;

// Im Rumpf: steht T im Kopf oder Deklarationsteil einer anonymen Methode
// (zwischen 'procedure'/'function' und ihrem 'begin')? Rueckwaerts bis
// AStart: das erste 'begin' bzw. Routinenwort entscheidet.
function InAnonymousHead(AMap: TRdxCodeMap;
  const T, AStart: TRdxToken): Boolean;
var
  P, PP : TRdxToken;
begin
  Result := False;
  P := Before(AMap, T);
  while (P.Low <> '') and TokBefore(AStart, P) do
  begin
    PP := Before(AMap, P);
    if IsKeywordAfter(P, PP) then
    begin
      if P.Low = 'begin' then
        Exit;
      if InList(P.Low, ROUTINE_WORDS) then
        Exit(True);
    end;
    P := PP;
  end;
end;

type
  // Die Rumpfe lokaler Routinen hinter der Deklaration: dort gelten die
  // Regeln des Rumpfs, nicht die des Deklarationsteils.
  TRdxBodies = record
    Starts : TArray<TRdxToken>;   // begin bzw. asm
    Ends   : TArray<TRdxToken>;   // das end des Rumpfs
  end;

// Die lokalen Routinen zwischen ADecl und dem Rumpf von ARoutine: ihre
// Rumpfe in ABodies (die Rumpfe darin verschachtelter Routinen nicht -
// deren ganzer Text gilt vorsichtig als Deklarationsteil). '' oder der
// Grund (unsichere Grenzen).
function LocalBodies(AMap: TRdxCodeMap; const ADecl: TRdxToken;
  const ARoutine: TRdxRoutine; const AName: string;
  out ABodies: TRdxBodies): string;
var
  T : TRdxToken;
  N : TRdxRoutine;
begin
  Result := '';
  ABodies := Default(TRdxBodies);
  T := After(AMap, ADecl);
  while (T.Low <> '') and TokBefore(T, ARoutine.Body) do
  begin
    if IsRoutineHead(AMap, T) then
    begin
      if TRdxBlocks.ReadRoutine(AMap, T, N) <> '' then
        Exit(_(R_LCN_BOUNDS, [AName]));
      if N.Body.Low <> '' then
      begin
        AddToken(ABodies.Starts, N.Body);
        AddToken(ABodies.Ends, N.EndTok);
      end;
      T := After(AMap, N.Last);
      Continue;
    end;
    T := After(AMap, T);
  end;
end;

// Steht T im Rumpf von ARoutine oder einer lokalen Routine aus ABodies?
// AStart: der Anfang dieses Rumpfs.
function BodyAround(const T: TRdxToken; const ARoutine: TRdxRoutine;
  const ABodies: TRdxBodies; out AStart: TRdxToken): Boolean;
var
  i : Integer;
begin
  Result := True;
  AStart := ARoutine.Body;
  if not TokBefore(T, ARoutine.Body) then Exit;
  for i := 0 to High(ABodies.Starts) do
    if TokBefore(ABodies.Starts[i], T) and TokBefore(T, ABodies.Ends[i]) then
    begin
      AStart := ABodies.Starts[i];
      Exit;
    end;
  Result := False;
end;

// Der Grund, den Verweis T hinter der Deklaration nicht umzubenennen; ''
// wenn er umbenannt werden kann. ASkip: ein Member ('X.Name') - weder
// umbenennen noch sperren.
function UseReason(AMap: TRdxCodeMap; const T: TRdxToken;
  const ARoutine: TRdxRoutine; const ABodies: TRdxBodies;
  const AName: string; out ASkip: Boolean): string;
var
  P, PP, N, Start : TRdxToken;
  Slot            : Boolean;
begin
  Result := '';
  P := Before(AMap, T);
  PP := Before(AMap, P);
  N := After(AMap, T);
  ASkip := P.Low = '.';
  if ASkip then Exit;
  if BodyAround(T, ARoutine, ABodies, Start) then
    Slot := IsInlineDecl(AMap, P)
      or (InAnonymousHead(AMap, T, Start) and IsDeclSlot(P, PP, N))
  else
    Slot := IsDeclSlot(P, PP, N);
  if Slot or ((P.Low = '@') and (PP.Low = '@')) then
    Result := _(R_LCN_SHADOW, [T.Line, AName])
  else if N.Low = ':=' then
    Result := _(R_LCN_NAMED_ARG, [AName, T.Line]);
end;

// Alle Verweise auf ALow in ARoutine als Ersetzungen; '' oder der Grund.
function CollectEdits(AMap: TRdxCodeMap; const ADecl: TRdxToken;
  const ARoutine: TRdxRoutine; const ABodies: TRdxBodies;
  const AName, ALow, ANewName: string; var AEdits: TArray<TRdxEdit>): string;
var
  T    : TRdxToken;
  E    : TRdxEdit;
  Skip : Boolean;
begin
  Result := '';
  T := ARoutine.Head;
  while (T.Low <> '') and not TokBefore(ARoutine.Last, T) do
  begin
    if T.Low = ALow then
    begin
      Skip := False;
      if TokBefore(T, ADecl) then
        Result := _(R_LCN_BEFORE, [AName, T.Line])
      else if TokBefore(ADecl, T) then
        Result := UseReason(AMap, T, ARoutine, ABodies, AName, Skip);
      if Result <> '' then
        Exit;
      if not Skip then
      begin
        E := Default(TRdxEdit);
        E.Span := TRefactorSpan.Make(SPAN_119, T.Line, T.Col, T.Line,
          T.EndCol);
        E.Expected := TokText(AMap, T);
        E.NewText := ANewName;
        AddEdit(AEdits, E);
      end;
    end;
    T := After(AMap, T);
  end;
end;

// Name aus der Meldung, Form, neuer Name: '' oder der Grund.
function NameReason(const AName: string): string;
begin
  Result := '';
  if not IsAsciiName(AName) then
    Result := _(R_LCN_NON_ASCII, [AName])
  else if IsUpperSnake(AName) then
    Result := MsgStaleSuffix(_(R_LCN_STALE, [AName]));
end;

// Deklaration, Abschnitt, Routine (auch die der Meldung), Ende der
// Deklaration ohne Kommentar: '' oder der Grund.
function PlaceReason(AMap: TRdxCodeMap; ALine: Integer;
  const AName, ARoutineName: string; out ADecl: TRdxToken;
  out ARoutine: TRdxRoutine): string;
var
  Semi : TRdxToken;
begin
  ARoutine := Default(TRdxRoutine);
  Result := FindDecl(AMap, ALine, AName, LowerCase(AName), ADecl);
  if Result <> '' then Exit;
  if SectionOf(AMap, ADecl) <> 'const' then
    Exit(_(R_LCN_NOT_CONST, [AName]));
  Result := DeclaringRoutine(AMap, ADecl, AName, ARoutine);
  if Result <> '' then Exit;
  if not SameText(ARoutine.Name, ARoutineName) then
    Exit(MsgMovedSuffix(_(R_LCN_OTHER_ROUTINE,
      [ARoutine.Name, ARoutineName])));
  Semi := DeclEnd(AMap, ADecl, ARoutine);
  if Semi.Low = '' then
    Exit(_(R_LCN_NO_END, [AName]));
  if CommentInRange(AMap, TRefactorSpan.Make(SPAN_119, ADecl.Line,
       ADecl.Col, Semi.Line, Semi.EndCol)) then
    Result := _(R_LCN_COMMENT, [AName]);
end;

// Die Fragen an Routine und Datei: with, Include, Direktiven, neuer Name.
// '' oder der Grund.
function ScopeReason(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AName, ANewName: string): string;
var
  IncLine : Integer;
  NewLow  : string;
begin
  Result := '';
  NewLow := LowerCase(ANewName);
  IncLine := IncludeInLines(AMap, ARoutine.Head.Line, ARoutine.Last.Line);
  if RoutineHasWith(AMap, ARoutine) then
    Result := _(R_LCN_WITH, [AName])
  else if IncLine > 0 then
    Result := _(R_LCN_INCLUDE, [IncLine, AName])
  else if DirectiveNames(AMap, ARoutine.Head.Line, ARoutine.Last.Line,
          LowerCase(AName)) then
    Result := _(R_LCN_DIRECTIVE, [AName])
  else if SameText(AName, ANewName) then
    Exit
  else if CodeNames(AMap, NewLow) then
    Result := _(R_LCN_TAKEN, [ANewName])
  else if DirectiveNames(AMap, 1, AMap.LineCount, NewLow) then
    Result := _(R_LCN_DIRECTIVE, [ANewName]);
end;

class function TRdxLocalConstantNameFix.RenameConstant(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string;
  out APlan: TRdxLocalConstantNamePlan; out AReason: string): Boolean;
var
  RoutineName : string;
  Decl        : TRdxToken;
  Routine     : TRdxRoutine;
  Bodies      : TRdxBodies;
begin
  Result := False;
  Decl := Default(TRdxToken);
  Routine := Default(TRdxRoutine);
  Bodies := Default(TRdxBodies);
  APlan := Default(TRdxLocalConstantNamePlan);
  APlan.OldName := ConstNameOf(AMessage, RoutineName);
  if APlan.OldName = '' then
  begin
    AReason := _(R_LCN_FORM);
    Exit;
  end;
  AReason := NameReason(APlan.OldName);
  if AReason <> '' then Exit;
  APlan.Name := UpperSnakeOf(APlan.OldName);
  AReason := PlaceReason(AMap, ALine, APlan.OldName, RoutineName, Decl,
    Routine);
  if AReason = '' then
    AReason := ScopeReason(AMap, Routine, APlan.OldName, APlan.Name);
  if AReason = '' then
    AReason := LocalBodies(AMap, Decl, Routine, APlan.OldName, Bodies);
  if AReason = '' then
    AReason := CollectEdits(AMap, Decl, Routine, Bodies, APlan.OldName,
      LowerCase(APlan.OldName), APlan.Name, APlan.Edits);
  if AReason <> '' then
  begin
    APlan.Edits := nil;
    Exit;
  end;
  Result := True;
end;

end.
