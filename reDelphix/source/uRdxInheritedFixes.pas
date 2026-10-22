unit uRdxInheritedFixes;

// reDelphix - Quick-Fixes "Konstruktoren und Destruktoren", OHNE ToolsAPI
// und ohne Parser (Konzept_Editorhilfen_Recherche_2026-10-11, Abschnitt 5
// Baustein "Routinengrenzen", Abschnitt 6 Charge H5). Bis Review Woche
// G08-04 standen die Planer in uRdxResultFixes ("Ergebnis und
// Konstruktoren"); mit SCA121/SCA196 teilen sie dort die Bausteine
// FirstStatement/LastStatement, den Planerlauf TRdxScan
// (Typdeklarationen, Klassenkoepfe, Methodendeklarationen und
// Konstruktornamen aus EINEM Lauf je Planeraufruf, Gegen-Review R5-07),
// die Deklaration einer Methode (DeclOf) und die Nachweise an Kopf und
// Rumpf (RoutineOnLine, BodyReason). Hier steht, was nur die Vererbung
// fragt: die Klasse und ihr erster Vorfahr (TRdxOwner), override,
// abstrakte Vorfahren, Delegation und das Ende des Destruktors.
//
//   SCA096 ConstructorWithoutInherited: als erste Anweisung des Rumpfs
//          (a) 'inherited Create;', wenn 'inherited Create' in dieser Unit
//              belegt TObject.Create ruft: die Klasse erbt DIREKT von
//              TObject ('class', 'class(TObject)', als erster Eintrag ein
//              unqualifiziertes Interface der Unit auf Unit-Ebene) oder
//              von einem Vorfahren ohne eigenen Konstruktor (NO_CTOR_PARENTS:
//              TPersistent, TInterfacedObject, TCustomAttribute - in den
//              Delphi-Quellen nachgesehen, s. dort). TObject.Create ist
//              leer, gleiche Bedeutung. Nie nacktes 'inherited;': es
//              reichte die eigenen Parameter weiter, und TObject hat keinen
//              Konstruktor mit Parametern;
//          (b) 'inherited;', wenn die Deklaration 'override' traegt -
//              Delphi uebersetzt es gegen den ueberschriebenen Konstruktor
//              mit denselben Parametern; gekennzeichnet (E2): der
//              Elternkonstruktor laeuft danach.
//          Ein Eintrag je Fund; die Variante waehlt der Planer (wie SCA149
//          override/reintroduce in uRdxDeclFixes). Erbt die Klasse von
//          etwas anderem und fehlt 'override', ist die Wahl des
//          Elternkonstruktors Entwurf - keine Hilfe.
//   SCA097 DestructorWithoutInherited: 'inherited;' als letzte Anweisung
//          vor dem end des Rumpfs (fehlt der letzten Anweisung das ';',
//          kommt es hinter ihr letztes Zeichen - auch hinter ein
//          String-Literal). Nur mit 'override' an der Deklaration (sonst
//          verdeckt Destroy die virtuelle Methode - eigentlich SCA149).
//          Gekennzeichnet, ausser die Klasse erbt direkt von TObject
//          (TObject.Destroy ist leer; TPersistent.Destroy nicht).
//
// SPERREN wie bei SCA121/SCA196 (uRdxResultFixes): kein begin-Rumpf
// (forward/external, asm-Rumpf), asm irgendwo im Rumpf, eine
// Compiler-Direktive zwischen Kopf und begin, zwei Koepfe auf der
// gemeldeten Zeile. Dazu fuer beide: 'class
// constructor/destructor', Kopf ohne Klasse, 'inherited' irgendwo im Text
// der Routine (inaktiver Zweig, Kommentar, String-Literal, lokale Routine -
// der Detektor sieht nur den aktiven AST; ein String sperrt mit, die
// Zeile wird roh gelesen), Klasse nicht (eindeutig) in der Unit,
// object-Typ, Record, class helper, eine Direktive in der Vorfahrenliste
// (der Vorfahr haengt an einem Zweig), eine geerbte Methode, die in der
// Unit 'abstract' ist, und unter {$mode objfpc}/{$mode fpc} ein Vorfahr
// ausserhalb der Unit (FPC lehnt 'inherited' auf eine abstrakte Methode
// ab, das ist dann nicht beweisbar). SCA096 (b) dazu ein Aufruf eines
// eigenen Konstruktors (Delegation, auch ohne 'Create' im Namen). SCA097
// dazu: letzte Anweisung Exit/raise/Halt/Abort/goto (auch 'System.Exit',
// 'System.Halt', 'SysUtils.Abort'), Exit (auch 'System.Exit') oder goto auf
// jeder Tiefe (inherited am Ende liefe dort nie) und eine Direktive
// zwischen letzter Anweisung und end.
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxCodeMap,
  uRdxResultFixes;   // TRdxResultPlan (Form der Planer: uRdxFixTable ResultForm)

const
  // SCA096/SCA097: die Anweisungen (ohne ';'), zugleich Name im Menuetext.
  STMT_INHERITED_CREATE = 'inherited Create';
  STMT_INHERITED        = 'inherited';

type
  // Die Planer SCA096/SCA097 der Charge H5 (s. Kopf): auf dem Puffertext
  // ueber die Code-Sicht, ohne ToolsAPI und Parser (laeuft auch im
  // FPC-Pruefstand). Ergebnis und Form wie bei SCA121/SCA196
  // (TRdxResultPlan, TRdxResultPlanner in uRdxResultFixes).
  TRdxInheritedFixes = class
  public
    // SCA096: der Konstruktor mit Kopf auf ALine (Meldung 'Constructor has
    // no `inherited` call ...') - 'inherited Create;' bzw. 'inherited;'.
    class function ConstructorInherited(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;

    // SCA097: der Destruktor mit Kopf auf ALine (Meldung 'Destructor has
    // no `inherited` call ...') - 'inherited;' am Ende.
    class function DestructorInherited(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxResultPlan;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRdxBufferMath,    // TRdxEdit
  uRdxBlocks,        // TRdxRoutine, HeritageOf, MethodDecl, HasDirective
  uRdxText;          // _() und die gemeinsamen Texte (MsgByHand ...), E29

const
  KW_CLASS    = 'class';
  KW_END      = 'end';
  KW_OVERRIDE = 'override';
  KW_OVERLOAD = 'overload';
  KW_CONSTRUCTOR = 'constructor';
  KW_DESTRUCTOR  = 'destructor';
  KW_SELF     = 'self';
  WORD_INHERITED = 'inherited';
  // SCA096 (b): so beginnt der Name eines Konstruktors, an den der Rumpf
  // delegiert (DelegationReason).
  CREATE_PREFIX = 'create';
  // SCA096 (b): ein Aufruf, der abbricht (BlockedReason).
  RAISE_PREFIX = 'raise';
  KEY_CTOR    = 'Constructor has no `inherited` call';
  KEY_DTOR    = 'Destructor has no `inherited` call';
  // Damit endet der Ablauf: ein inherited dahinter liefe nie (SCA097).
  DEAD_END_WORDS: array[0..4] of string = ('exit', 'raise', 'halt', 'abort',
    'goto');
  // ... auch qualifiziert, mit der Unit der RTL davor (Gegen-Review R5,
  // R5-05: die letzte Anweisung begann mit 'system' bzw. 'sysutils', und
  // ein totes 'inherited;' kam dahinter). Ein anderer Empfaenger
  // ('FConn.Abort') ist eine Methode, kein Ende.
  DEAD_END_PATHS: array[0..3] of string = ('system.exit', 'system.halt',
    'sysutils.abort', 'system.sysutils.abort');
  // SCA097: damit verlaesst der Ablauf den Destruktor vor dem Ende - auf
  // jeder Tiefe (LeavesDestructorReason; Gegen-Review H5, Minor 2).
  // raise/Halt/Abort mitten im Rumpf sind Fehlerpfade; dort fehlt
  // inherited ohnehin.
  JUMP_WORDS: array[0..1] of string = ('exit', 'goto');
  KW_ABSTRACT = 'abstract';
  // So weit folgen die Planer der Vorfahrenkette in der Unit (OwnConstructor,
  // AbstractReason) - eine Grenze gegen Zyklen in kaputtem Code.
  MAX_CHAIN = 16;
  // FPC-Modi, in denen 'inherited' auf eine abstrakte Methode nicht
  // uebersetzt ("Abstract methods cannot be called directly", FPC 3.2.2;
  // der Delphi-Modus laesst den Aufruf still weg - Gegen-Review H5, Minor 1).
  ABSTRACT_FATAL_MODES: array[0..1] of string = ('objfpc', 'fpc');
  // SCA096 (a): der erste Eintrag der Vorfahrenliste, klein und mit
  // Qualifizierung - TObject selbst ...
  ROOT_PARENTS: array[0..1] of string = ('tobject', 'system.tobject');
  // ... und Vorfahren OHNE eigenen Konstruktor: 'inherited Create' ruft dort
  // TObject.Create (leer) - gleiche Bedeutung wie bei TObject. Nachgesehen
  // (Charge H5c) in den Delphi-Quellen 23.0 und 37.0: System.Classes.pas
  // TPersistent (Zeile 449-460 in beiden: nur 'destructor Destroy;
  // override'), System.pas TInterfacedObject (23.0 Zeile 1058-1079, 37.0
  // Zeile 1056-1077: AfterConstruction, BeforeDestruction, NewInstance -
  // kein constructor) und TCustomAttribute (23.0 Zeile 749, 37.0 Zeile 747:
  // leerer Rumpf); FPC 3.2.2 ebenso (classesh.inc TPersistent, objpash.inc
  // TInterfacedObject - je nur 'destructor destroy; override'). Eine feste
  // Liste, NICHT generiert: ein neuer Eintrag braucht denselben Nachweis in
  // beiden Versionen. Gilt nur, wenn die Unit den Namen nicht selbst
  // deklariert (DeclaresTypeName).
  NO_CTOR_PARENTS: array[0..6] of string = ('tpersistent',
    'classes.tpersistent', 'system.classes.tpersistent', 'tinterfacedobject',
    'system.tinterfacedobject', 'tcustomattribute', 'system.tcustomattribute');
  // SCA096 (b): Woerter in Anweisungsstellung, die nie ein Konstruktor sind
  // - die Delegations-Suche (OwnConstructor) fragt sie nicht erst ab.
  STATEMENT_WORDS: array[0..12] of string = ('if', 'while', 'for', 'case',
    'with', 'repeat', 'try', 'begin', 'raise', 'inherited', 'exit', 'goto',
    'asm');
  // Damit endet ein Aufruf als ganze Anweisung ('Init;', 'Make(A) end').
  CALL_ENDS: array[0..6] of string = ('(', ';', 'end', 'else', 'until',
    'finally', 'except');
  OBJECT_KINDS: array[0..0] of string = ('object');
  RECORD_KINDS: array[0..0] of string = ('record');
  // Gruende als englische msgids (Entscheid E29), uebersetzt an der
  // Verwendung mit _() - mit den Planern aus uRdxResultFixes abgespalten
  // (Folgewelle A3), die Umstellung der Charge C (G2) zog mit. Das
  // gemeinsame Ende ('Zeile verschoben? ...', 'von Hand') kommt aus
  // uRdxText (MsgMovedSuffix, MsgByHand).
  // CtorVariantReason: dieselbe msgid wie R_NO_DECL in uRdxResultFixes
  // (DeclOf) - ein Satz, zwei Stellen.
  R_NO_DECL = 'no declaration of %s in the body of class %s';

type
  // Die Klasse einer Methode (OwnerOf).
  //   Parent          erster Vorfahr wie im Text (letztes Glied); 'TObject'
  //                   ohne Liste
  //   DirectTObject   erbt direkt von TObject (SCA097: TObject.Destroy ist
  //                   leer)
  //   CreateOfTObject 'inherited Create' ruft TObject.Create: direkter
  //                   TObject-Erbe oder ein Vorfahr aus NO_CTOR_PARENTS
  //                   (SCA096 (a))
  TRdxOwner = record
    ClassTok        : TRdxToken;   // 'class' des Klassenkopfs
    Parent          : string;
    DirectTObject   : Boolean;
    CreateOfTObject : Boolean;
  end;

  // SCA096/SCA097: der Konstruktor bzw. Destruktor, seine Klasse und der
  // Planerlauf (MethodCtxReason legt ihn an). Bis Charge H5c hiessen die
  // Felder R und O (Gegen-Review H5, Minor 7).
  TRdxMethodCtx = record
    Routine : TRdxRoutine;
    Owner   : TRdxOwner;
    Scan    : TRdxScan;
  end;

// Die Zeile der ersten Direktive '{$AWord ...}' der Datei, deren Text
// dahinter (klein, ohne Leerraum am Rand) in AArgs steht - bei leerem AArgs
// jede; 0 ohne. '{$mode objfpc}' -> AWord 'mode', AArgs ['objfpc'].
// Der Lauf ueber alle Direktiven: NextDirective (uRdxCodeMap; bis zur
// Folgewelle des Wochen-Reviews, G08-01, hier ausgeschrieben).
function DirectiveLine(AMap: TRdxCodeMap; const AWord: string;
  const AArgs: array of string): Integer;
var
  Li, Co : Integer;
  Arg    : Boolean;
begin
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co) do
  begin
    if (DirectiveWord(AMap, Li, Co, Arg) = AWord)
       and ((Length(AArgs) = 0)
            or InList(LowerCase(Trim(DirectiveArgs(AMap, Li, Co))), AArgs)) then
      Exit(Li);
    Inc(Co);
  end;
  Result := 0;
end;

{ ---- Klasse und Vorfahr (SCA096/SCA097) ---- }

// SCA096/SCA097: ein Methodenkopf 'TKlasse.Name' ohne 'class' davor? ''
// oder der Grund.
function MethodHeadReason(const R: TRdxRoutine): string;
begin
  Result := '';
  if R.Head.Low = KW_CLASS then
    Result := _('class %s - without an inheritance chain, inherited does '
      + 'not belong there', [R.Keyword.Low])
  else if Length(R.Parts) < 2 then
    Result := _('%s without a class (no TClass.Name) - %s',
      [R.Keyword.Low, MsgByHand]);
end;

// Steht 'inherited' irgendwo im Text der Routine - auch in einem
// Kommentar, einem inaktiven $IFDEF-Zweig oder einer lokalen Routine? Dann
// hat ihn jemand gesetzt, verschoben oder auskommentiert, und der Detektor
// sah ihn nur nicht im AST. Gelesen wird die rohe Zeile, ein String-Literal
// ('Log(''inherited skipped'')') sperrt also mit - lieber eine Sperre zu
// viel; der Grund nennt es (Review Woche G08-05). '' oder der Grund.
function InheritedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  Li : Integer;
begin
  Result := '';
  for Li := R.Head.Line to R.Last.Line do
    if HasIdentWord(LowerCase(AMap.Raw(Li)), WORD_INHERITED) then
      Exit(_('"inherited" already appears in line %d (inactive branch, '
        + 'comment, string literal or local routine) - %s',
        [Li, MsgByHand]));
end;

// Der erste Eintrag der Vorfahrenliste hinter AClass (Token 'class') wie im
// Text, Glieder mit '.', ohne Typargumente ('class(System.Classes.
// TPersistent, IFoo)' -> 'System.Classes.TPersistent'); '' ohne Liste.
// AOpen/AClose: die Klammern der Liste (Low = '' ohne). HeritageOf liefert
// nur letzte Glieder - hier entscheidet die Qualifizierung mit
// ('class(Other.IFoo)' ist kein Interface DIESER Unit; Gegen-Review H5,
// Minor 3).
function FirstHeritage(AMap: TRdxCodeMap; const AClass: TRdxToken;
  out AOpen, AClose: TRdxToken): string;
var
  T  : TRdxToken;
  SB : TStringBuilder;
begin
  Result := '';
  AClose := Default(TRdxToken);
  AOpen := After(AMap, AClass);
  while InList(AOpen.Low, CLASS_MODIFIERS) do
    AOpen := After(AMap, AOpen);
  if AOpen.Low <> '(' then
  begin
    AOpen := Default(TRdxToken);
    Exit;
  end;
  AClose := MatchClose(AMap, AOpen);
  if AClose.Low = '' then Exit;
  SB := TStringBuilder.Create;
  try
    T := After(AMap, AOpen);
    while not SameTok(T, AClose) and (T.Low <> ',') and (T.Low <> '') do
    begin
      if T.Low = '<' then
        T := MatchClose(AMap, T)
      else if T.IsWord or (T.Low = '.') then
        SB.Append(TokText(AMap, T));
      if T.Low <> '' then
        T := After(AMap, T);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Der erste Vorfahr der Klasse mit dem Kopf AClass in AOwner (Parent,
// DirectTObject, CreateOfTObject). '' oder der Grund: eine Direktive
// zwischen '=' und dem Ende der Vorfahrenliste -
// 'class({$IFDEF FPC}TPersistent{$ELSE}TObject{$ENDIF})' las die Code-Sicht
// als TObject, 'class{$IFDEF X}(TComponent){$ENDIF}' haengt den Vorfahren
// an einen Zweig (Gegen-Review H5, Minor 3).
function ParentReason(var AScan: TRdxScan; const AClass: TRdxToken;
  var AOwner: TRdxOwner): string;
var
  First, Low  : string;
  Open, Close : TRdxToken;
  Stop        : TRdxToken;
begin
  First := FirstHeritage(AScan.Map, AClass, Open, Close);
  if (Open.Low <> '') and (Close.Low = '') then
    Exit(_('ancestor list without ")" (line %d) - %s',
      [AClass.Line, MsgByHand]));
  Stop := AClass;
  if Close.Low <> '' then
    Stop := Close;
  if DirectiveBetween(AScan.Map, Before(AScan.Map, AClass), Stop.Line,
       Stop.Col) then
    Exit(_('compiler directive in the ancestor list (line %d) - the '
      + 'ancestor depends on a branch; %s', [AClass.Line, MsgByHand]));
  Low := LowerCase(First);
  AOwner.Parent := 'TObject';
  if First <> '' then
    AOwner.Parent := LastPart(First);
  // 'class(IFoo)': der erste Eintrag ist ein Interface - Vorfahr TObject.
  // Nur ein unqualifiziertes Interface DIESER Unit auf Unit-Ebene beweist
  // das (UnitInterface); ein fremdes 'IFoo' bzw. 'Other.IFoo' kann eine
  // Klasse sein.
  AOwner.DirectTObject := (First = '') or InList(Low, ROOT_PARENTS)
    or ((Pos('.', First) = 0) and UnitInterface(AScan, Low));
  AOwner.CreateOfTObject := AOwner.DirectTObject
    or (InList(Low, NO_CTOR_PARENTS)
        and not DeclaresTypeName(AScan, LowerCase(AOwner.Parent)));
  Result := '';
end;

// Die Klasse AClassPath in der Unit: genau ein Kopf mit Rumpf, kein class
// helper; ihr erster Vorfahr (ParentReason). '' oder der Grund.
function OwnerOf(var AScan: TRdxScan; const AClassPath: string;
  out AOwner: TRdxOwner): string;
var
  Heads : TArray<TRdxToken>;
  Low   : string;
begin
  AOwner := Default(TRdxOwner);
  Low := LowerCase(LastPart(AClassPath));
  Heads := ClassHeads(AScan, AClassPath);
  if Length(Heads) = 0 then
  begin
    if DeclaredAs(AScan, Low, OBJECT_KINDS) then
      Exit(_('object type (old object model) - %s', [MsgByHand]));
    if DeclaredAs(AScan, Low, RECORD_KINDS) then
      Exit(_('record - no inheritance'));
    Exit(_('class %s not in this unit - the ancestor cannot be proven',
      [AClassPath]));
  end;
  if Length(Heads) > 1 then
    Exit(_('%d classes named %s in the unit - ambiguous',
      [Length(Heads), LastPart(AClassPath)]));
  AOwner.ClassTok := Heads[0];
  if After(AScan.Map, Heads[0]).Low = 'helper' then
    Exit(_('class helper - inherited means the extended class there'));
  Result := ParentReason(AScan, Heads[0], AOwner);
end;

{ ---- override, abstrakte Vorfahren, Delegation ---- }

// SCA096 (b): die Deklaration traegt override (ohne overload). '' oder der
// Grund.
function CtorOverrideReason(var AScan: TRdxScan; const R: TRdxRoutine;
  const AOwner: TRdxOwner): string;
var
  D : TRdxRoutine;
  W : string;
begin
  Result := DeclOf(AScan, R, D);
  if Result <> '' then Exit;
  if not HasDirective(D, [KW_OVERRIDE], W) then
    Exit(_('parent class %s and no override declaration - which parent '
      + 'constructor should run with which arguments is a design decision; '
      + '%s', [AOwner.Parent, MsgByHand]));
  if HasDirective(D, [KW_OVERLOAD], W) then
    Exit(_('override with overload - which inherited constructor is meant '
      + 'is not certain; %s', [MsgByHand]));
end;

// SCA096 (b): bricht die erste Anweisung den Konstruktor ab - 'raise',
// 'Assert(False..)', ein Aufruf 'Raise..' ('EFoo.RaiseUtf8(..)',
// 'RaiseLastOSError')? Ein blockierter Konstruktor (Korpus: 'Assert(False);
// // Call constructor CreateWithManager') erzeugt nie ein Objekt; der
// Detektor kennt nur 'raise'. Der Elternkonstruktor davor liefe vergeblich
// und mit seinen Nebenwirkungen. '' oder der Grund.
function BlockedReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T       : TRdxToken;
  Blocked : Boolean;
begin
  Result := '';
  T := After(AMap, R.Body);
  Blocked := (T.Low = 'raise')
    or ((T.Low = 'assert') and (After(AMap, T).Low = '(')
        and (After(AMap, After(AMap, T)).Low = 'false'));
  while not Blocked and (T.Low <> '') and not SameTok(T, R.EndTok)
    and not InList(T.Low, [';', '(']) do
  begin
    // Ein Ziel einer Zuweisung ('RaiseOnError := ..') ist kein Aufruf - bis
    // Review Woche G08-06 hiess es "blockierter Konstruktor".
    Blocked := T.IsWord and (Copy(T.Low, 1, Length(RAISE_PREFIX)) = RAISE_PREFIX)
      and (After(AMap, T).Low <> ':=');
    if not Blocked then
      T := After(AMap, T);
  end;
  if Blocked then
    Result := _('the constructor aborts with its first statement (line %d, '
      + 'blocked constructor) - inherited before it would run in vain; %s',
      [After(AMap, R.Body).Line, MsgByHand]);
end;

// SCA096 (b): ist ALowName ein Konstruktor der Klasse AClassPath oder eines
// ihrer Vorfahren in dieser Unit (MethodDecls je Glied der Kette,
// hoechstens MAX_CHAIN)? 'class constructor' zaehlt nicht - ihn ruft keine
// Anweisung. Steht der Name nirgends hinter 'constructor' (IsCtorName),
// braucht es die Kette nicht.
function OwnConstructor(var AScan: TRdxScan; const AClassPath,
  ALowName: string): Boolean;
var
  Cls   : string;
  H     : TRdxToken;
  Heads : TArray<TRdxToken>;
  Names : TArray<string>;
  Step  : Integer;
begin
  Result := False;
  if not IsCtorName(AScan, ALowName) then Exit;
  Cls := AClassPath;
  for Step := 1 to MAX_CHAIN do
  begin
    for H in MethodDecls(AScan, Cls, ALowName) do
      if H.Low = KW_CONSTRUCTOR then
        Exit(True);
    Heads := ClassHeads(AScan, Cls);
    if Length(Heads) <> 1 then Exit;
    Names := TRdxBlocks.HeritageOf(AScan.Map, Heads[0]);
    if Length(Names) = 0 then Exit;
    Cls := Names[0];
  end;
end;

// SCA096 (b): koennte das Wort T in Anweisungsstellung ein Aufruf eines
// eigenen Konstruktors sein - ein ganzer Aufruf ('Init;', 'OpenOptions(..)',
// CALL_ENDS dahinter), kein Schluesselwort einer Anweisung? Nur dann fragt
// DelegationAt nach einem Konstruktor dieses Namens (OwnConstructor: erst
// die Namen hinter 'constructor' aus dem Index, dann je Glied der
// Vorfahrenkette die gemerkten Methodendeklarationen).
function CallCandidate(AMap: TRdxCodeMap; const T: TRdxToken): Boolean;
begin
  Result := T.IsWord and not InList(T.Low, STATEMENT_WORDS)
    and InList(After(AMap, T).Low, CALL_ENDS);
end;

// SCA096 (b): der Grund fuer eine Delegation am Wort T in Anweisungsstellung
// (s. DelegationReason), '' ohne. ASeen: die Namen, deren Deklarationen
// schon abgefragt sind.
function DelegationAt(var AScan: TRdxScan; const R: TRdxRoutine;
  const T: TRdxToken; var ASeen: TArray<string>): string;
begin
  Result := '';
  // Ein Ziel einer Zuweisung ('Created := True', 'CreateDate := Now') ist
  // kein Aufruf - bis Review Woche G08-06 hiess es "Delegation".
  if After(AScan.Map, T).Low = ':=' then Exit;
  if Copy(T.Low, 1, Length(CREATE_PREFIX)) = CREATE_PREFIX then
    Exit(_('call %s in line %d - maybe another constructor of the class '
      + '(delegation) that already initializes the parent class; inherited '
      + 'before it would run twice; %s',
      [TokText(AScan.Map, T), T.Line, MsgByHand]));
  if not CallCandidate(AScan.Map, T) or InList(T.Low, ASeen) then Exit;
  if OwnConstructor(AScan, OwnerPathOf(R.Name), T.Low) then
    Exit(_('call %s in line %d - a constructor of the class (delegation) '
      + 'that already initializes the parent class; inherited before it '
      + 'would run twice; %s', [TokText(AScan.Map, T), T.Line, MsgByHand]));
  SetLength(ASeen, Length(ASeen) + 1);
  ASeen[High(ASeen)] := T.Low;
end;

// SCA096 (b): ruft der Rumpf als Anweisung einen Konstruktor der Klasse
// selbst - 'CreateNew(AOwner);', 'Self.CreateEx(..)', 'OpenOptions(..)'?
// Das ist eine Delegation, die der Detektor nur fuer 'Create(' kennt; der
// gerufene Konstruktor initialisiert die Elternklasse schon
// (TCustomForm.CreateNew laedt danach keine .dfm - 'inherited;' davor
// taete es und scheiterte). Erkannt am Namen 'Create..' in
// Anweisungsstellung - eine Routine wie 'CreateDir(..)' sperrt mit (lieber
// keine Hilfe) - oder an einer constructor-Deklaration des Namens in der
// Klasse bzw. ihren Vorfahren der Unit (OwnConstructor; Gegen-Review H5,
// Major 1: mORMot THttpClientSocket.OpenFrom ruft OpenOptions, der selbst
// Create und OpenBind ruft - 'inherited;' davor oeffnete zuerst ueber
// TCrtSocket.OpenFrom eine zweite Verbindung). '' oder der Grund.
function DelegationReason(var AScan: TRdxScan; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
  Seen : TArray<string>;
begin
  Result := '';
  Seen := nil;
  P := R.Body;
  T := After(AScan.Map, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if T.IsWord and (InList(P.Low, STATEMENT_PREV)
                     or ((P.Low = '.')
                         and (Before(AScan.Map, P).Low = KW_SELF))) then
      Result := DelegationAt(AScan, R, T, Seen);
    if Result <> '' then Exit;
    P := T;
    T := After(AScan.Map, T);
  end;
end;

// SCA097: die Deklaration traegt override. '' oder der Grund.
function DtorOverrideReason(var AScan: TRdxScan; const R: TRdxRoutine): string;
var
  D : TRdxRoutine;
  W : string;
begin
  Result := DeclOf(AScan, R, D);
  if (Result = '') and not HasDirective(D, [KW_OVERRIDE], W) then
    Result := _('the declaration carries no override - then the destructor '
      + 'hides the virtual method (SCA149); %s', [MsgByHand]);
end;

// SCA096 (b), SCA097: die Deklarationen von AMethod in der Klasse ACls der
// Unit (ohne 'class constructor/destructor'). AFound, wenn es welche gibt;
// '' oder der Grund, wenn eine 'abstract' traegt oder nicht zu lesen ist.
function AbstractDeclReason(var AScan: TRdxScan; const ACls, AMethod: string;
  out AFound: Boolean): string;
var
  H : TRdxToken;
  D : TRdxRoutine;
  W : string;
begin
  Result := '';
  AFound := False;
  for H in MethodDecls(AScan, ACls, AMethod) do
  begin
    if H.Low = KW_CLASS then Continue;
    AFound := True;
    if TRdxBlocks.MethodDecl(AScan.Map, H, D) <> '' then
      Exit(_('the declaration of %s.%s in line %d cannot be read - whether '
        + 'it is abstract remains open; %s',
        [ACls, AMethod, H.Line, MsgByHand]));
    if HasDirective(D, [KW_ABSTRACT], W) then
      Exit(_('%s.%s is abstract (line %d) - inherited calls nothing there or '
        + 'does not compile under FPC objfpc; %s',
        [ACls, AMethod, H.Line, MsgByHand]));
  end;
end;

// SCA096 (b), SCA097: ist die Methode, die 'inherited;' ruft, abstrakt? Die
// Kette der Vorfahren in der Unit hinauf bis zur ersten Klasse, die die
// Methode deklariert: abstrakt -> sperren (FPC objfpc: "Abstract methods
// cannot be called directly", Delphi-Modus laesst den Aufruf still weg -
// beides keine Hilfe; Gegen-Review H5, Minor 1). Endet die Kette vorher
// ausserhalb der Unit, ist das unter {$mode objfpc}/{$mode fpc} nicht
// beweisbar -> sperren; in Delphi bleibt es beim Angebot. TObject (Create,
// Destroy) ist nie abstrakt. '' oder der Grund.
function AbstractReason(var ACtx: TRdxMethodCtx): string;
var
  Cls, Method : string;
  Heads       : TArray<TRdxToken>;
  O           : TRdxOwner;
  Found       : Boolean;
  Step, Mode  : Integer;
begin
  Result := '';
  O := ACtx.Owner;
  Cls := O.Parent;
  Method := LastPart(ACtx.Routine.Name);
  for Step := 1 to MAX_CHAIN do
  begin
    if O.DirectTObject then Exit;
    Cls := O.Parent;
    Heads := ClassHeads(ACtx.Scan, Cls);
    if Length(Heads) <> 1 then Break;
    Result := AbstractDeclReason(ACtx.Scan, Cls, Method, Found);
    if (Result <> '') or Found then Exit;
    O := Default(TRdxOwner);
    if ParentReason(ACtx.Scan, Heads[0], O) <> '' then Break;
  end;
  Mode := DirectiveLine(ACtx.Scan.Map, 'mode', ABSTRACT_FATAL_MODES);
  if Mode > 0 then
    Result := _('{$mode objfpc/fpc} in line %d, and from %s on the '
      + 'inherited method is not visible in this unit - if it is abstract, '
      + 'FPC does not compile the inherited; not provable, %s',
      [Mode, Cls, MsgByHand]);
end;

{ ---- Das Ende des Destruktors (SCA097) ---- }

// SCA097: das erste Token der letzten Anweisung auf oberster Ebene des
// Rumpfs (hinter dem letzten ';' der Tiefe 0); Low = '' im leeren Rumpf.
function LastStatementStart(AMap: TRdxCodeMap; const R: TRdxRoutine): TRdxToken;
var
  T, P, N : TRdxToken;
  Depth   : Integer;
begin
  Result := Default(TRdxToken);
  Depth := 0;
  P := R.Body;
  T := After(AMap, R.Body);
  if not SameTok(T, R.EndTok) then
    Result := T;
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if IsKeywordAfter(T, P) and IsEndOpener(T.Low) then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and (T.Low = KW_END) then
      Dec(Depth)
    else if (Depth = 0) and (T.Low = ';') then
    begin
      N := After(AMap, T);
      if not SameTok(N, R.EndTok) then
        Result := N;
    end;
    P := T;
    T := After(AMap, T);
  end;
end;

// SCA097: steht Exit (auch 'System.Exit') oder goto irgendwo im Rumpf - auf
// jeder Tiefe, auch in einer anonymen Methode (lieber keine Hilfe)? Lokale
// Routinen stehen vor dem begin und zaehlen nicht. Dann verlaesst der
// Ablauf den Destruktor dort vor dem Ende, und ein inherited am Ende liefe
// auf diesem Weg nie (Gegen-Review H5, Minor 2: Abbrevia TMultiTree.Destroy
// endet mit 'Curr.Free; exit;' in einer Schleife). '' oder der Grund. Bis
// zur Nachpruefung B2S hiess sie JumpReason wie zwei andere Routinen mit
// anderem Vertrag (uRdxFlowFixes.RedundantJumpReason fuer SCA080,
// uRdxTrySpan.SpanJumpReason fuer den try-Bereich; Review R3-05/R5-03).
function LeavesDestructorReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  T, P : TRdxToken;
begin
  Result := '';
  P := R.Body;
  T := After(AMap, R.Body);
  while (T.Low <> '') and not SameTok(T, R.EndTok) do
  begin
    if IsExitAt(AMap, T, P)
       or (InList(T.Low, JUMP_WORDS) and IsKeywordAfter(T, P)) then
      Exit(_('%s in line %d - the control flow leaves the destructor there '
        + 'before the end, an inherited at the end would never run on this '
        + 'path; %s', [TokText(AMap, T), T.Line, MsgByHand]));
    P := T;
    T := After(AMap, T);
  end;
end;

// Der Pfad ab T wie im Quelltext, Glieder mit '.' ('System.SysUtils.Abort');
// ALow dasselbe klein. Nur T selbst, wenn kein '.' folgt; '' ohne T.
function PathAt(AMap: TRdxCodeMap; const T: TRdxToken;
  out ALow: string): string;
var
  D, N : TRdxToken;
  SB   : TStringBuilder;
begin
  Result := TokText(AMap, T);
  ALow := T.Low;
  if T.Low = '' then Exit;
  SB := TStringBuilder.Create;
  try
    SB.Append(Result);
    D := After(AMap, T);
    N := After(AMap, D);
    while (D.Low = '.') and N.IsWord do
    begin
      SB.Append('.').Append(TokText(AMap, N));
      D := After(AMap, N);
      N := After(AMap, D);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
  // TokenAt senkt jedes Glied mit LowerCase - den ganzen Pfad ebenso.
  ALow := LowerCase(Result);
end;

// SCA097: endet der Rumpf mit Exit, raise, Halt, Abort oder goto - auch
// qualifiziert ('System.Exit', 'SysUtils.Abort', DEAD_END_PATHS)? Dann
// liefe ein inherited dahinter nie. Dazu Exit/goto auf jeder Tiefe
// (LeavesDestructorReason). '' oder der Grund.
function DeadEndReason(AMap: TRdxCodeMap; const R: TRdxRoutine): string;
var
  S         : TRdxToken;
  Path, Low : string;
begin
  S := LastStatementStart(AMap, R);
  Path := PathAt(AMap, S, Low);
  if InList(S.Low, DEAD_END_WORDS) or InList(Low, DEAD_END_PATHS) then
    Exit(_('the last statement is %s (line %d) - inherited after it would '
      + 'never run; %s', [Path, S.Line, MsgByHand]));
  Result := LeavesDestructorReason(AMap, R);
end;

{ ---- Gemeinsame Nachweise ---- }

// SCA096/SCA097: was beide Planer nachweisen - die Meldung, genau ein Kopf
// AWord ('constructor' bzw. 'destructor') auf ALine, eine Methode mit
// Klasse ohne 'class' davor, ein begin-Rumpf ohne asm und ohne Direktive
// davor, kein 'inherited' im Text der Routine und die Klasse in der Unit.
// Legt den Planerlauf ACtx.Scan an. '' oder der Grund.
function MethodCtxReason(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage, AWord: string; out ACtx: TRdxMethodCtx): string;
var
  Key, What : string;
begin
  ACtx := Default(TRdxMethodCtx);
  ACtx.Scan := NewScan(AMap);
  // What: die Ergaenzung der Kopf-Suche als ganze uebersetzte Phrase
  // (RoutineOnLine setzt sie in MsgNoHeader/MsgHeadersFmt ein).
  Key := KEY_DTOR;
  What := _('of a destructor');
  if AWord = KW_CONSTRUCTOR then
  begin
    Key := KEY_CTOR;
    What := _('of a constructor');
  end;
  if Pos(Key, AMessage) = 0 then
    Exit(_('unknown message - no "%s"', [Key]));
  Result := RoutineOnLine(AMap, ALine, AWord, What, ACtx.Routine);
  if Result = '' then
    Result := MethodHeadReason(ACtx.Routine);
  if Result = '' then
    Result := BodyReason(AMap, ACtx.Routine);
  if Result = '' then
    Result := InheritedReason(AMap, ACtx.Routine);
  if Result = '' then
    Result := OwnerOf(ACtx.Scan, OwnerPathOf(ACtx.Routine.Name), ACtx.Owner);
end;

// SCA096: die Variante nach dem Vorfahren - (a) 'inherited Create' ruft
// TObject.Create (direkter TObject-Erbe oder NO_CTOR_PARENTS): 'inherited
// Create' (die Deklaration muss es geben, sonst gehoert der Kopf nicht zu
// dieser Klasse; ein overload stoert nicht - 'inherited Create' meint immer
// TObject.Create); (b) override: 'inherited', gekennzeichnet, nicht
// abstrakt geerbt, ohne Delegation und nicht blockiert. Setzt APlan.Name
// bzw. APlan.Changes. '' oder der Grund.
function CtorVariantReason(var ACtx: TRdxMethodCtx;
  var APlan: TRdxResultPlan): string;
begin
  if ACtx.Owner.CreateOfTObject then
  begin
    APlan.Name := STMT_INHERITED_CREATE;
    if Length(DeclHeadsOf(ACtx.Scan, ACtx.Routine)) = 0 then
      Exit(MsgMovedSuffix(_(R_NO_DECL, [LastPart(ACtx.Routine.Name),
        OwnerPathOf(ACtx.Routine.Name)])));
    Exit('');
  end;
  Result := CtorOverrideReason(ACtx.Scan, ACtx.Routine, ACtx.Owner);
  APlan.Changes := Result = '';
  if Result = '' then
    Result := AbstractReason(ACtx);
  if Result = '' then
    Result := DelegationReason(ACtx.Scan, ACtx.Routine);
  if Result = '' then
    Result := BlockedReason(ACtx.Scan.Map, ACtx.Routine);
end;

{ TRdxInheritedFixes }

class function TRdxInheritedFixes.ConstructorInherited(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx   : TRdxMethodCtx;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  APlan.Name := STMT_INHERITED;
  Edits := nil;
  AReason := MethodCtxReason(AMap, ALine, AMessage, KW_CONSTRUCTOR, Ctx);
  if AReason = '' then
    AReason := CtorVariantReason(Ctx, APlan);
  if AReason = '' then
    AReason := FirstEdits(AMap, Ctx.Routine, APlan.Name + ';', Edits);
  Result := FinishPlan(APlan, Edits, AReason);
end;

class function TRdxInheritedFixes.DestructorInherited(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxResultPlan;
  out AReason: string): Boolean;
var
  Ctx   : TRdxMethodCtx;
  Edits : TArray<TRdxEdit>;
begin
  APlan := Default(TRdxResultPlan);
  APlan.Name := STMT_INHERITED;
  APlan.Changes := True;
  Edits := nil;
  AReason := MethodCtxReason(AMap, ALine, AMessage, KW_DESTRUCTOR, Ctx);
  if AReason = '' then
    AReason := DtorOverrideReason(Ctx.Scan, Ctx.Routine);
  if AReason = '' then
    AReason := AbstractReason(Ctx);
  if AReason = '' then
    AReason := DeadEndReason(AMap, Ctx.Routine);
  if AReason = '' then
    AReason := TRdxResultFixes.LastStatement(AMap, Ctx.Routine,
      STMT_INHERITED + ';', Edits);
  // TObject.Destroy ist leer: bei direktem TObject-Erben gleiche Bedeutung.
  if AReason = '' then
    APlan.Changes := not Ctx.Owner.DirectTObject;
  Result := FinishPlan(APlan, Edits, AReason);
end;

end.
