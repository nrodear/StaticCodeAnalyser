unit uRdxThreadResumeFix;

// reDelphix - Editorhilfe SCA113 ThreadResumeDeprecated, OHNE ToolsAPI und
// ohne Parser (Konzept_Editorhilfen_Regelliste_2026-10-11, Zeile SCA113:
// "bedingt"):
//   'X.Resume;' -> 'X.Start;' - NUR mit Beweis, dass X in derselben Routine
//   unmittelbar davor angehalten erzeugt wurde ('X := TFoo.Create(True);').
//
// WARUM NUR MIT BEWEIS (Recherche-Tabellen, SCA113): TThread.Start ist NICHT
// Resume. Start wirft EThread, wenn der Thread nicht angehalten erzeugt
// wurde oder schon laeuft (InternalStart, RTL 37.0); Resume nach Suspend
// setzt fort, Start nach Suspend wirft. Fuer einen mit Create(True)
// erzeugten, noch nie gestarteten Thread tun beide dasselbe - dann ist der
// Tausch bedeutungsgleich (Changes: False). FPC kennt Start ab 2.6 und ruft
// darin Resume.
//
// WAS DER DETEKTOR MELDET (uConcurrencyExt, PruefeResumeAufrufe): jedes
// '<ident>.Resume' im gestrippten Text, das kein Kopf, kein Lesen und kein
// Vergleich ist und dessen Empfaenger nicht in der Datei als Nicht-Thread
// aufgeloest wird; Zeile = Zeile des Empfaengers (das Regex greift nur das
// LETZTE Glied einer Kette). Meldung '<ident>.Resume is deprecated since
// Delphi 2010 - prefer <ident>.Start or ...' - ohne Spalte.
//
// DER BEWEIS (am Text, auf der Code-Sicht; sonst keine Hilfe):
//   * auf der Zeile genau ein '<X>.Resume' mit dem Namen der Meldung, X ein
//     blosser Bezeichner (kein 'A.X', kein '@X'), als eigene Anweisung;
//   * es steht im Rumpf einer Routine (Routinengrenzen uRdxBlocks); die
//     LETZTE Zuweisung an X davor in diesem Rumpf ist 'X := T.Create(True);'
//     bzw. 'var X[: T] := T.Create(True);' - als Anweisung einer
//     Anweisungsliste (davor ';', begin oder try), und der Weg von dort zum
//     Resume verlaesst diesen Block nicht (end-Bilanz nie unter 0);
//   * dazwischen keine Schleife, kein goto, kein with, keine anonyme
//     Methode, keine Direktive, und X kommt dort nur als 'X.Feld := ..' vor
//     (nicht Suspended): jeder andere Gebrauch koennte den Thread starten;
//   * im Rumpf kein zweites 'X.Resume'/'X.Start', in der Datei kein
//     'X.Suspend';
//   * T ist ein Thread-Typ (Name endet auf 'Thread' oder die Vorfahrenkette
//     in der Datei erreicht einen); hat T in der Datei einen eigenen
//     Konstruktor Create, reicht er seinen ersten Parameter an 'inherited
//     Create(..)' weiter (oder ruft 'inherited;');
//   * kein Compiler ohne Start: keine Spur eines Compilers vor Delphi 2010
//     bzw. FPC 2.6 in den Direktiven der Datei (uRdxCompilerTraces,
//     FLOOR_THREAD_START), und das Resume steht in keinem offenen
//     {$IF}/{$IFDEF}-Block (die Altzweige '{$IF CompilerVersion ..} Start
//     {$ELSE} Resume').
// Ersetzt wird nur das Wort Resume, Schreibweise wie im Text ('RESUME' ->
// 'START').
//
// GRENZE: ein Thread-Typ aus einer ANDEREN Unit mit eigenem Konstruktor
// Create(B: Boolean), in dem B etwas anderes bedeutet als CreateSuspended,
// ist am Text nicht zu sehen - im Korpus nicht belegt.
//
// Die Unit bindet nur Textlogik (FPC-Pruefstand); den Adapter der Tabelle
// (PlanThreadResume ueber MapFix) bekommt uRdxFixTable bei der Integration.

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_TR_NO_NAME     = 'the message names no receiver of Resume';
  R_TR_MOVED       = 'no call "%s.Resume" on the reported line';
  R_TR_MANY        = 'line %d carries %d calls "%s.Resume" - ambiguous';
  R_TR_QUALIFIED   = '%s.Resume is reached through a qualifier - the help '
    + 'proves only a plain variable';
  R_TR_NOT_STMT    = '%s.Resume is not a statement of its own';
  R_TR_LOOP        = '%s.Resume is the body of a loop or with statement ("%s" '
    + 'before it)';
  R_TR_NO_ROUTINE  = '%s.Resume does not stand in the body of a routine';
  R_TR_NO_CREATE   = 'no "%s := T.Create(True)" before Resume in this routine '
    + '- that the thread was created suspended is not provable';
  R_TR_LAST_ASSIGN = 'the last assignment to %s before Resume (line %d) is not '
    + '"T.Create(True);"';
  R_TR_BRANCH      = '"%s := T.Create(True)" stands in a branch or block that '
    + 'Resume does not share - not provable that it ran';
  R_TR_USED        = '%s is used in line %d between Create(True) and Resume - '
    + 'the thread could already run there';
  R_TR_FLOW        = '"%s" between Create(True) and Resume - Resume could run '
    + 'more than once or for another thread';
  R_TR_TWICE       = '%s is resumed or started more than once in this routine';
  R_TR_SUSPEND     = 'the file calls %s.Suspend - Start after Suspend raises '
    + 'EThread';
  R_TR_NOT_THREAD  = '%s is not provably a TThread descendant in this file';
  R_TR_OWN_CTOR    = 'own constructor %s.Create - not provable that True still '
    + 'means CreateSuspended';
  R_TR_DIRECTIVE   = 'compiler directive between Create(True) and Resume';
  R_TR_CONDITIONAL = 'Resume stands in a conditional compilation block - an '
    + 'older compiler may need it';
  R_TR_OLD_COMPILER = 'the file supports compilers without TThread.Start (%s, '
    + 'line %d) - Start exists from Delphi 2010 and FPC 2.6';

type
  // Der Planer von SCA113 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxThreadResumeFix = class
  public
    // Der Empfaenger aus der Meldung ('Worker.Resume is deprecated ...' ->
    // 'Worker'); '' ohne diese Form. Fuer den Menuetext (Name) und den
    // Planer.
    class function ReceiverOf(const AMessage: string): string; static;

    // ALine ist die Zeile des Empfaengers (die Meldung traegt keine
    // Spalte). Liefert die eine Ersetzung 'Resume' -> 'Start' oder den
    // Grund (Beweis im Kopf).
    class function ResumeToStart(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,         // TRefactorSpan.Make
  uRdxBlocks,            // TRdxBlocks (Routinengrenzen, Klassenkoepfe)
  uRdxCompilerTraces,    // OldCompilerTrace, TRdxCompilerFloor
  uRdxText;              // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_113    = 'sca113';
  KEY_RESUME  = '.Resume is deprecated';
  KW_RESUME   = 'resume';
  KW_START    = 'start';
  KW_CREATE   = 'create';
  NEW_WORD    = 'Start';
  // Thread-Typ: so endet sein Name, so oft folgt die Planung der
  // Vorfahrenkette in der Datei.
  THREAD_SUFFIX = 'thread';
  MAX_HERITAGE  = 4;
  // So viele Token liest die Planung hinter 'var X:' bis zum ':='.
  MAX_TYPE_TOKENS = 12;
  // Vor dem Empfaenger: eine Anweisung beginnt ...
  STMT_PREV: array[0..7] of string = (';', 'begin', 'then', 'else', 'try',
    'finally', 'except', ':');
  // ... hinter Resume endet sie.
  STMT_NEXT: array[0..2] of string = (';', 'end', 'else');
  // Vor 'X := T.Create(True)': die Anweisung steht in einer
  // Anweisungsliste, nicht als Zweig. Bewusst enger als
  // uRdxCodeMap.LIST_PREV (ohne finally/except/repeat/initialization/
  // finalization) - bis zur Hygiene-Welle H1 hiess die Liste LIST_PREV und
  // verdeckte den zentralen Namen.
  STMT_LIST_PREV: array[0..2] of string = (';', 'begin', 'try');
  // Davor steht X nicht als blosser Bezeichner: uRdxCodeMap.IDENT_PREFIXES
  // (bis zur Hygiene-Welle H1 hier als QUALIFIERS mengengleich kopiert).
  // Zwischen Create(True) und Resume - Schleifen, Spruenge, with und
  // anonyme Methoden ('procedure'/'function' als Wert; ein asm-Block zaehlt
  // als Oeffner der end-Bilanz).
  FLOW_WORDS: array[0..7] of string = ('for', 'while', 'repeat', 'until',
    'goto', 'with', 'procedure', 'function');
  // Vor Resume: eine Schleife bzw. ein with-Rumpf.
  LOOP_PREV: array[0..1] of string = ('do', 'repeat');
  // Die Suche nach der Routine um das Resume endet an
  // uRdxCodeMap.UNIT_BOUNDS (bis zur Hygiene-Welle H1 hier kopiert).
  // Parameter-Vorsaetze im Konstruktorkopf.
  PARAM_MODIFIERS: array[0..3] of string = ('const', 'var', 'out', 'constref');
  // TThread.Start: ab Delphi 2010 (VER210, CompilerVersion 21, COMPILER14,
  // DELPHI14 der JEDI-Zaehlung, RTL210) und FPC 2.6. Wer nach Version n
  // fragt, baut auch mit der davor (uRdxCompilerTraces, Kopf) - darum zaehlt
  // FPC_FULLVERSION 20600 selbst mit (FpcFull zaehlt UNTER dem Wert). Die
  // XE-Namen fragen nach juengeren Compilern (XeNames aus);
  // CONDITIONALEXPRESSIONS (Delphi 6) haengt am selben Schalter und faellt
  // damit heraus - offen in der Integrationsnotiz.
  FLOOR_THREAD_START: TRdxCompilerFloor = (Ver: 210; Version: 21;
    Compiler: 14; DelphiNumber: 14; DelphiYear: 2010; Rtl: 210;
    FpcFull: 20601; XeNames: False; ProjectVersion: 120);

type
  // Was der Beweis ueber die Erzeugung findet.
  TRdxCreateSite = record
    Target  : TRdxToken;   // X in 'X := T.Create(True)'
    TypeTok : TRdxToken;   // T (letztes Glied vor .Create)
    Semi    : TRdxToken;   // das ';' hinter der Erzeugung
  end;

// AWord in der Schreibweise von AModel: ganz gross, ganz klein oder gross am
// Anfang.
function CaseLike(const AModel, AWord: string): string;
begin
  if (AModel = UpperCase(AModel)) and (Length(AModel) > 1) then
    Result := UpperCase(AWord)
  else if AModel = LowerCase(AModel) then
    Result := LowerCase(AWord)
  else
    Result := AWord;
end;

// Steht T als blosser Bezeichner AName (klein) - nicht hinter '.', '@', '&'?
function IsPlainName(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowName: string): Boolean;
begin
  Result := SameIdent(T.Low, ALowName)
    and not InList(Before(AMap, T).Low, IDENT_PREFIXES);
end;

// Die Tiefe der bedingten Uebersetzung vor (ALine, ACol): {$IF}, {$IFDEF},
// {$IFNDEF}, {$IFOPT} oeffnen, {$ENDIF}/{$IFEND} schliessen. Privat - eine
// Kopie steht in uRdxInsecureRandomFix (Kandidat fuer uRdxCodeMap).
function ConditionalDepthAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Integer;
var
  Li, Co, Last : Integer;
  Arg          : Boolean;
  W            : string;
begin
  Result := 0;
  for Li := 1 to ALine do
  begin
    Last := Length(AMap.Raw(Li));
    if Li = ALine then
      Last := ACol - 1;
    for Co := 1 to Last do
      if OpensDirective(AMap, Li, Co) then
      begin
        W := DirectiveWord(AMap, Li, Co, Arg);
        if InList(W, COND_OPENERS) then
          Inc(Result)
        else if InList(W, COND_CLOSERS) and (Result > 0) then
          Dec(Result);
      end;
  end;
end;

// Der Rumpf der innersten Routine um AAt (wie uRdxTryFixes.RoutineAround):
// unsichere Koepfe uebergangen, ein Abschnittswort der Unit beendet die
// Suche.
function RoutineAround(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): Boolean;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, UNIT_BOUNDS, S) and not S.Stop do
    if (S.Reason = '') and (S.Routine.Body.Low <> '')
       and TokBefore(S.Routine.Body, AAt)
       and TokBefore(AAt, S.Routine.EndTok) then
    begin
      ARoutine := S.Routine;
      Exit(True);
    end;
  Result := False;
end;

// Der eine Aufruf '<AName>.Resume' auf ALine als eigene Anweisung: ARecv der
// Empfaenger, ARes das Wort Resume. '' oder der Grund.
function FindCall(AMap: TRdxCodeMap; ALine: Integer; const AName: string;
  out ARecv, ARes: TRdxToken): string;
var
  T, Dot, Res, Prev : TRdxToken;
  n                 : Integer;
  NameLow           : string;
begin
  ARecv := Default(TRdxToken);
  ARes := Default(TRdxToken);
  NameLow := LowerCase(AName);
  n := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if SameIdent(T.Low, NameLow) then
    begin
      Dot := After(AMap, T);
      Res := After(AMap, Dot);
      if (Dot.Low = '.') and (Res.Low = KW_RESUME) then
      begin
        Inc(n);
        ARecv := T;
        ARes := Res;
      end;
    end;
    T := After(AMap, T);
  end;
  if n = 0 then
    Exit(MsgMovedSuffix(_(R_TR_MOVED, [AName])));
  if n > 1 then
    Exit(_(R_TR_MANY, [ALine, n, AName]));
  Prev := Before(AMap, ARecv);
  if InList(Prev.Low, IDENT_PREFIXES) then
    Exit(_(R_TR_QUALIFIED, [AName]));
  if InList(Prev.Low, LOOP_PREV) then
    Exit(_(R_TR_LOOP, [AName, Prev.Low]));
  if not InList(Prev.Low, STMT_PREV)
     or not InList(After(AMap, ARes).Low, STMT_NEXT) then
    Exit(_(R_TR_NOT_STMT, [AName]));
  Result := '';
end;

// Ist T das Ziel einer Zuweisung ('T :=' bzw. 'var T[: Typ] :=')? AAssign
// ist dann das ':='.
function AssignAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out AAssign: TRdxToken): Boolean;
var
  N : TRdxToken;
  k : Integer;
begin
  AAssign := After(AMap, T);
  if AAssign.Low = ':=' then
    Exit(True);
  Result := False;
  if (AAssign.Low <> ':') or (Before(AMap, T).Low <> 'var') then Exit;
  N := After(AMap, AAssign);
  for k := 1 to MAX_TYPE_TOKENS do
  begin
    if N.Low = ':=' then
    begin
      AAssign := N;
      Exit(True);
    end;
    if (N.Low = '') or (N.Low = ';') then Exit;
    N := After(AMap, N);
  end;
end;

// Hinter AAssign genau 'T.Create(True);' (T auch qualifiziert: 'Unit.T')?
// ASite traegt T und das ';'.
function ReadCreate(AMap: TRdxCodeMap; const AAssign: TRdxToken;
  var ASite: TRdxCreateSite): Boolean;
var
  P, N, W, Open, Lit, Close : TRdxToken;
begin
  Result := False;
  P := After(AMap, AAssign);
  if not P.IsWord or (P.Low = KW_CREATE) then Exit;
  ASite.TypeTok := P;
  W := Default(TRdxToken);
  N := After(AMap, P);
  while N.Low = '.' do
  begin
    W := After(AMap, N);
    if not W.IsWord then Exit;
    if W.Low = KW_CREATE then Break;
    ASite.TypeTok := W;
    N := After(AMap, W);
  end;
  if (N.Low <> '.') or (W.Low <> KW_CREATE) then Exit;
  Open := After(AMap, W);
  Lit := After(AMap, Open);
  Close := After(AMap, Lit);
  ASite.Semi := After(AMap, Close);
  Result := (Open.Low = '(') and (Lit.Low = 'true') and (Close.Low = ')')
    and (ASite.Semi.Low = ';');
end;

// Die letzte Zuweisung an AName im Rumpf von ARoutine vor ARecv muss die
// Erzeugung 'AName := T.Create(True);' als Anweisung einer
// Anweisungsliste sein; ein with davor sperrt (AName koennte ein Feld sein).
// '' und ASite oder der Grund.
function CreateReason(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const ARecv: TRdxToken; const AName: string;
  out ASite: TRdxCreateSite): string;
var
  T, Asg, LastAsg, Start : TRdxToken;
  NameLow                : string;
begin
  ASite := Default(TRdxCreateSite);
  NameLow := LowerCase(AName);
  LastAsg := Default(TRdxToken);
  T := After(AMap, ARoutine.Body);
  while (T.Low <> '') and TokBefore(T, ARecv) do
  begin
    if (T.Low = 'with') and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(_(R_TR_FLOW, [T.Low]));
    if IsPlainName(AMap, T, NameLow) and AssignAt(AMap, T, Asg) then
    begin
      ASite.Target := T;
      LastAsg := Asg;
    end;
    T := After(AMap, T);
  end;
  if LastAsg.Low = '' then
    Exit(_(R_TR_NO_CREATE, [AName]));
  if not ReadCreate(AMap, LastAsg, ASite) then
    Exit(_(R_TR_LAST_ASSIGN, [AName, ASite.Target.Line]));
  Start := ASite.Target;
  if Before(AMap, Start).Low = 'var' then
    Start := Before(AMap, Start);
  if not InList(Before(AMap, Start).Low, STMT_LIST_PREV) then
    Exit(_(R_TR_BRANCH, [AName]));
  Result := '';
end;

// Von der Erzeugung bis zum Resume: Block nicht verlassen, keine Schleife
// usw., X nur als 'X.Feld := ..' (nicht Suspended), keine Direktive. '' oder
// der Grund.
function BetweenReason(AMap: TRdxCodeMap; const ASite: TRdxCreateSite;
  const ARecv: TRdxToken; const AName: string): string;
var
  T, P, M : TRdxToken;
  Depth   : Integer;
  NameLow : string;
begin
  NameLow := LowerCase(AName);
  Depth := 0;
  P := ASite.Semi;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, ARecv) do
  begin
    if IsKeywordAfter(T, P) then
    begin
      if IsEndOpener(T.Low) then
        Inc(Depth)
      else if T.Low = 'end' then
      begin
        Dec(Depth);
        if Depth < 0 then
          Exit(_(R_TR_BRANCH, [AName]));
      end
      else if InList(T.Low, FLOW_WORDS) then
        Exit(_(R_TR_FLOW, [T.Low]));
    end;
    if IsPlainName(AMap, T, NameLow) then
    begin
      // Erlaubt ist nur 'X.Feld := ..' (FreeOnTerminate, Priority,
      // OnTerminate ...) - nicht Suspended, das den Thread startet.
      M := After(AMap, After(AMap, T));
      if (After(AMap, T).Low <> '.') or not M.IsWord or (M.Low = 'suspended')
         or (After(AMap, M).Low <> ':=') then
        Exit(_(R_TR_USED, [AName, T.Line]));
    end;
    P := T;
    T := After(AMap, T);
  end;
  if DirectiveBetween(AMap, ASite.Semi, ARecv.Line, ARecv.Col) then
    Exit(_(R_TR_DIRECTIVE));
  Result := '';
end;

// Wie oft steht 'AName.Resume' bzw. 'AName.Start' im Rumpf von ARoutine?
// Mehr als einmal: der Grund, sonst ''.
function TwiceReason(AMap: TRdxCodeMap; const ARoutine: TRdxRoutine;
  const AName: string): string;
var
  T, M    : TRdxToken;
  n       : Integer;
  NameLow : string;
begin
  NameLow := LowerCase(AName);
  n := 0;
  T := After(AMap, ARoutine.Body);
  while (T.Low <> '') and TokBefore(T, ARoutine.EndTok) do
  begin
    if IsPlainName(AMap, T, NameLow) and (After(AMap, T).Low = '.') then
    begin
      M := After(AMap, After(AMap, T));
      if (M.Low = KW_RESUME) or (M.Low = KW_START) then
        Inc(n);
    end;
    T := After(AMap, T);
  end;
  Result := '';
  if n > 1 then
    Result := _(R_TR_TWICE, [AName]);
end;

// Ruft die Datei irgendwo 'AName.Suspend'? Dann der Grund, sonst ''.
function SuspendReason(AMap: TRdxCodeMap; const AName: string): string;
var
  T, Dot, X : TRdxToken;
begin
  Result := '';
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'suspend');
  while T.Low <> '' do
  begin
    if T.Low = 'suspend' then
    begin
      Dot := Before(AMap, T);
      X := Before(AMap, Dot);
      if (Dot.Low = '.') and SameIdent(X.Low, LowerCase(AName)) then
        Exit(_(R_TR_SUSPEND, [AName]));
    end;
    T := NextTokenOnLineWith(AMap, T, 'suspend');
  end;
end;

// Endet S (klein oder gross) auf 'thread'?
function EndsWithThread(const S: string): Boolean;
begin
  Result := (Length(S) >= Length(THREAD_SUFFIX))
    and (LowerCase(Copy(S, Length(S) - Length(THREAD_SUFFIX) + 1,
      Length(THREAD_SUFFIX))) = THREAD_SUFFIX);
end;

// Ist AType ein Thread-Typ - sein Name endet auf 'Thread', oder die
// Vorfahrenkette in der Datei erreicht einen solchen (je Glied genau ein
// Klassenkopf mit Rumpf)?
function IsThreadType(AMap: TRdxCodeMap; const AType: string): Boolean;
var
  Cur     : string;
  Steps   : Integer;
  Heads   : TArray<TRdxToken>;
  Parents : TArray<string>;
begin
  Cur := AType;
  for Steps := 0 to MAX_HERITAGE do
  begin
    if EndsWithThread(Cur) then
      Exit(True);
    Heads := TRdxBlocks.FindClassHeads(AMap, Cur);
    if Length(Heads) <> 1 then
      Exit(False);
    Parents := TRdxBlocks.HeritageOf(AMap, Heads[0]);
    if Length(Parents) = 0 then
      Exit(False);
    Cur := Parents[0];
  end;
  Result := False;
end;

// Der Kopf 'constructor AType.Create' an T (T ist das Wort Create)? AHead
// ist dann das Wort constructor.
function CtorHeadAt(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowType: string; out AHead: TRdxToken): Boolean;
var
  Dot, Ty : TRdxToken;
begin
  Result := False;
  Dot := Before(AMap, T);
  Ty := Before(AMap, Dot);
  if (Dot.Low <> '.') or not SameIdent(Ty.Low, ALowType) then Exit;
  AHead := Before(AMap, Ty);
  // Verschachtelte Klasse: 'constructor TOuter.TWorker.Create'.
  while AHead.Low = '.' do
    AHead := Before(AMap, Before(AMap, AHead));
  Result := (AHead.Low = 'constructor')
    and IsKeywordAfter(AHead, Before(AMap, AHead));
end;

// Reicht der Konstruktor R seinen ersten Parameter an 'inherited
// Create(..)' weiter bzw. ruft er 'inherited;'?
function PassesFirstParam(AMap: TRdxCodeMap; const R: TRdxRoutine): Boolean;
var
  P, T, N, Arg : TRdxToken;
  Param        : string;
begin
  Result := False;
  P := After(AMap, R.NameTok);
  if P.Low <> '(' then Exit;
  P := After(AMap, P);
  if InList(P.Low, PARAM_MODIFIERS) then
    P := After(AMap, P);
  if not P.IsWord then Exit;
  Param := P.Low;
  T := After(AMap, R.Body);
  while (T.Low <> '') and TokBefore(T, R.EndTok) do
  begin
    if T.Low = 'inherited' then
    begin
      N := After(AMap, T);
      if (N.Low = ';') or (N.Low = 'end') then
        Exit(True);
      Arg := After(AMap, After(AMap, N));
      if (N.Low = KW_CREATE) and (After(AMap, N).Low = '(')
         and SameIdent(Arg.Low, Param)
         and InList(After(AMap, Arg).Low, [')', ',']) then
        Exit(True);
    end;
    T := After(AMap, T);
  end;
end;

// Hat AType in der Datei einen eigenen Konstruktor Create? Dann muss es
// genau einer sein, der den ersten Parameter weiterreicht. '' oder der
// Grund.
function CtorReason(AMap: TRdxCodeMap; const AType: string): string;
var
  T, Head, Found : TRdxToken;
  n              : Integer;
  LowType        : string;
  R              : TRdxRoutine;
begin
  Result := '';
  LowType := LowerCase(AType);
  n := 0;
  Found := Default(TRdxToken);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_CREATE);
  while T.Low <> '' do
  begin
    if (T.Low = KW_CREATE) and CtorHeadAt(AMap, T, LowType, Head) then
    begin
      Inc(n);
      Found := Head;
    end;
    T := NextTokenOnLineWith(AMap, T, KW_CREATE);
  end;
  if n = 0 then Exit;
  if (n > 1) or (TRdxBlocks.ReadRoutine(AMap, Found, R) <> '')
     or (R.Body.Low = '') or not PassesFirstParam(AMap, R) then
    Result := _(R_TR_OWN_CTOR, [AType]);
end;

// Kennt jeder Compiler der Datei Start? Spur eines aelteren in den
// Direktiven bzw. Resume in einem offenen Bedingungsblock: der Grund.
function CompilerReason(AMap: TRdxCodeMap; const ARecv: TRdxToken): string;
var
  Trace     : string;
  TraceLine : Integer;
begin
  Result := '';
  Trace := OldCompilerTrace(AMap, FLOOR_THREAD_START, TraceLine);
  if Trace <> '' then
    Exit(_(R_TR_OLD_COMPILER, [Trace, TraceLine]));
  if ConditionalDepthAt(AMap, ARecv.Line, ARecv.Col) > 0 then
    Result := _(R_TR_CONDITIONAL);
end;

{ TRdxThreadResumeFix }

class function TRdxThreadResumeFix.ReceiverOf(const AMessage: string): string;
var
  P : Integer;
begin
  Result := '';
  P := Pos(KEY_RESUME, AMessage);
  if P <= 1 then Exit;
  Result := Trim(Copy(AMessage, 1, P - 1));
  // Nur ein Bezeichner (der Detektor greift '\w+').
  if (Result = '') or not IsIdentStart(Result[1]) then
    Result := '';
end;

class function TRdxThreadResumeFix.ResumeToStart(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Name      : string;
  Recv, Res : TRdxToken;
  R         : TRdxRoutine;
  Site      : TRdxCreateSite;
  Kw        : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Name := ReceiverOf(AMessage);
  if Name = '' then
  begin
    AReason := _(R_TR_NO_NAME);
    Exit;
  end;
  AReason := FindCall(AMap, ALine, Name, Recv, Res);
  if (AReason = '') and not RoutineAround(AMap, Recv, R) then
    AReason := _(R_TR_NO_ROUTINE, [Name]);
  // Vor dem Beweis am Rumpf: die Altzweige '{$IF CompilerVersion ..} Start
  // {$ELSE} Resume' nennt so der Grund, der sie erklaert.
  if AReason = '' then
    AReason := CompilerReason(AMap, Recv);
  if AReason = '' then
    AReason := CreateReason(AMap, R, Recv, Name, Site);
  if AReason = '' then
    AReason := BetweenReason(AMap, Site, Recv, Name);
  if AReason = '' then
    AReason := TwiceReason(AMap, R, Name);
  if AReason = '' then
    AReason := SuspendReason(AMap, Name);
  if (AReason = '') and not IsThreadType(AMap, TokText(AMap, Site.TypeTok)) then
    AReason := _(R_TR_NOT_THREAD, [TokText(AMap, Site.TypeTok)]);
  if AReason = '' then
    AReason := CtorReason(AMap, TokText(AMap, Site.TypeTok));
  if AReason <> '' then
    Exit;
  Kw := TokText(AMap, Res);
  AEdit.Span := TRefactorSpan.Make(SPAN_113, Res.Line, Res.Col, Res.Line,
    Res.EndCol);
  AEdit.Expected := Kw;
  AEdit.NewText := CaseLike(Kw, NEW_WORD);
  Result := True;
end;

end.
