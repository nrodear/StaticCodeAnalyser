unit uRdxObjectListFix;

// reDelphix - Editorhilfe fuer SCA174 TObjectListWithoutOwnership, OHNE
// ToolsAPI und ohne Parser: die lokale Liste 'L: TList<TFoo>', die frisch
// erzeugte Objekte aufnimmt ('L.Add(TFoo.Create)'), wird eine
// 'TObjectList<TFoo>' - in der Deklaration UND im 'TList<TFoo>.Create',
// zwei Ersetzungen in EINEM Undo-Schritt (TRdxObjectListPlan.Edits). Danach
// gibt die Liste ihre Elemente frei (OwnsObjects ist True) - bei Free, aber
// auch bei Clear, Delete und Remove. Das ist der Fix, und es aendert das
// Verhalten (Kennzeichnung, Changes: True).
//
// DER FUND (uTObjectListWithoutOwnership): je Methode die Zuweisungen
// 'X := TList<T>.Create' (T beginnt mit 'T'), dann jeder Aufruf
// 'X.Add(<Klasse>.Create' derselben Methode; gemeldet wird die Zeile des
// ADD-Aufrufs (nkCall.Line). Die Meldung nennt den Typ der Liste und den
// Namen KLEIN geschrieben (Qualifier 'Self.' entfernt):
//   'TList<TFoo> "l" gets a new TFoo.Create - instances will leak when the
//   list is freed. Use TObjectList<TFoo> instead (OwnsObjects=True is the
//   default).'
// Eine zeitliche Ordnung kennt der Detektor nicht (Posten 306): ein Add
// einer frueheren Inkarnation faellt einer spaeteren Zuweisung zur Last.
// Die Hilfe verlangt darum genau EINE Zuweisung der Variablen in der
// Routine.
//
// BEWIESEN (am Text, konservativ), sonst keine Hilfe:
//   - auf der gemeldeten Zeile steht 'X.Add(' im Code;
//   - X ist eine LOKALE Variable der innersten Routine um diese Zeile:
//     deklariert in deren var-Abschnitt ('X: TList<T>;', nicht mit anderen
//     zusammen) oder inline ('var X: TList<T> := ..', 'var X := ..');
//     kein Parameter, kein Feld, keine globale Variable - eine solche Liste
//     kann anderswo gefuellt, geleert oder freigegeben werden. In einer
//     verschachtelten Routine und im Deklarationsteil kommt X sonst nicht
//     vor;
//   - X wird genau einmal zugewiesen: 'X := TList<T>.Create' (auch '()'),
//     ohne Argumente - 'Create(Collection)' uebernaehme fremde Objekte;
//   - jedes Hinzufuegen ('Add', 'Insert') nimmt ein Objekt, das genau dort
//     entsteht ('TFoo.Create', Argumente nur Literale): ein Objekt aus
//     einer Variablen kann einen anderen Besitzer haben, ein Argument wie
//     'Self' oder 'Owner' als TComponent-Besitzer gibt es selbst frei;
//   - kein Element verlaesst die Liste: ein Element ('X[i]', 'X.Items[i]',
//     'X.First', 'X.Last', die Laufvariable von 'for E in X do') steht nur
//     vor einem '.' und einem Member, das nicht 'Free' o. ae. ist - also nie
//     als Wert (Zuweisung, Argument, 'FreeAndNil(X[i])', 'with X[i] do')
//     und wird nie freigegeben ('X[i].Free' gaebe es danach doppelt frei);
//   - von der Liste selbst nur Members aus einer festen Liste (Free, Count,
//     Sort, IndexOf, Clear, Delete ...); 'Extract', 'Remove', 'ToArray',
//     'List', 'AddRange', 'OnNotify' und jedes unbekannte Member sperren,
//     ebenso eine Zuweisung an ein Member ('X.Count := 0', 'X[i] := ..').
//     X selbst steht sonst nur in 'FreeAndNil(X)', 'Assigned(X)' und
//     'X = nil' bzw. 'X <> nil' - nie als Wert (Argument, Result, Feld);
//   - die Routine traegt keine Compiler-Direktive (bedingter Code) und
//     kein 'with' (ein Name darin koennte an ein Member binden);
//   - System.Generics.Collections (oder Generics.Collections) steht in
//     einer uses-Klausel der Datei - dort ist TObjectList<T>; die Datei
//     deklariert keinen eigenen Typ TList bzw. TObjectList.
//
// GRENZEN: ob TFoo eine Klasse ist (TObjectList<T: class>), prueft die
// Hilfe nicht - fuer einen Record uebersetzte es danach nicht (kein
// stilles Fehlverhalten). Ein Konstruktor, der das neue Objekt selbst
// irgendwo eintraegt (Registry, globale Liste), ist am Text nicht zu
// sehen. Eine fremde Bibliothek mit eigener TList<T> in einer Unit hinter
// Generics.Collections (Spring4D u. a.) erkennt die Hilfe nicht.
//
// FPC-TAUGLICH: nur Textlogik auf der Code-Sicht (uRdxCodeMap, uRdxBlocks,
// uRdxBufferMath, uRdxText, uRefactorInfo). Den Adapter fuer die Tabelle
// (PlanObjectList ueber TRdxFixFrame) traegt uRdxFixTable (Hausregel
// dort).

interface

uses
  uRdxBufferMath,   // TRdxEdit
  uRdxCodeMap;      // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()).
  R_OL_NO_MESSAGE = 'the message names no list variable or no item type';
  R_OL_NO_ADD = 'no "%s.Add(" on the reported line';
  R_OL_NO_ROUTINE = 'no routine with a begin..end body around the reported '
    + 'line';
  R_OL_BOUNDS = 'the bounds of the routine around the reported line are not '
    + 'safe to read';
  R_OL_DIRECTIVE = 'compiler directive in the routine - conditional code '
    + 'could hide a use of the list';
  R_OL_WITH = 'the routine contains a "with" statement - a name in it could '
    + 'bind to a member';
  R_OL_PARAM = '"%s" is a parameter of the routine - the list comes from the '
    + 'caller';
  R_OL_NOT_LOCAL = '"%s" is not a local variable of the routine - a field or '
    + 'global list can be filled or freed elsewhere';
  R_OL_NESTED = '"%s" also appears in the declaration part of the routine '
    + '(line %d) - a nested routine or a second declaration';
  R_OL_DECLS = '"%s" is declared more than once in the routine';
  R_OL_GROUPED = '"%s" is declared together with other variables - their '
    + 'type would change too';
  R_OL_DECL_TYPE = 'the declaration of "%s" (line %d) is not "TList<%s>"';
  R_OL_ASSIGNS = '"%s" is assigned %d times in the routine - the help needs '
    + 'exactly one "TList<%s>.Create"';
  R_OL_CREATE = 'the assignment to "%s" (line %d) is not "TList<%s>.Create" '
    + 'without arguments';
  R_OL_ADD_ARG = 'line %d adds an object that is not created right there '
    + '(or with a non-literal argument such as an owner) - it may have '
    + 'another owner';
  R_OL_ITEM = 'line %d uses an item of the list as a value or frees it - '
    + 'after the change the list frees it, too';
  R_OL_MEMBER = '"%s.%s" (line %d) is not checked by the help - it could '
    + 'hand out or free items';
  R_OL_SETTER = 'line %d assigns to a property of "%s" - an owning list '
    + 'frees the items it drops';
  R_OL_VALUE = '"%s" is used as a value on line %d (passed, assigned or '
    + 'returned) - the list or its items may get another owner';
  R_OL_LOOP_VAR = 'the loop variable "%s" (line %d) is used as a value or '
    + 'freed - after the change the list frees its items';
  R_OL_USES = 'System.Generics.Collections is not in a uses clause of the '
    + 'file - TObjectList<T> may not come from there';
  R_OL_OWN_TYPE = 'the file declares its own type %s';

type
  // Ergebnis des Planers: die Ersetzungen (EIN Undo-Schritt - Deklaration
  // und Create; bei 'var X := TList<T>.Create' nur das Create) und der
  // Elementtyp fuer den Menuetext - schon aus der Meldung, auch wenn
  // abgelehnt wird.
  TRdxObjectListPlan = record
    Edits : TArray<TRdxEdit>;
    Name  : string;
  end;

  // Der Planer auf der Code-Sicht in der Form TRdxPlannerOf<TPlan>
  // (uRdxFixTable): True genau dann, wenn AReason = ''.
  TRdxObjectListFix = class
  public
    // SCA174: 'TList<T>' -> 'TObjectList<T>' in Deklaration und Create der
    // lokalen Liste der Meldung (s. Kopf der Unit).
    class function OwnItems(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxObjectListPlan;
      out AReason: string): Boolean; static;
  end;

// Der Elementtyp der Meldung ('TList<TFoo> "l" gets ...' -> 'TFoo'); ''
// ohne.
function ListTypeArgOf(const AMessage: string): string;
// Der Name der Liste in der Meldung, klein wie gemeldet ('l'); '' ohne.
function ListVarOf(const AMessage: string): string;

implementation

uses
  System.SysUtils,
  uRefactorInfo,    // TRefactorSpan.Make
  uRdxText,         // _(): in die reDelphix-Sprache, nie uLocalization
  uRdxBlocks;       // TRdxBlocks.HeadBefore, TRdxRoutine, TRdxHeadStep

const
  SPAN_174 = 'sca174';
  MSG_LIST_PREFIX = 'TList<';
  MSG_LIST_CLOSE = '>';
  QUOTE_NAME = '"';
  NEW_CLASS = 'TObjectList';
  KW_TLIST = 'tlist';
  KW_TOBJECTLIST = 'tobjectlist';
  KW_CREATE = 'create';
  KW_USES = 'uses';
  // Hier endet die Suche nach der Routine um die Zeile: UNIT_BOUNDS
  // (uRdxCodeMap, seit der Folgewelle B1 zentral).
  // Dahinter endet die Anweisung 'X := TList<T>.Create'.
  STATEMENT_ENDS: array[0..5] of string = (';', 'end', 'else', 'until',
    'finally', 'except');
  // Rueckwaerts von einer Deklaration: das erste dieser Woerter nennt den
  // Abschnitt ('var' - sonst Konstante, Typ, Feld eines lokalen Records ...).
  DECL_STOPS: array[0..18] of string = ('var', 'const', 'type', 'label',
    'resourcestring', 'threadvar', 'begin', 'end', 'record', 'class',
    'object', 'interface', 'procedure', 'function', 'constructor',
    'destructor', 'operator', 'property', 'case');
  // Members der Liste, die die Liste freigeben.
  LIST_FREE: array[0..2] of string = ('free', 'disposeof', 'destroy');
  // Members, die ein Element hinzufuegen (Argument: frisches Objekt).
  LIST_ADDERS: array[0..1] of string = ('add', 'insert');
  // Members, die ein Element liefern (danach nur '.' und ein Member).
  LIST_ITEMS: array[0..2] of string = ('items', 'first', 'last');
  // Members, die kein Element herausgeben - Clear, Delete, DeleteRange
  // geben bei der besitzenden Liste frei, was niemand sonst haelt.
  LIST_SAFE: array[0..12] of string = ('count', 'capacity', 'sort',
    'exchange', 'move', 'reverse', 'indexof', 'contains', 'clear', 'delete',
    'deleterange', 'trimexcess', 'pack');
  // Members eines Elements, die es freigeben.
  ITEM_FREE: array[0..5] of string = ('free', 'disposeof', 'destroy',
    'release', 'freeinstance', 'cleanupinstance');
  // Woerter, die als Argument eines Konstruktors Literale sind.
  LITERAL_WORDS: array[0..2] of string = ('nil', 'true', 'false');
  // Satzzeichen, die in einem Literal-Argument stehen duerfen ('-1', '1.5',
  // '#13').
  LITERAL_MARKS: array[0..4] of string = (',', '-', '+', '.', '#');
  // 'FreeAndNil(X)' und 'Assigned(X)' - X darin ist kein Wert, der die
  // Liste weitergibt.
  GUARD_CALLS: array[0..1] of string = ('freeandnil', 'assigned');
  NIL_COMPARE: array[0..1] of string = ('=', '<>');
  GENERICS_UNITS: array[0..1] of string = ('system.generics.collections',
    'generics.collections');

function ListTypeArgOf(const AMessage: string): string;
var
  P, Q : Integer;
  Rest : string;
begin
  Result := '';
  P := Pos(MSG_LIST_PREFIX, AMessage);
  if P = 0 then Exit;
  Rest := Copy(AMessage, P + Length(MSG_LIST_PREFIX), MaxInt);
  Q := Pos(MSG_LIST_CLOSE, Rest);
  if Q = 0 then Exit;
  Result := Trim(Copy(Rest, 1, Q - 1));
end;

function ListVarOf(const AMessage: string): string;
begin
  Result := QuotedText(AMessage, QUOTE_NAME);
end;

// Ist T ein Vorkommen der Variablen ALowVar - ein Wort, nicht Member eines
// anderen ('Obj.L')?
function IsVarTok(AMap: TRdxCodeMap; const T: TRdxToken;
  const ALowVar: string): Boolean;
begin
  Result := T.IsWord and SameIdent(T.Low, ALowVar)
    and (Before(AMap, T).Low <> '.');
end;

// Das erste 'X.Add(' im Code von ALine (X = ALowVar); Low = '' ohne.
function AddOnLine(AMap: TRdxCodeMap; ALine: Integer;
  const ALowVar: string): TRdxToken;
var
  T, D, M : TRdxToken;
begin
  Result := Default(TRdxToken);
  if (ALine < 1) or (ALine > AMap.LineCount) then Exit;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsVarTok(AMap, T, ALowVar) then
    begin
      D := After(AMap, T);
      M := After(AMap, D);
      if (D.Low = '.') and (M.Low = 'add') and (After(AMap, M).Low = '(') then
        Exit(T);
    end;
    T := After(AMap, T);
  end;
end;

// Die innerste Routine mit begin..end-Rumpf um AAt mit den Gruenden
// dieser Unit; '' oder der Grund. Die Suche ist der Baustein
// uRdxBlocks.BeginBodyAround (bis zur Hygiene-Welle H1 hier als Kopie
// ausgeschrieben): ein Kopf mit unsicheren Grenzen beendet sie.
function EnclosingRoutine(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): string;
begin
  case BeginBodyAround(AMap, AAt, ARoutine) of
    rbfUnsure: Result := _(R_OL_BOUNDS);
    rbfNone:   Result := _(R_OL_NO_ROUTINE);
  else
    Result := '';
  end;
end;

// Ein 'with' als Schluesselwort zwischen Kopf und end der Routine?
function HasWith(AMap: TRdxCodeMap; const R: TRdxRoutine): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  P := R.Head;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, R.EndTok) do
  begin
    if (T.Low = 'with') and IsKeywordAfter(T, P) then
      Exit(True);
    P := T;
    T := After(AMap, T);
  end;
end;

// Alle Vorkommen der Variablen zwischen Kopf und end der Routine.
function Occurrences(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ALowVar: string): TArray<TRdxToken>;
var
  T : TRdxToken;
begin
  Result := nil;
  T := R.Head;
  while (T.Low <> '') and TokBefore(T, R.EndTok) do
  begin
    if IsVarTok(AMap, T, ALowVar) then
      AddToken(Result, T);
    T := After(AMap, T);
  end;
end;

// Steht ADecl (im Deklarationsteil der Routine R) in einem var-Abschnitt?
// Rueckwaerts das erste Wort aus DECL_STOPS muss 'var' sein.
function InVarSection(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const ADecl: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := Before(AMap, ADecl);
  while (T.Low <> '') and TokBefore(R.HeaderEnd, T) do
  begin
    if InList(T.Low, DECL_STOPS) and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T.Low = 'var');
    T := Before(AMap, T);
  end;
end;

// Steht ab AFrom 'TList<T>' (T wie ALowType)? True mit dem Token 'TList'
// und dem Token hinter '>'.
function ReadListType(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  const ALowType: string; out AList, AAfter: TRdxToken): Boolean;
var
  Open, Arg, Close : TRdxToken;
begin
  AList := AFrom;
  AAfter := Default(TRdxToken);
  Result := False;
  if AFrom.Low <> KW_TLIST then Exit;
  Open := After(AMap, AFrom);
  Arg := After(AMap, Open);
  Close := After(AMap, Arg);
  if (Open.Low <> '<') or (Arg.Low <> ALowType) or (Close.Low <> '>') then
    Exit;
  AAfter := After(AMap, Close);
  Result := True;
end;

// Steht ab AFrom (hinter ':=') 'TList<T>.Create' ohne Argumente, dahinter
// das Ende der Anweisung? True mit dem Token 'TList'.
function ReadCreate(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  const ALowType: string; out AList: TRdxToken): Boolean;
var
  T, C : TRdxToken;
begin
  Result := False;
  if not ReadListType(AMap, AFrom, ALowType, AList, T) then Exit;
  if T.Low <> '.' then Exit;
  C := After(AMap, T);
  if C.Low <> KW_CREATE then Exit;
  T := After(AMap, C);
  if T.Low = '(' then
  begin
    T := After(AMap, T);
    if T.Low <> ')' then Exit;
    T := After(AMap, T);
  end;
  Result := InList(T.Low, STATEMENT_ENDS);
end;

// Steht ab AFrom ein Objekt, das genau dort entsteht - 'TFoo.Create',
// 'Unit.TFoo.Create', Argumente nur Literale (Strings sieht die Code-Sicht
// nicht als Token)? True mit dem Token dahinter in AEnd.
function FreshCreate(AMap: TRdxCodeMap; const AFrom: TRdxToken;
  out AEnd: TRdxToken): Boolean;
var
  T, N, C : TRdxToken;
begin
  Result := False;
  AEnd := Default(TRdxToken);
  if (not AFrom.IsWord) or (AFrom.Low = KW_CREATE) then Exit;
  T := AFrom;
  repeat
    N := After(AMap, T);
    if N.Low <> '.' then Exit;
    T := After(AMap, N);
    if not T.IsWord then Exit;
  until T.Low = KW_CREATE;
  N := After(AMap, T);
  if N.Low = '(' then
  begin
    C := MatchClose(AMap, N);
    if C.Low = '' then Exit;
    T := After(AMap, N);
    while (T.Low <> '') and not SameTok(T, C) do
    begin
      if T.IsWord then
      begin
        if not InList(T.Low, LITERAL_WORDS) then Exit;
      end
      else if not (CharInSet(T.Low[1], ['0'..'9'])
                   or InList(T.Low, LITERAL_MARKS)) then
        Exit;
      T := After(AMap, T);
    end;
    N := After(AMap, C);
  end;
  AEnd := N;
  Result := True;
end;

// 'X.Add(..)' bzw. 'X.Insert(.., ..)' ab dem Member AMember: das (letzte)
// Argument ist ein frisches Objekt. '' oder der Grund.
function AdderReason(AMap: TRdxCodeMap; const AMember: TRdxToken): string;
var
  Open, Close, T, E : TRdxToken;
  Depth             : Integer;
begin
  Result := _(R_OL_ADD_ARG, [AMember.Line]);
  Open := After(AMap, AMember);
  if Open.Low <> '(' then Exit;
  Close := MatchClose(AMap, Open);
  if Close.Low = '' then Exit;
  T := After(AMap, Open);
  if AMember.Low = 'insert' then
  begin
    // Das erste Argument (der Index) bis zum Komma der obersten Ebene.
    Depth := 0;
    while (T.Low <> '') and not SameTok(T, Close)
          and not ((Depth = 0) and (T.Low = ',')) do
    begin
      Depth := Depth + ParenDelta(T);
      T := After(AMap, T);
    end;
    if T.Low <> ',' then Exit;
    T := After(AMap, T);
  end;
  if FreshCreate(AMap, T, E) and SameTok(E, Close) then
    Result := '';
end;

// Hinter einem Element (AAfter: das Token nach 'X[i]', 'X.Items[i]',
// 'X.First' ...) steht nur '.' und ein Member, das es nicht freigibt?
function ItemUseOk(AMap: TRdxCodeMap; const AAfter: TRdxToken): Boolean;
var
  M : TRdxToken;
begin
  Result := False;
  if AAfter.Low <> '.' then Exit;
  M := After(AMap, AAfter);
  Result := M.IsWord and not InList(M.Low, ITEM_FREE);
end;

// Hinter einem Member AMember: seine Klammer bzw. sein Index uebersprungen
// - das Token danach.
function AfterMember(AMap: TRdxCodeMap; const AMember: TRdxToken): TRdxToken;
begin
  Result := After(AMap, AMember);
  while (Result.Low = '(') or (Result.Low = '[') do
    Result := AfterClose(AMap, Result);
end;

// 'for E in X do' bzw. 'for var E in X do' um das Vorkommen O: True mit
// der Laufvariablen E.
function ForInVar(AMap: TRdxCodeMap; const O: TRdxToken;
  out AVar: TRdxToken): Boolean;
var
  P, K : TRdxToken;
begin
  Result := False;
  AVar := Default(TRdxToken);
  P := Before(AMap, O);
  if (P.Low <> 'in') or (After(AMap, O).Low <> 'do') then Exit;
  AVar := Before(AMap, P);
  if not AVar.IsWord then Exit;
  K := Before(AMap, AVar);
  if K.Low = 'var' then
    K := Before(AMap, K);
  Result := K.Low = 'for';
end;

// Ein Vorkommen von X im Rumpf, das weder Deklaration noch Zuweisung ist:
// '' oder der Grund (s. Kopf der Unit). Eine Laufvariable 'for E in X'
// kommt nach ALoopVars.
function UseReason(AMap: TRdxCodeMap; const O: TRdxToken;
  const AName: string; var ALoopVars: TArray<TRdxToken>): string;
var
  P, N, M, X, LoopVar : TRdxToken;
begin
  Result := '';
  P := Before(AMap, O);
  N := After(AMap, O);
  if N.Low = '.' then
  begin
    M := After(AMap, N);
    if InList(M.Low, LIST_FREE) then
      Exit;
    if InList(M.Low, LIST_ADDERS) then
      Exit(AdderReason(AMap, M));
    if InList(M.Low, LIST_ITEMS) then
    begin
      if ItemUseOk(AMap, AfterMember(AMap, M)) then
        Exit;
      Exit(_(R_OL_ITEM, [O.Line]));
    end;
    if InList(M.Low, LIST_SAFE) then
    begin
      if AfterMember(AMap, M).Low = ':=' then
        Exit(_(R_OL_SETTER, [O.Line, AName]));
      Exit;
    end;
    Exit(_(R_OL_MEMBER, [AName, TokText(AMap, M), O.Line]));
  end;
  if N.Low = '[' then
  begin
    X := AfterClose(AMap, N);
    if X.Low = ':=' then
      Exit(_(R_OL_SETTER, [O.Line, AName]));
    if ItemUseOk(AMap, X) then
      Exit;
    Exit(_(R_OL_ITEM, [O.Line]));
  end;
  if (P.Low = '(') and InList(Before(AMap, P).Low, GUARD_CALLS)
     and (N.Low = ')') then
    Exit;
  if InList(N.Low, NIL_COMPARE) and (After(AMap, N).Low = 'nil') then
    Exit;
  if ForInVar(AMap, O, LoopVar) then
  begin
    AddToken(ALoopVars, LoopVar);
    Exit;
  end;
  Result := _(R_OL_VALUE, [AName, O.Line]);
end;

// Die Laufvariable AVar (aus 'for AVar in X do') im Rumpf der Routine: jedes
// andere Vorkommen steht vor '.' und einem Member, das das Element nicht
// freigibt. '' oder der Grund.
function LoopVarReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AVar: TRdxToken): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  P := R.Body;
  T := After(AMap, P);
  while (T.Low <> '') and TokBefore(T, R.EndTok) do
  begin
    if T.IsWord and SameIdent(T.Low, AVar.Low) and (P.Low <> '.')
       and not SameTok(T, AVar) and not ItemUseOk(AMap, After(AMap, T)) then
      Exit(_(R_OL_LOOP_VAR, [TokText(AMap, AVar), T.Line]));
    P := T;
    T := After(AMap, T);
  end;
  // Vorkommen in einer verschachtelten Routine (Deklarationsteil): nur als
  // Deklaration 'E: TFoo'.
  T := After(AMap, R.HeaderEnd);
  while (T.Low <> '') and TokBefore(T, R.Body) do
  begin
    if T.IsWord and SameIdent(T.Low, AVar.Low)
       and (Before(AMap, T).Low <> '.') and (After(AMap, T).Low <> ':') then
      Exit(_(R_OL_LOOP_VAR, [TokText(AMap, AVar), T.Line]));
    T := After(AMap, T);
  end;
end;

// Steht System.Generics.Collections (oder Generics.Collections) in einer
// uses-Klausel der Datei? 'in ''pfad''' hinter einem Namen zaehlt nicht mit.
function UsesGenerics(AMap: TRdxCodeMap): Boolean;
var
  T, N    : TRdxToken;
  Name    : string;
  InPath  : Boolean;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_USES);
  while T.Low <> '' do
  begin
    if (T.Low = KW_USES) and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      Name := '';
      InPath := False;
      N := After(AMap, T);
      while (N.Low <> '') and (N.Low <> ';') do
      begin
        if N.Low = ',' then
        begin
          if InList(Name, GENERICS_UNITS) then
            Exit(True);
          Name := '';
          InPath := False;
        end
        else if N.Low = 'in' then
          InPath := True
        else if not InPath and ((N.Low = '.') or N.IsWord) then
          Name := Name + N.Low;
        N := After(AMap, N);
      end;
      if InList(Name, GENERICS_UNITS) then
        Exit(True);
    end;
    T := NextTokenOnLineWith(AMap, T, KW_USES);
  end;
end;

// Deklariert die Datei einen Typ ALow ('TList<T> = class', 'TList = ..')?
function DeclaresType(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  T, N : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if (T.Low = ALow) and (Before(AMap, T).Low <> '.') then
    begin
      N := After(AMap, T);
      if N.Low = '<' then
        N := AfterClose(AMap, N);
      if N.Low = '=' then
        Exit(True);
    end;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

// Die Ersetzung 'TList' -> 'TObjectList' am Token T.
function ListEdit(AMap: TRdxCodeMap; const T: TRdxToken): TRdxEdit;
begin
  Result := Default(TRdxEdit);
  Result.Span := TRefactorSpan.Make(SPAN_174, T.Line, T.Col, T.Line, T.EndCol);
  Result.Expected := TokText(AMap, T);
  Result.NewText := NEW_CLASS;
end;

type
  // Was die Durchsicht der Vorkommen findet.
  TListFacts = record
    Decl       : TRdxToken;   // Deklaration (var-Abschnitt oder inline)
    DeclList   : TRdxToken;   // ihr 'TList'; Low = '' bei 'var X := ..'
    Assigns    : Integer;     // Zuweisungen an X
    CreateAt   : TRdxToken;   // das Token hinter dem ':=' der Zuweisung
    CreateLine : Integer;
    Others     : TArray<TRdxToken>;   // alle anderen Vorkommen im Rumpf
  end;

// Die Deklaration (Vorkommen O im Deklarationsteil): var-Abschnitt, allein,
// Typ 'TList<T>;'. '' oder der Grund; die Fakten in AFacts.
function SectionDeclReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const O: TRdxToken; const AName, AType: string;
  var AFacts: TListFacts): string;
var
  N, P, L, A : TRdxToken;
begin
  N := After(AMap, O);
  P := Before(AMap, O);
  if (N.Low <> ':') and (N.Low <> ',') and (P.Low <> ',') then
    Exit(_(R_OL_NESTED, [AName, O.Line]));
  if AFacts.Decl.Low <> '' then
    Exit(_(R_OL_DECLS, [AName]));
  if not InVarSection(AMap, R, O) then
    Exit(_(R_OL_NOT_LOCAL, [AName]));
  if (N.Low = ',') or (P.Low = ',') then
    Exit(_(R_OL_GROUPED, [AName]));
  if not ReadListType(AMap, After(AMap, N), LowerCase(AType), L, A)
     or (A.Low <> ';') then
    Exit(_(R_OL_DECL_TYPE, [AName, O.Line, AType]));
  AFacts.Decl := O;
  AFacts.DeclList := L;
  Result := '';
end;

// Eine inline-Deklaration 'var X ..' (O hinter 'var' im Rumpf): mit Typ
// 'var X: TList<T>[ := ..]' oder ohne 'var X := ..'. '' oder der Grund.
function InlineDeclReason(AMap: TRdxCodeMap; const O: TRdxToken;
  const AName, AType: string; var AFacts: TListFacts): string;
var
  N, L, A : TRdxToken;
begin
  if AFacts.Decl.Low <> '' then
    Exit(_(R_OL_DECLS, [AName]));
  N := After(AMap, O);
  if N.Low = ',' then
    Exit(_(R_OL_GROUPED, [AName]));
  AFacts.Decl := O;
  if N.Low = ':=' then
  begin
    Inc(AFacts.Assigns);
    AFacts.CreateAt := After(AMap, N);
    AFacts.CreateLine := O.Line;
    Exit('');
  end;
  if (N.Low <> ':')
     or not ReadListType(AMap, After(AMap, N), LowerCase(AType), L, A)
     or ((A.Low <> ';') and (A.Low <> ':=')) then
    Exit(_(R_OL_DECL_TYPE, [AName, O.Line, AType]));
  AFacts.DeclList := L;
  if A.Low = ':=' then
  begin
    Inc(AFacts.Assigns);
    AFacts.CreateAt := After(AMap, A);
    AFacts.CreateLine := O.Line;
  end;
  Result := '';
end;

// Die Vorkommen der Variablen ordnen: Parameter, Deklarationsteil, Rumpf
// (inline-Deklaration, Zuweisung, sonst Nutzung). '' oder der Grund.
function FactsReason(AMap: TRdxCodeMap; const R: TRdxRoutine;
  const AName, AType: string; out AFacts: TListFacts): string;
var
  O, P : TRdxToken;
begin
  AFacts := Default(TListFacts);
  Result := '';
  for O in Occurrences(AMap, R, LowerCase(AName)) do
  begin
    if not TokBefore(R.HeaderEnd, O) then
      Result := _(R_OL_PARAM, [AName])
    else if TokBefore(O, R.Body) then
      Result := SectionDeclReason(AMap, R, O, AName, AType, AFacts)
    else
    begin
      P := Before(AMap, O);
      if (P.Low = 'var') and IsKeywordAfter(P, Before(AMap, P)) then
        Result := InlineDeclReason(AMap, O, AName, AType, AFacts)
      else if After(AMap, O).Low = ':=' then
      begin
        Inc(AFacts.Assigns);
        AFacts.CreateAt := After(AMap, After(AMap, O));
        AFacts.CreateLine := O.Line;
      end
      else
        AddToken(AFacts.Others, O);
    end;
    if Result <> '' then
      Exit;
  end;
  if AFacts.Decl.Low = '' then
    Exit(_(R_OL_NOT_LOCAL, [AName]));
  if AFacts.Assigns <> 1 then
    Exit(_(R_OL_ASSIGNS, [AName, AFacts.Assigns, AType]));
end;

{ TRdxObjectListFix }

class function TRdxObjectListFix.OwnItems(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out APlan: TRdxObjectListPlan;
  out AReason: string): Boolean;
var
  AType, VarLow, Name : string;
  AddTok, CreateList  : TRdxToken;
  R                   : TRdxRoutine;
  Facts               : TListFacts;
  LoopVars            : TArray<TRdxToken>;
  O                   : TRdxToken;
begin
  APlan := Default(TRdxObjectListPlan);
  R := Default(TRdxRoutine);
  Facts := Default(TListFacts);
  LoopVars := nil;
  Result := False;
  AType := ListTypeArgOf(AMessage);
  VarLow := LowerCase(ListVarOf(AMessage));
  APlan.Name := AType;
  if (AType = '') or (VarLow = '') then
  begin
    AReason := _(R_OL_NO_MESSAGE);
    Exit;
  end;
  AddTok := AddOnLine(AMap, ALine, VarLow);
  if AddTok.Low = '' then
  begin
    AReason := MsgMovedSuffix(_(R_OL_NO_ADD, [VarLow]));
    Exit;
  end;
  // Der Name wie im Quelltext geschrieben (die Meldung schreibt ihn klein).
  Name := TokText(AMap, AddTok);
  AReason := EnclosingRoutine(AMap, AddTok, R);
  if AReason <> '' then Exit;
  if DirectiveBetween(AMap, R.Head, R.EndTok.Line, R.EndTok.Col) then
    AReason := _(R_OL_DIRECTIVE)
  else if HasWith(AMap, R) then
    AReason := _(R_OL_WITH)
  else
    AReason := FactsReason(AMap, R, Name, AType, Facts);
  if (AReason = '')
     and not ReadCreate(AMap, Facts.CreateAt, LowerCase(AType), CreateList) then
    AReason := _(R_OL_CREATE, [Name, Facts.CreateLine, AType]);
  if AReason <> '' then Exit;
  for O in Facts.Others do
  begin
    AReason := UseReason(AMap, O, Name, LoopVars);
    if AReason <> '' then Exit;
  end;
  for O in LoopVars do
  begin
    AReason := LoopVarReason(AMap, R, O);
    if AReason <> '' then Exit;
  end;
  if not UsesGenerics(AMap) then
    AReason := _(R_OL_USES)
  else if DeclaresType(AMap, KW_TLIST) then
    AReason := _(R_OL_OWN_TYPE, ['TList'])
  else if DeclaresType(AMap, KW_TOBJECTLIST) then
    AReason := _(R_OL_OWN_TYPE, [NEW_CLASS]);
  if AReason <> '' then Exit;
  if Facts.DeclList.Low <> '' then
    AddEdit(APlan.Edits, ListEdit(AMap, Facts.DeclList));
  AddEdit(APlan.Edits, ListEdit(AMap, CreateList));
  Result := True;
end;

end.
