unit uRdxUnusedParameterFix;

// reDelphix - Editorhilfe SCA054 UnusedParameter, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11, "bedingt"):
//   'procedure P(A: Integer; Mode: Integer);' -> '... _Mode: Integer);'
//   in der Implementierung UND in jeder Deklaration derselben Routine
//   (Klassenrumpf, interface-Teil, forward), dazu '<param name="Mode">' in
//   der '///'-Doku direkt darueber. Der Unterstrich dokumentiert die
//   Absicht; der Detektor uebergeht Namen mit '_'.
//
// BEDEUTUNGSGLEICH: der Name eines Parameters ist nicht Teil des Aufrufs -
// benannte Argumente gibt es in Delphi nicht (nur fuer OLE-Automation ueber
// Variant/dispinterface, nie fuer eine Routine dieser Datei). Overrides
// und Interface-Implementierungen duerfen andere Namen tragen als ihre
// Vorlage, und eine Formdatei bindet nur den Methodennamen. Delphi
// verlangt dagegen gleiche Namen in Deklaration und Implementierung
// (E2037) - darum beide.
//
// DER FUND: uUnusedParameter meldet auf der Zeile des Kopfworts der
// IMPLEMENTIERUNG (der Parser gibt jedem Parameter die Zeile von
// procedure/function/...), 'Unused parameter: X (never read in method
// body)'. Gemeldet werden nur Routinen mit Rumpf; Methoden mit
// override/virtual/abstract/dynamic, Ereignishandler (Sender), message-
// Handler, Klassen mit Interfaces, Routinen als Wert und Namen mit '_'
// uebergeht der Detektor.
//
// SPERREN (lieber keine Hilfe als eine falsche):
//   * Auf der Zeile beginnt nicht genau EINE Routine mit Rumpf, deren
//     Parameterliste den Namen traegt; ihre Grenzen sind nicht sicher
//     (TRdxBlocks.ReadRoutine); die Liste ist nicht lesbar ('&Name',
//     ungewohnte Form) oder traegt Kommentar, Direktive oder Attribut (auch
//     FPC '{%H-}').
//   * Der Name kommt im Bereich der Routine sonst als Code vor - Rumpf,
//     lokale Routinen, inaktive $IFDEF-Zweige (die Code-Sicht wertet keine
//     Direktiven aus), auch hinter '.' oder in 'with'. Kommentare und
//     Strings zaehlen nicht. asm in der Routine (Parameter ueber Register,
//     ohne Namen) und ein {$I} in ihr sperren ebenso.
//   * '_Name' kommt in der Datei schon als Code vor (doppelter Bezeichner
//     oder verdeckt danach ein Feld/eine Variable gleichen Namens).
//   * Deklaration und Implementierung nicht eindeutig zu paaren: overload
//     an einer Seite, Methode ohne Deklaration in einer Klasse dieser Datei
//     (Record-Methoden, Include), mehr als eine Deklaration oder
//     Implementierung, eine zweite freie Routine gleichen Namens (auch
//     lokal oder als $IFDEF-Zwilling), verschiedene Namenslisten; bei
//     freien Routinen jedes {$I} in der Datei (es kann die Deklaration
//     tragen - danach E2037).
//   * Ein Attribut an Routine, Deklaration oder Klasse: RTTI-gestuetzte
//     Frameworks (REST-Controller) binden Parameter auch per Namen.
//
// GRENZEN: FPC im Modus objfpc meldet einen Parameter, der wie ein Member
// der Klasse heisst, als doppelten Bezeichner - ein geerbtes Feld '_Mode'
// aus einer anderen Unit sieht die Hilfe nicht.
//
// GETEILTE BAUSTEINE: ReadSite (Implementierung auf der Zeile, ihre
// Parameterliste und alle Deklarationen) und TokenEdit nutzt auch
// uRdxConstStringParameterFix (SCA170). Kandidaten fuer uRdxBlocks, sobald
// eine dritte Hilfe sie braucht.
//
// OHNE ToolsAPI und ohne uEngineApi/uRdxFixRunner (Hausregel der Tabelle,
// uRdxFixTable): reine Textlogik, FPC-tauglich. Den Adapter fuer FIX_ROWS
// schreibt uRdxFixTable (Form TRdxPlannerOf<TRdxParamPlan>).

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap,       // TRdxCodeMap, TRdxToken
  uRdxBlocks;        // TRdxRoutine, TRdxClassHead

const
  // Gruende als englische msgids (die Tests pruefen sie mit _()). Die
  // ersten gelten auch fuer SCA170 - ReadSite setzt sie.
  R_UP_NO_HEAD = 'no routine with the parameter "%s" begins on the reported '
    + 'line';
  R_UP_MANY_HEADS = '%d routines with the parameter "%s" begin on the '
    + 'reported line';
  R_UP_BOUNDS = 'the bounds of the routine or its class are not safe to read';
  R_UP_LIST = 'the parameter list is not readable';
  R_UP_NOISE = 'comment, compiler directive or attribute in the parameter '
    + 'list';
  R_UP_ASM = 'asm in the routine - it can read parameters through registers '
    + 'without their names';
  R_UP_INCLUDE = '{$I} include in line %d - it can use or declare the routine';
  R_UP_NO_DECL = 'no declaration of %s in a class of this file (record '
    + 'method, include?)';
  R_UP_MANY_IMPLS = '%d implementations of %s - overload or $IFDEF twin?';
  R_UP_OVERLOAD = '%s is overloaded - declaration and implementation cannot '
    + 'be paired safely';
  R_UP_TWIN = 'a second routine %s in line %d - overload, $IFDEF twin or '
    + 'local routine';
  R_UP_DECL_FORM = 'the declaration of %s in line %d is not readable';
  R_UP_DECL_DIFFERS = 'the parameter lists of the declaration in line %d and '
    + 'of the implementation differ';
  // Nur SCA054.
  R_UP_NO_NAME = 'the message names no parameter';
  R_UP_UNDERSCORE = 'parameter "%s" already starts with "_"';
  R_UP_USED = 'parameter "%s" occurs in the routine in line %d';
  R_UP_TAKEN = '"%s" already occurs in line %d - the new name would clash '
    + 'with it or hide it';
  R_UP_ATTRIBUTE = 'attribute on the routine or its class - RTTI-based code '
    + 'can bind parameters by their names';

type
  // Eine Gruppe der Parameterliste: '[const] A, B: T [= Vorgabe]'.
  TRdxParamGroup = record
    Modifier  : TRdxToken;            // const/var/out/constref; Low = '' ohne
    Names     : TArray<TRdxToken>;
    TypeFirst : TRdxToken;            // erstes und letztes Token des Typs;
    TypeLast  : TRdxToken;            // Low = '' ohne Typ (untypisiert)
  end;

  // Die Parameterliste eines Kopfs; Open.Low = '' ohne Liste.
  TRdxParamList = record
    Open   : TRdxToken;
    Close  : TRdxToken;
    Groups : TArray<TRdxParamGroup>;
    Noise  : Boolean;                 // Kommentar, Direktive oder Attribut
  end;

  // Eine Deklaration zur Implementierung: Kopf (ohne Rumpf), Liste und der
  // Name des Parameters darin.
  TRdxParamDecl = record
    Head        : TRdxRoutine;
    List        : TRdxParamList;
    NameTok     : TRdxToken;
    Group       : Integer;
    InInterface : Boolean;            // freie Routine, vor 'implementation'
  end;

  // Die Stelle eines Funds (ReadSite): die Implementierung, ihre Liste, der
  // Parameter darin und alle Deklarationen derselben Routine.
  TRdxParamSite = record
    Impl      : TRdxRoutine;
    List      : TRdxParamList;
    NameTok   : TRdxToken;
    Group     : Integer;
    IsMethod  : Boolean;
    ClassHead : TRdxClassHead;        // Methoden: die Klasse der Deklaration
    ImplWord  : TRdxToken;            // 'implementation'; Low = '' ohne
    Decls     : TArray<TRdxParamDecl>;
  end;

  // Das Ergebnis der Planer SCA054/SCA170: alle Ersetzungen (EIN Undo-
  // Schritt) und der Name des Parameters fuer den Menuetext - schon aus der
  // Meldung, auch wenn abgelehnt wird.
  TRdxParamPlan = record
    Edits : TArray<TRdxEdit>;
    Name  : string;
  end;

  TRdxUnusedParameterFix = class
  public
    // SCA054: den Parameter der Meldung in Implementierung, Deklarationen
    // und Doku zu '_Name' umbenennen (s. Kopf). Form TRdxPlannerOf
    // (uRdxFixTable).
    class function MarkUnused(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxParamPlan;
      out AReason: string): Boolean; static;

    // Die Stelle des Parameters AName: genau eine Implementierung, deren
    // Kopf auf ALine beginnt und deren Liste AName traegt, dazu ihre
    // Deklarationen mit gleicher Namensliste. '' oder der (uebersetzte)
    // Grund - die gemeinsamen Sperren (Liste, overload, asm, {$I}, Paarung
    // mit den Deklarationen); was ein Vorkommen des Namens im Rumpf
    // bedeutet, prueft jede Hilfe selbst.
    class function ReadSite(AMap: TRdxCodeMap; ALine: Integer;
      const AName: string; out ASite: TRdxParamSite): string; static;

    // Die Ersetzung des Tokens T durch ANewText (Bereich genau das Token).
    class function TokenEdit(AMap: TRdxCodeMap; const T: TRdxToken;
      const ANewText, ARole: string): TRdxEdit; static;
  end;

// Der Parameter aus 'Unused parameter: X (never read in method body)';
// '' ohne diese Form.
function UnusedParamName(const AMessage: string): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(), MsgMovedSuffix, MsgStaleSuffix (nie uLocalization)

const
  SPAN_054 = 'sca054';
  KEY_PARAM = 'Unused parameter: ';
  KEY_END   = ' (never read';
  PARAM_MODIFIERS: array[0..3] of string = ('const', 'var', 'out',
    'constref');
  // Typen mit Rumpf hinter '=' bzw. 'packed' (dazu 'record').
  CLASS_LIKE: array[0..3] of string = ('class', 'object', 'interface',
    'dispinterface');
  // Bloecke mit eigenem end im Code ('case' gesondert: im record ohne).
  CODE_OPENERS: array[0..2] of string = ('begin', 'try', 'asm');
  // Dahinter ist 'record' eine generische Einschraenkung ('<T: record>').
  CONSTRAINT_FOLLOW: array[0..3] of string = ('>', ',', ';', ')');
  STACK_TYPE = 't';
  STACK_CODE = 'c';
  KW_IMPL     = 'implementation';
  KW_CLASS    = 'class';
  KW_OVERLOAD = 'overload';
  KW_FORWARD  = 'forward';
  KW_ASM      = 'asm';
  DOC_PREFIX  = '///';
  DOC_PARAM   = '<param name="';

function UnusedParamName(const AMessage: string): string;
var
  E : Integer;
begin
  Result := '';
  if Pos(KEY_PARAM, AMessage) <> 1 then Exit;
  E := Pos(KEY_END, AMessage);
  if E = 0 then
    E := Length(AMessage) + 1;
  Result := Trim(Copy(AMessage, Length(KEY_PARAM) + 1,
    E - Length(KEY_PARAM) - 1));
end;

procedure AddGroup(var AList: TArray<TRdxParamGroup>; const G: TRdxParamGroup);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := G;
end;

procedure AddDecl(var AList: TArray<TRdxParamDecl>; const D: TRdxParamDecl);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := D;
end;

{ ---- Die Parameterliste ---- }

// Ein Wort aus PARAM_MODIFIERS vor einem Namen oder Attribut ist der
// Modifizierer der Gruppe - 'Out: Integer' ist ein Name.
function IsModifierAt(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  N := After(AMap, T);
  Result := InList(T.Low, PARAM_MODIFIERS) and (N.IsWord or (N.Low = '['));
end;

// Attribute '[ref]' ab T ueberspringen (Noise). False ohne ']'.
function SkipAttributes(AMap: TRdxCodeMap; var AList: TRdxParamList;
  var T: TRdxToken): Boolean;
var
  C : TRdxToken;
begin
  Result := True;
  while T.Low = '[' do
  begin
    AList.Noise := True;
    C := MatchClose(AMap, T);
    if C.Low = '' then
      Exit(False);
    T := After(AMap, C);
  end;
end;

// Ab T bis vor ';' bzw. die schliessende Klammer der Liste AClose - im Typ
// (AInType) auch bis vor '='; Klammern als Ganzes, im Typ auch '<..>'
// (im Vorgabewert ist '<' ein Vergleich). ALast ist das letzte Token davor
// (Low = '' ohne). False, wenn die Liste dabei nicht sauber endet.
function SkipToGroupEnd(AMap: TRdxCodeMap; const AClose: TRdxToken;
  AInType: Boolean; var T: TRdxToken; out ALast: TRdxToken): Boolean;
begin
  ALast := Default(TRdxToken);
  while not (SameTok(T, AClose) or (T.Low = ';')
    or (AInType and (T.Low = '='))) do
  begin
    if (T.Low = '') or TokBefore(AClose, T) then
      Exit(False);
    ALast := T;
    if (T.Low = '(') or (T.Low = '[') or (AInType and (T.Low = '<')) then
    begin
      ALast := MatchClose(AMap, T);
      if ALast.Low = '' then
        Exit(False);
      T := ALast;
    end;
    T := After(AMap, T);
  end;
  Result := True;
end;

// Eine Gruppe ab T; T steht danach auf ';' bzw. der schliessenden Klammer.
// '' oder der Grund.
function ReadGroup(AMap: TRdxCodeMap; var AList: TRdxParamList;
  var T: TRdxToken; out G: TRdxParamGroup): string;
var
  Last : TRdxToken;
begin
  G := Default(TRdxParamGroup);
  Result := _(R_UP_LIST);
  if not SkipAttributes(AMap, AList, T) then Exit;
  if IsModifierAt(AMap, T) then
  begin
    G.Modifier := T;
    T := After(AMap, T);
    if not SkipAttributes(AMap, AList, T) then Exit;
  end;
  while True do
  begin
    if not T.IsWord then Exit;        // auch '&Name'
    AddToken(G.Names, T);
    T := After(AMap, T);
    if T.Low <> ',' then Break;
    T := After(AMap, T);
  end;
  if T.Low = ':' then
  begin
    T := After(AMap, T);
    G.TypeFirst := T;
    if not SkipToGroupEnd(AMap, AList.Close, True, T, Last)
       or (Last.Low = '') then
      Exit;
    G.TypeLast := Last;
    if T.Low = '=' then
    begin
      T := After(AMap, T);
      if not SkipToGroupEnd(AMap, AList.Close, False, T, Last)
         or (Last.Low = '') then
        Exit;
    end;
  end;
  if SameTok(T, AList.Close) or (T.Low = ';') then
    Result := '';
end;

// Die Parameterliste des Kopfs R ('(' hinter dem Namen, Typparameter
// uebersprungen). Ohne Liste '' mit Open.Low = ''. '' oder der Grund.
function ReadParamList(AMap: TRdxCodeMap; const R: TRdxRoutine;
  out AList: TRdxParamList): string;
var
  T : TRdxToken;
  G : TRdxParamGroup;
begin
  AList := Default(TRdxParamList);
  T := After(AMap, R.NameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low <> '(' then
    Exit('');
  AList.Open := T;
  AList.Close := MatchClose(AMap, T);
  if (AList.Close.Low = '') or not TokBefore(AList.Close, R.HeaderEnd) then
    Exit(_(R_UP_LIST));
  AList.Noise := CommentInRange(AMap, TRefactorSpan.Make(SPAN_054,
    AList.Open.Line, AList.Open.Col, AList.Close.Line, AList.Close.EndCol));
  T := After(AMap, AList.Open);
  if SameTok(T, AList.Close) then
    Exit('');
  while True do
  begin
    Result := ReadGroup(AMap, AList, T, G);
    if Result <> '' then Exit;
    AddGroup(AList.Groups, G);
    if SameTok(T, AList.Close) then
      Exit('');
    T := After(AMap, T);
  end;
end;

// Wie oft traegt AList den Namen ALowName (klein)? Der letzte Treffer in
// ATok und AGroup.
function NameIn(const AList: TRdxParamList; const ALowName: string;
  out ATok: TRdxToken; out AGroup: Integer): Integer;
var
  i : Integer;
  T : TRdxToken;
begin
  Result := 0;
  ATok := Default(TRdxToken);
  AGroup := -1;
  for i := 0 to High(AList.Groups) do
    for T in AList.Groups[i].Names do
      if SameIdent(T.Low, ALowName) then
      begin
        Inc(Result);
        ATok := T;
        AGroup := i;
      end;
end;

// Tragen beide Listen dieselben Namen in derselben Reihenfolge?
function SameNames(const A, B: TRdxParamList): Boolean;
var
  NA, NB : TArray<TRdxToken>;
  i      : Integer;
  G      : TRdxParamGroup;
  T      : TRdxToken;
begin
  NA := nil;
  NB := nil;
  for G in A.Groups do
    for T in G.Names do
      AddToken(NA, T);
  for G in B.Groups do
    for T in G.Names do
      AddToken(NB, T);
  Result := Length(NA) = Length(NB);
  i := 0;
  while Result and (i < Length(NA)) do
  begin
    Result := SameIdent(NA[i].Low, NB[i].Low);
    Inc(i);
  end;
end;

{ ---- Die Datei ---- }

// Das erste 'implementation' als Schluesselwort; Low = '' ohne (Programm).
function ImplementationWord(AMap: TRdxCodeMap): TRdxToken;
var
  T : TRdxToken;
begin
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_IMPL);
  while T.Low <> '' do
  begin
    if (T.Low = KW_IMPL) and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T);
    T := NextTokenOnLineWith(AMap, T, KW_IMPL);
  end;
  Result := Default(TRdxToken);
end;

// Oeffnet T (Token davor AP) einen Typrumpf mit eigenem end? 'record'
// ausser als generische Einschraenkung; class/object/interface/
// dispinterface hinter '=' bzw. 'packed' mit Rumpf (TypeHasBody).
function OpensType(AMap: TRdxCodeMap; const T, AP: TRdxToken): Boolean;
begin
  if T.Low = 'record' then
    Result := not InList(After(AMap, T).Low, CONSTRAINT_FOLLOW)
  else
    Result := InList(T.Low, CLASS_LIKE) and InList(AP.Low, ['=', 'packed'])
      and TypeHasBody(AMap, T);
end;

// Ist T das Kopfwort einer Routine mit dem EINGLIEDRIGEN Namen ALowName
// ('procedure Foo', nicht 'procedure Foo.Bar')?
function NamedSingle(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowName: string): Boolean;
var
  N, M : TRdxToken;
begin
  N := After(AMap, T);
  Result := False;
  if not SameIdent(N.Low, ALowName) then Exit;
  M := After(AMap, N);
  if M.Low = '<' then
    M := AfterClose(AMap, M);
  Result := M.Low <> '.';
end;

// Die Koepfe (HeadStart) der Routinen mit dem eingliedrigen Namen ALowName
// ausserhalb jedes Typrumpfs - Deklarationen im interface-Teil, forward,
// Implementierungen, lokale Routinen. Ein Lauf ueber die Datei mit einem
// Stapel der Bloecke: Typrumpf ('t') oder Code ('c'); 'case' oeffnet nur
// im Code ein eigenes end (im record ist es der variante Teil).
function TopLevelHeads(AMap: TRdxCodeMap;
  const ALowName: string): TArray<TRdxToken>;
var
  T, P  : TRdxToken;
  Stack : string;
begin
  Result := nil;
  Stack := '';
  P := Default(TRdxToken);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if IsKeywordAt(AMap, T, P) then
    begin
      if T.Low = 'end' then
      begin
        if Stack <> '' then
          SetLength(Stack, Length(Stack) - 1);
      end
      else if OpensType(AMap, T, P) then
        Stack := Stack + STACK_TYPE
      else if T.Low = 'case' then
      begin
        if (Stack = '') or (Stack[Length(Stack)] <> STACK_TYPE) then
          Stack := Stack + STACK_CODE;
      end
      else if InList(T.Low, CODE_OPENERS) then
        Stack := Stack + STACK_CODE
      else if (Pos(STACK_TYPE, Stack) = 0) and IsRoutineHeadAfter(T, P)
         and NamedSingle(AMap, T, ALowName) then
        AddToken(Result, HeadStart(AMap, T));
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// asm in der Routine R?
function AsmIn(AMap: TRdxCodeMap; const R: TRdxRoutine): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  P := Before(AMap, R.Head);
  T := R.Head;
  while (T.Low <> '') and not TokBefore(R.Last, T) do
  begin
    if (T.Low = KW_ASM) and IsKeywordAfter(T, P) then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

{ ---- Implementierung und Deklarationen ---- }

// Die eine Implementierung auf ALine, deren Liste AName traegt. '' oder
// der Grund.
function ImplOn(AMap: TRdxCodeMap; ALine: Integer; const AName: string;
  var ASite: TRdxParamSite): string;
var
  T, Tok : TRdxToken;
  R      : TRdxRoutine;
  L      : TRdxParamList;
  n, G   : Integer;
  Failed : string;
  NameLow: string;
begin
  n := 0;
  Failed := '';
  NameLow := LowerCase(AName);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsRoutineHead(AMap, T) then
    begin
      if TRdxBlocks.ReadRoutine(AMap, T, R) <> '' then
      begin
        if Failed = '' then
          Failed := _(R_UP_BOUNDS);
      end
      else if R.Body.Low <> '' then
      begin
        Result := ReadParamList(AMap, R, L);
        if Result <> '' then
        begin
          if Failed = '' then
            Failed := Result;
        end
        else if NameIn(L, NameLow, Tok, G) = 1 then
        begin
          Inc(n);
          ASite.Impl := R;
          ASite.List := L;
          ASite.NameTok := Tok;
          ASite.Group := G;
        end;
      end;
    end;
    T := After(AMap, T);
  end;
  if n = 1 then
    Result := ''
  else if n > 1 then
    Result := _(R_UP_MANY_HEADS, [n, AName])
  else if Failed <> '' then
    Result := Failed
  else
    Result := MsgMovedSuffix(_(R_UP_NO_HEAD, [AName]));
end;

// Methode: genau eine Implementierung (diese) und genau eine Deklaration
// in einer Klasse dieses Namens, deren Kopf EnclosingClass findet.
function MethodDecls(AMap: TRdxCodeMap; var ASite: TRdxParamSite): string;
var
  ClassPath, Meth : string;
  Heads           : TArray<TRdxToken>;
  D               : TRdxParamDecl;
  n               : Integer;
begin
  ClassPath := Copy(ASite.Impl.Name, 1,
    LastDelimiter('.', ASite.Impl.Name) - 1);
  Meth := TokText(AMap, ASite.Impl.NameTok);
  Heads := TRdxBlocks.FindMethodImpls(AMap, ClassPath, Meth);
  n := Length(Heads);
  if (n <> 1) or not SameTok(Heads[0], ASite.Impl.Head) then
    Exit(_(R_UP_MANY_IMPLS, [n, ASite.Impl.Name]));
  Heads := TRdxBlocks.FindMethodDecls(AMap, ClassPath, Meth);
  n := Length(Heads);
  if n = 0 then
    Exit(_(R_UP_NO_DECL, [ASite.Impl.Name]));
  if n > 1 then
    Exit(MsgDeclsInClassesOfName(n, Meth));
  D := Default(TRdxParamDecl);
  if TRdxBlocks.MethodDecl(AMap, Heads[0], D.Head) <> '' then
    Exit(_(R_UP_DECL_FORM, [ASite.Impl.Name, Heads[0].Line]));
  if not EnclosingClass(AMap, D.Head.Head, LowerCase(LastPart(ClassPath)),
     ASite.ClassHead) then
    Exit(_(R_UP_BOUNDS));
  AddDecl(ASite.Decls, D);
  Result := '';
end;

// Freie Routine: jeder andere Kopf gleichen Namens ausserhalb eines
// Typrumpfs ist die Deklaration im interface-Teil oder ein forward - sonst
// ein Zwilling (Sperre). Die Implementierung selbst muss unter den Koepfen
// sein, sonst ist der Lauf ueber die Bloecke aus dem Tritt.
function FreeDecls(AMap: TRdxCodeMap; var ASite: TRdxParamSite): string;
var
  Heads : TArray<TRdxToken>;
  H     : TRdxToken;
  D     : TRdxParamDecl;
  Fwd   : TRdxRoutine;
  Seen  : Boolean;
  W     : string;
begin
  Seen := False;
  Heads := TopLevelHeads(AMap, LowerCase(ASite.Impl.Name));
  for H in Heads do
  begin
    if SameTok(H, ASite.Impl.Head) then
    begin
      Seen := True;
      Continue;
    end;
    D := Default(TRdxParamDecl);
    if (ASite.ImplWord.Low <> '') and TokBefore(H, ASite.ImplWord) then
    begin
      if TRdxBlocks.MethodDecl(AMap, H, D.Head) <> '' then
        Exit(_(R_UP_DECL_FORM, [ASite.Impl.Name, H.Line]));
      D.InInterface := True;
    end
    else if (TRdxBlocks.ReadRoutine(AMap, H, Fwd) = '')
       and HasDirective(Fwd, [KW_FORWARD], W) then
      D.Head := Fwd
    else
      Exit(_(R_UP_TWIN, [ASite.Impl.Name, H.Line]));
    AddDecl(ASite.Decls, D);
  end;
  if Seen then
    Result := ''
  else
    Result := _(R_UP_BOUNDS);
end;

// Die Liste der Deklaration ADecl lesen und gegen die Implementierung
// pruefen. '' oder der Grund.
function DeclListReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite;
  const ALowName: string; var ADecl: TRdxParamDecl): string;
var
  W : string;
begin
  Result := ReadParamList(AMap, ADecl.Head, ADecl.List);
  if Result <> '' then Exit;
  if ADecl.List.Noise then
    Exit(_(R_UP_NOISE));
  if HasDirective(ADecl.Head, [KW_OVERLOAD], W) then
    Exit(_(R_UP_OVERLOAD, [ASite.Impl.Name]));
  if not SameNames(ADecl.List, ASite.List)
     or (NameIn(ADecl.List, ALowName, ADecl.NameTok, ADecl.Group) <> 1) then
    Result := _(R_UP_DECL_DIFFERS, [ADecl.Head.Head.Line]);
end;

{ ---- SCA054 ---- }

// Ein Attribut vor Implementierung, Deklaration oder Klasse? '' oder der
// Grund.
function AttributeReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite): string;
var
  D     : TRdxParamDecl;
  Found : Boolean;
begin
  Found := Before(AMap, ASite.Impl.Head).Low = ']';
  for D in ASite.Decls do
    Found := Found or (Before(AMap, D.Head.Head).Low = ']');
  if ASite.IsMethod then
    Found := Found or (Before(AMap, ASite.ClassHead.NameTok).Low = ']');
  if Found then
    Result := _(R_UP_ATTRIBUTE)
  else
    Result := '';
end;

// Kommt der Name im Bereich der Routine (ab der Liste bis zum letzten ';')
// ausser als der Parameter selbst vor? '' oder der Grund.
function UsedReason(AMap: TRdxCodeMap; const ASite: TRdxParamSite;
  const AName: string): string;
var
  T       : TRdxToken;
  NameLow : string;
begin
  Result := '';
  NameLow := LowerCase(AName);
  T := ASite.List.Open;
  while (T.Low <> '') and not TokBefore(ASite.Impl.Last, T) do
  begin
    if SameIdent(T.Low, NameLow) and not SameTok(T, ASite.NameTok) then
      Exit(MsgStaleSuffix(_(R_UP_USED, [AName, T.Line])));
    T := After(AMap, T);
  end;
end;

// Steht der neue Name ANew schon als Code in der Datei? '' oder der Grund.
function TakenReason(AMap: TRdxCodeMap; const ANew: string): string;
var
  T       : TRdxToken;
  NewLow  : string;
begin
  Result := '';
  NewLow := LowerCase(ANew);
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if SameIdent(T.Low, NewLow) then
      Exit(_(R_UP_TAKEN, [ANew, T.Line]));
    T := After(AMap, T);
  end;
end;

// Eine '///'-Zeile: davor nur Leerraum, der '//'-Kommentar beginnt dort.
function DocLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L : string;
  i : Integer;
begin
  L := AMap.Raw(ALine);
  i := SkipBlanks(L, 1);
  Result := (Copy(L, i, Length(DOC_PREFIX)) = DOC_PREFIX)
    and (AMap.LineCommentCol(ALine) = i) and not AMap.StartsInside(ALine);
end;

// '<param name="AName">' in den '///'-Zeilen direkt ueber AHead: je
// Treffer die Ersetzung des Namens durch '_' + Name.
procedure AddDocEdits(AMap: TRdxCodeMap; const AHead: TRdxToken;
  const AName: string; var AEdits: TArray<TRdxEdit>);
var
  Li, P, C, Q : Integer;
  L, LowL, Old : string;
  E           : TRdxEdit;
begin
  Li := AHead.Line - 1;
  while (Li >= 1) and DocLine(AMap, Li) do
  begin
    L := AMap.Raw(Li);
    LowL := LowerCase(L);
    P := Pos(DOC_PARAM, LowL);
    while P > 0 do
    begin
      C := P + Length(DOC_PARAM);
      Q := C;
      while (Q <= Length(L)) and (L[Q] <> '"') do
        Inc(Q);
      Old := Copy(L, C, Q - C);
      if (Q <= Length(L)) and SameText(Old, AName) then
      begin
        E.Span := TRefactorSpan.Make(SPAN_054, Li, C, Li, Q);
        E.Expected := RangeText(AMap, E.Span);
        E.NewText := '_' + Old;
        AddEdit(AEdits, E);
      end;
      P := Pos(DOC_PARAM, LowL, Q);
    end;
    Dec(Li);
  end;
end;

{ TRdxUnusedParameterFix }

class function TRdxUnusedParameterFix.TokenEdit(AMap: TRdxCodeMap;
  const T: TRdxToken; const ANewText, ARole: string): TRdxEdit;
begin
  Result.Span := TRefactorSpan.Make(ARole, T.Line, T.Col, T.Line, T.EndCol);
  Result.Expected := RangeText(AMap, Result.Span);
  Result.NewText := ANewText;
end;

class function TRdxUnusedParameterFix.ReadSite(AMap: TRdxCodeMap;
  ALine: Integer; const AName: string; out ASite: TRdxParamSite): string;
var
  i, IncLine : Integer;
  W          : string;
begin
  ASite := Default(TRdxParamSite);
  Result := ImplOn(AMap, ALine, AName, ASite);
  if Result <> '' then Exit;
  if ASite.List.Noise then
    Exit(_(R_UP_NOISE));
  if HasDirective(ASite.Impl, [KW_OVERLOAD], W) then
    Exit(_(R_UP_OVERLOAD, [ASite.Impl.Name]));
  if AsmIn(AMap, ASite.Impl) then
    Exit(_(R_UP_ASM));
  ASite.ImplWord := ImplementationWord(AMap);
  ASite.IsMethod := Length(ASite.Impl.Parts) > 1;
  if ASite.IsMethod then
    IncLine := IncludeInLines(AMap, ASite.Impl.Head.Line,
      ASite.Impl.Last.Line)
  else
    IncLine := IncludeInLines(AMap, 1, AMap.LineCount);
  if IncLine > 0 then
    Exit(_(R_UP_INCLUDE, [IncLine]));
  if ASite.IsMethod then
    Result := MethodDecls(AMap, ASite)
  else if ASite.Impl.Head.Low = KW_CLASS then
    Result := _(R_UP_BOUNDS)
  else
    Result := FreeDecls(AMap, ASite);
  if Result <> '' then Exit;
  for i := 0 to High(ASite.Decls) do
  begin
    Result := DeclListReason(AMap, ASite, LowerCase(AName), ASite.Decls[i]);
    if Result <> '' then Exit;
  end;
end;

class function TRdxUnusedParameterFix.MarkUnused(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxParamPlan;
  out AReason: string): Boolean;
var
  Site : TRdxParamSite;
  Name : string;
  D    : TRdxParamDecl;
begin
  APlan := Default(TRdxParamPlan);
  Name := UnusedParamName(AMessage);
  APlan.Name := Name;
  if Name = '' then
    AReason := _(R_UP_NO_NAME)
  else if Name[1] = '_' then
    AReason := MsgStaleSuffix(_(R_UP_UNDERSCORE, [Name]))
  else
    AReason := ReadSite(AMap, ALine, Name, Site);
  if AReason = '' then
    AReason := AttributeReason(AMap, Site);
  if AReason = '' then
    AReason := UsedReason(AMap, Site, Name);
  if AReason = '' then
    AReason := TakenReason(AMap, '_' + Name);
  Result := AReason = '';
  if not Result then Exit;
  APlan.Name := TokText(AMap, Site.NameTok);
  for D in Site.Decls do
  begin
    AddEdit(APlan.Edits, TokenEdit(AMap, D.NameTok,
      '_' + TokText(AMap, D.NameTok), SPAN_054));
    AddDocEdits(AMap, D.Head.Head, Name, APlan.Edits);
  end;
  AddEdit(APlan.Edits, TokenEdit(AMap, Site.NameTok,
    '_' + TokText(AMap, Site.NameTok), SPAN_054));
  AddDocEdits(AMap, Site.Impl.Head, Name, APlan.Edits);
end;

end.
