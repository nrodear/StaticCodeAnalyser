unit uTestRdxInheritedFixes;

// Quick-Fixes "Konstruktoren und Destruktoren" (uRdxInheritedFixes, Charge H5)
// auf Text - ohne Parser, ohne Detektor (laeuft in reDelphix.Test UND im
// FPC-Pruefstand):
//   SCA096 (a) 'inherited Create;' bei direktem TObject-Erben ('class',
//          'class(TObject)', 'class(IFoo)' mit Interface der Unit, 'class
//          sealed', generisch, Overload) - bedeutungsgleich; (b)
//          'inherited;' mit override an der Deklaration, gekennzeichnet;
//          Sperren: anderer Vorfahr ohne override, override mit overload,
//          Delegation an einen Konstruktor ('CreateNew', 'Self.CreateEx'),
//          blockierter Konstruktor ('Assert(False)', 'Raise..'), inherited
//          im Text (Kommentar, inaktiver Zweig), object, Record, class
//          helper, Klasse nicht oder doppelt in der Unit, class
//          constructor, asm, Direktive zwischen Kopf und begin, zwei Koepfe,
//          fremde Meldung, Konstruktor ohne Klasse;
//   SCA097 'inherited;' vor dem end (Baustein LastStatement): eigene Zeile,
//          fehlendes ';', inline, leerer Rumpf, Kommentare vor end, Tab;
//          gekennzeichnet ausser bei direktem TObject-Erben; Sperren: kein
//          override, letzte Anweisung Exit/raise, Direktive zwischen letzter
//          Anweisung und end, inherited im Text, class destructor. Seit
//          Charge B1-FE (Gegen-Review R5, je gegen 4358b769 rot): fehlendes ';'
//          hinter einem String-Literal - eigene Zeile und inline (R5-01,
//          missed 3) - und 'System.Exit', 'SysUtils.Abort' & Co. als Ende
//          (R5-05, missed 4).
// SCA121/SCA196: uTestRdxResultFixes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxInheritedFixes = class
  public
    [Test] procedure Sca096_TObjectDirect;
    [Test] procedure Sca096_TObjectForms;
    [Test] procedure Sca096_Override;
    [Test] procedure Refuse096_Design;
    [Test] procedure Refuse096_DelegationOrBlocked;
    [Test] procedure Refuse096_InheritedInText;
    [Test] procedure Refuse096_TypeKinds;
    [Test] procedure Refuse096_HeadAndBody;
    [Test] procedure Sca097_Override;
    [Test] procedure Sca097_TObjectDirectUnmarked;
    [Test] procedure Sca097_MissingSemicolon;
    [Test] procedure Sca097_InlineAndEmpty;
    [Test] procedure Sca097_CommentsTabsTry;
    [Test] procedure Refuse097_NoOverride;
    [Test] procedure Refuse097_DeadEnd;
    [Test] procedure Refuse097_DirectiveBeforeEnd;
    [Test] procedure Refuse097_InheritedOrClassDestructor;
    [Test] procedure Sca097_StringLiteralLast;
    [Test] procedure Sca097_StringLiteralInline;
    [Test] procedure Refuse097_QualifiedDeadEnd;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxResultFixes,
  uRdxInheritedFixes,  // SCA096/SCA097 (seit Review Woche G08-04)
  uTestRdxTextKit;   // Join, Apply, LineStartingWith

const
  MSG_CTOR = 'Constructor has no `inherited` call - parent class is not '
    + 'initialized. Add `inherited Create(...)` or `inherited;` (use // '
    + 'noinspection if intentional).';
  MSG_DTOR = 'Destructor has no `inherited` call - parent class cleanup is '
    + 'skipped, likely leak. Add `inherited Destroy;` or `inherited;` at the '
    + 'end of the body.';

// ---- Helfer ----

// Eine Unit mit den Typen ATypes (interface) und den Zeilen AImpl.
function InUnit(const ATypes, AImpl: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type']) + #13#10 + Join(ATypes)
    + #13#10 + 'implementation' + #13#10 + Join(AImpl) + #13#10 + 'end.';
end;

// Der Plan fuer die Zeile, die mit AHead beginnt; AReason = '' heisst Hilfe.
function PlanAt(APlanner: TRdxResultPlanner; const ASource, AHead,
  AMessage: string; out AReason: string): TRdxResultPlan;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    APlanner(Map, LineStartingWith(ASource, AHead), AMessage, Result, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// SCA096 bzw. SCA097 am Kopf AHead: neuer Text oder '' (AReason), APlan.
function Ctor(const ASource, AHead: string; out AReason: string;
  out APlan: TRdxResultPlan): string;
begin
  Result := '';
  APlan := PlanAt(TRdxInheritedFixes.ConstructorInherited, ASource, AHead,
    MSG_CTOR, AReason);
  if AReason = '' then
    Result := Apply(ASource, APlan.Edits);
end;

function Dtor(const ASource, AHead: string; out AReason: string;
  out APlan: TRdxResultPlan): string;
begin
  Result := '';
  APlan := PlanAt(TRdxInheritedFixes.DestructorInherited, ASource, AHead,
    MSG_DTOR, AReason);
  if AReason = '' then
    Result := Apply(ASource, APlan.Edits);
end;

procedure AssertCtorRefused(const ASource, AHead, APart: string);
var
  R : string;
  P : TRdxResultPlan;
begin
  Assert.AreEqual('', Ctor(ASource, AHead, R, P), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

procedure AssertDtorRefused(const ASource, AHead, APart: string);
var
  R : string;
  P : TRdxResultPlan;
begin
  Assert.AreEqual('', Dtor(ASource, AHead, R, P), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// Ein Konstruktor TFoo.Create(A) der Klasse 'TFoo = AHeritage' mit der
// Deklaration ADecl und dem Rumpf ABody (ohne begin/end).
function CtorUnit(const AHeritage, ADecl: string;
  const ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type', '  TFoo = ' + AHeritage,
    '  public', '    ' + ADecl, '  end;', 'implementation',
    'constructor TFoo.Create(A: Integer);', 'begin']) + #13#10 + Join(ABody)
    + #13#10 + Join(['end;', 'end.']);
end;

// Ein Destruktor TFoo.Destroy der Klasse 'TFoo = AHeritage' mit
// 'destructor Destroy; ADirectives' und den Zeilen AImpl ab dem Kopf.
function DtorUnit(const AHeritage, ADirectives: string;
  const AImpl: array of string): string;
begin
  Result := InUnit(['  TFoo = ' + AHeritage, '  public',
    '    destructor Destroy; ' + ADirectives, '  end;'], AImpl);
end;

// ---- SCA096 ----

procedure TTestRdxInheritedFixes.Sca096_TObjectDirect;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  S := InUnit(['  TFoo = class', '    FX: Integer;', '  public',
    '    constructor Create;', '  end;'],
    ['constructor TFoo.Create;', 'begin', '  FX := 0;', 'end;']);
  Assert.AreEqual(InUnit(['  TFoo = class', '    FX: Integer;', '  public',
    '    constructor Create;', '  end;'],
    ['constructor TFoo.Create;', 'begin', '  inherited Create;', '  FX := 0;',
    'end;']), Ctor(S, 'constructor TFoo', R, P), R);
  Assert.AreEqual(STMT_INHERITED_CREATE, P.Name);
  Assert.IsFalse(P.Changes, 'TObject.Create ist leer');
end;

procedure TTestRdxInheritedFixes.Sca096_TObjectForms;
const
  FORMS: array[0..2] of string = ('class(TObject)', 'class(System.TObject)',
    'class sealed');
var
  R, S, H : string;
  P       : TRdxResultPlan;
begin
  for H in FORMS do
  begin
    S := CtorUnit(H, 'constructor Create(A: Integer);', ['  Run(A);']);
    Assert.AreEqual(StringReplace(S, 'begin'#13#10,
      'begin'#13#10'  inherited Create;'#13#10, []),
      Ctor(S, 'constructor TFoo', R, P), H + ': ' + R);
  end;
  // Erster Eintrag ein Interface DIESER Unit: der Vorfahr ist TObject.
  S := InUnit(['  IFoo = interface', '  end;', '  TFoo = class(IFoo)',
    '    constructor Create;', '  end;'], ['constructor TFoo.Create;', 'begin',
    'end;']);
  Assert.AreEqual(StringReplace(S, 'begin'#13#10,
    'begin'#13#10'  inherited Create;'#13#10, []),
    Ctor(S, 'constructor TFoo', R, P), R);
  // Overloads und eine generische Klasse: 'inherited Create' meint immer
  // TObject.Create.
  S := InUnit(['  TBox<T> = class', '    constructor Create; overload;',
    '    constructor Create(A: T); overload;', '  end;'],
    ['constructor TBox<T>.Create(A: T);', 'begin', '  Keep(A);', 'end;']);
  Assert.AreEqual(StringReplace(S, 'begin'#13#10,
    'begin'#13#10'  inherited Create;'#13#10, []),
    Ctor(S, 'constructor TBox', R, P), R);
  // Eine fremde Klasse als erster Eintrag ist kein Interface-Beweis.
  S := CtorUnit('class(IFremd)', 'constructor Create(A: Integer);', ['  Run(A);']);
  Assert.AreEqual('', Ctor(S, 'constructor TFoo', R, P));
  Assert.IsTrue(Pos('Elternklasse IFremd', R) > 0, R);
end;

procedure TTestRdxInheritedFixes.Sca096_Override;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  S := InUnit(['  TBase = class', '    constructor Create(A: Integer); virtual;',
    '  end;', '  TFoo = class(TBase)',
    '    constructor Create(A: Integer); override;', '  end;'],
    ['constructor TFoo.Create(A: Integer);', 'begin', '  Log(A);', 'end;']);
  Assert.AreEqual(StringReplace(S, 'begin'#13#10,
    'begin'#13#10'  inherited;'#13#10, []), Ctor(S, 'constructor TFoo', R, P), R);
  Assert.AreEqual(STMT_INHERITED, P.Name);
  Assert.IsTrue(P.Changes, 'der Elternkonstruktor laeuft jetzt');
  // Vorfahr aus einer anderen Unit: override reicht als Beleg.
  S := CtorUnit('class(TComponent)', 'constructor Create(A: Integer); override;',
    ['  Run(A);']);
  Assert.AreEqual(StringReplace(S, 'begin'#13#10,
    'begin'#13#10'  inherited;'#13#10, []), Ctor(S, 'constructor TFoo', R, P), R);
  // Ein Feld als erstes Ziel, dessen Name mit Raise bzw. Create beginnt, ist
  // kein Aufruf (Review Woche G08-06; bis dahin "blockierter Konstruktor"
  // bzw. "Delegation").
  S := CtorUnit('class(TComponent)', 'constructor Create(A: Integer); override;',
    ['  RaiseOnError := A > 0;']);
  Assert.AreEqual(StringReplace(S, 'begin'#13#10,
    'begin'#13#10'  inherited;'#13#10, []), Ctor(S, 'constructor TFoo', R, P), R);
  S := CtorUnit('class(TComponent)', 'constructor Create(A: Integer); override;',
    ['  Created := True;']);
  Assert.AreEqual(StringReplace(S, 'begin'#13#10,
    'begin'#13#10'  inherited;'#13#10, []), Ctor(S, 'constructor TFoo', R, P), R);
end;

procedure TTestRdxInheritedFixes.Refuse096_Design;
begin
  AssertCtorRefused(CtorUnit('class(TComponent)',
    'constructor Create(A: Integer);', ['  Run(A);']), 'constructor TFoo',
    'Entwurf');
  AssertCtorRefused(CtorUnit('class(TComponent)',
    'constructor Create(A: Integer); overload; override;', ['  Run(A);']),
    'constructor TFoo', 'override mit overload');
end;

procedure TTestRdxInheritedFixes.Refuse096_DelegationOrBlocked;
const
  DECL = 'constructor Create(A: Integer); override;';
begin
  AssertCtorRefused(CtorUnit('class(TForm)', DECL, ['  CreateNew(nil);']),
    'constructor TFoo', 'Delegation');
  AssertCtorRefused(CtorUnit('class(TForm)', DECL, ['  Self.CreateEx(A);']),
    'constructor TFoo', 'Delegation');
  AssertCtorRefused(CtorUnit('class(TForm)', DECL,
    ['  Assert(False); // CreateWith rufen']), 'constructor TFoo', 'blockierter');
  AssertCtorRefused(CtorUnit('class(TForm)', DECL,
    ['  EFoo.RaiseUtf8(''nicht so'');']), 'constructor TFoo', 'blockierter');
end;

procedure TTestRdxInheritedFixes.Refuse096_InheritedInText;
begin
  // Bewusst auskommentiert bzw. in einem inaktiven Zweig - der Detektor
  // sieht es nicht.
  AssertCtorRefused(CtorUnit('class', 'constructor Create(A: Integer);',
    ['  // inherited Create; use AfterCreate instead', '  Run(A);']),
    'constructor TFoo', '"inherited" steht schon');
  AssertCtorRefused(CtorUnit('class(TBase)',
    'constructor Create(A: Integer); override;', ['{$IFDEF OLD}',
    '  inherited;', '{$ENDIF}']), 'constructor TFoo', '"inherited" steht schon');
  // Auch in einem String-Literal - die rohe Zeile zaehlt, der Grund nennt es
  // (Review Woche G08-05; bis dahin nur Zweig, Kommentar, lokale Routine).
  AssertCtorRefused(CtorUnit('class', 'constructor Create(A: Integer);',
    ['  Log(''inherited skipped'');']), 'constructor TFoo',
    'Kommentar, String-Literal oder lokale Routine');
end;

procedure TTestRdxInheritedFixes.Refuse096_TypeKinds;
begin
  AssertCtorRefused(InUnit(['  TObj = object', '    constructor Init;',
    '  end;'], ['constructor TObj.Init;', 'begin', 'end;']), 'constructor TObj',
    'object-Typ');
  AssertCtorRefused(InUnit(['  TRec = record', '    constructor Create(A: Integer);',
    '  end;'], ['constructor TRec.Create(A: Integer);', 'begin', 'end;']),
    'constructor TRec', 'Record');
  AssertCtorRefused(InUnit(['  TFooHelper = class helper for TFoo',
    '    constructor Create(A: Integer);', '  end;'],
    ['constructor TFooHelper.Create(A: Integer);', 'begin', 'end;']),
    'constructor TFooHelper', 'class helper');
  AssertCtorRefused(InUnit(['  TOther = class', '  end;'],
    ['constructor TFoo.Create;', 'begin', 'end;']), 'constructor TFoo',
    'nicht in dieser Unit');
  AssertCtorRefused(InUnit(['  TA = class', '  type', '    TItem = class',
    '      constructor Create;', '    end;', '  end;', '  TB = class', '  type',
    '    TItem = class', '      constructor Create;', '    end;', '  end;'],
    ['constructor TA.TItem.Create;', 'begin', 'end;']), 'constructor TA',
    'mehrdeutig');
  AssertCtorRefused(InUnit(['  TFoo = class', '    class constructor Create;',
    '  end;'], ['class constructor TFoo.Create;', 'begin', 'end;']),
    'class constructor TFoo', 'class constructor');
end;

procedure TTestRdxInheritedFixes.Refuse096_HeadAndBody;
var
  R : string;
  P : TRdxResultPlan;
  S : string;
begin
  S := InUnit(['  TFoo = class', '    constructor Create;', '  end;'],
    ['constructor TFoo.Create;', 'asm', '  nop', 'end;']);
  AssertCtorRefused(S, 'constructor TFoo', 'asm-Rumpf');
  S := InUnit(['  TFoo = class', '    constructor Create;', '  end;'],
    ['constructor TFoo.Create;', '{$IFDEF X}', 'var', '  I: Integer;',
    '{$ENDIF}', 'begin', 'end;']);
  AssertCtorRefused(S, 'constructor TFoo', 'Direktive zwischen Kopf und begin');
  S := InUnit(['  TFoo = class', '    constructor Create;',
    '    constructor Make;', '  end;'],
    ['constructor TFoo.Create; begin end; constructor TFoo.Make; begin end;']);
  // Zwei Koepfe auf der Zeile: 'Koepfe' traegt in de einen echten Umlaut
  // (uRdxText.MsgHeadersFmt) - geprueft wird das umlautfreie Ende des Grunds.
  AssertCtorRefused(S, 'constructor TFoo', 'eines Konstruktors - mehrdeutig');
  AssertCtorRefused(InUnit(['  TX = Integer;'], ['constructor Create;',
    'begin', 'end;']), 'constructor Create', 'ohne Klasse');
  S := InUnit(['  TFoo = class', '    constructor Create;', '  end;'],
    ['constructor TFoo.Create;', 'begin', 'end;']);
  P := PlanAt(TRdxInheritedFixes.ConstructorInherited, S, 'constructor TFoo',
    'Something else', R);
  Assert.IsTrue(Pos('Meldung unbekannt', R) > 0, R);
  Assert.AreEqual(STMT_INHERITED, P.Name, 'Menuetext auch gesperrt');
end;

// ---- SCA097 ----

procedure TTestRdxInheritedFixes.Sca097_Override;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  S := DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
    'begin', '  FList.Free;', 'end;']);
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  FList.Free;', '  inherited;',
    'end;']), Dtor(S, 'destructor TFoo', R, P), R);
  Assert.IsTrue(P.Changes, 'der Elterndestruktor laeuft jetzt');
  Assert.AreEqual(STMT_INHERITED, P.Name);
end;

procedure TTestRdxInheritedFixes.Sca097_TObjectDirectUnmarked;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  // TObject.Destroy ist leer - gleiche Bedeutung, nicht gekennzeichnet.
  S := DtorUnit('class', 'override;', ['destructor TFoo.Destroy;', 'begin',
    '  FList.Free;', 'end;']);
  Assert.AreNotEqual('', Dtor(S, 'destructor TFoo', R, P), R);
  Assert.IsFalse(P.Changes, 'direkt von TObject');
end;

procedure TTestRdxInheritedFixes.Sca097_MissingSemicolon;
var
  R, S : string;
  P    : TRdxResultPlan;
begin
  // Der letzten Anweisung fehlt das ';' - es kommt mit (zweite Ersetzung).
  S := DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
    'begin', '  if Assigned(FList) then', '    FList.Free', 'end;']);
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  if Assigned(FList) then',
    '    FList.Free;', '  inherited;', 'end;']), Dtor(S, 'destructor TFoo', R, P), R);
  Assert.AreEqual<Integer>(2, Length(P.Edits));
end;

procedure TTestRdxInheritedFixes.Sca097_InlineAndEmpty;
var
  R : string;
  P : TRdxResultPlan;
begin
  // end nicht am Zeilenanfang: inline hinter der letzten Anweisung.
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin FList.Free; inherited; end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
      'begin FList.Free; end;']), 'destructor TFoo', R, P), R);
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin FList.Free; inherited; end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
      'begin FList.Free end;']), 'destructor TFoo', R, P), R);
  // Leerer Rumpf: wie die erste Anweisung (eigene Zeile bzw. inline).
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  inherited;', 'end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
      'begin', 'end;']), 'destructor TFoo', R, P), R);
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy; begin inherited; end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;',
      ['destructor TFoo.Destroy; begin end;']), 'destructor TFoo', R, P), R);
end;

procedure TTestRdxInheritedFixes.Sca097_CommentsTabsTry;
var
  R : string;
  P : TRdxResultPlan;
begin
  // Kommentarzeilen vor end bleiben davor; die Zeile kommt direkt vor end,
  // eingerueckt wie die erste Anweisung (Tab).
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', #9'FList.Free;', #9'// FOld.Free;',
    #9'inherited;', 'end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
      'begin', #9'FList.Free;', #9'// FOld.Free;', 'end;']), 'destructor TFoo',
      R, P), R);
  // Ein try-Block als letzte Anweisung (ohne ';' vor end).
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  try', '    FList.Clear;',
    '  finally', '    FList.Free;', '  end;', '  inherited;', 'end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
      'begin', '  try', '    FList.Clear;', '  finally', '    FList.Free;',
      '  end', 'end;']), 'destructor TFoo', R, P), R);
end;

procedure TTestRdxInheritedFixes.Refuse097_NoOverride;
begin
  AssertDtorRefused(DtorUnit('class(TComponent)', '', ['destructor TFoo.Destroy;',
    'begin', '  FList.Free;', 'end;']), 'destructor TFoo', 'kein override');
end;

procedure TTestRdxInheritedFixes.Refuse097_DeadEnd;
begin
  AssertDtorRefused(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  FList.Free;', '  Exit;', 'end;']),
    'destructor TFoo', 'liefe nie');
  AssertDtorRefused(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  raise EAbort.Create(''x'');',
    'end;']), 'destructor TFoo', 'liefe nie');
end;

procedure TTestRdxInheritedFixes.Refuse097_DirectiveBeforeEnd;
begin
  AssertDtorRefused(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  FList.Free;', '{$IFDEF A}',
    '  FOld.Free;', '{$ENDIF}', 'end;']), 'destructor TFoo',
    'Direktive zwischen der letzten Anweisung und end');
end;

procedure TTestRdxInheritedFixes.Refuse097_InheritedOrClassDestructor;
begin
  AssertDtorRefused(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  FList.Free;',
    '  //inherited Destroy;', 'end;']), 'destructor TFoo',
    '"inherited" steht schon');
  AssertDtorRefused(InUnit(['  TFoo = class', '    class destructor Destroy;',
    '  end;'], ['class destructor TFoo.Destroy;', 'begin', 'end;']),
    'class destructor TFoo', 'class destructor');
end;

// ---- Gegen-Review R5 (Charge B1-FE) ----

// Die letzte Anweisung endet ohne ';' auf einem String-Literal (R5-01,
// missed 3; Pruefer-Fixtures R5/r3.txt, R5_verify/v01.txt, v01b.txt): das
// ';' kommt hinter das letzte Zeichen aus Code ODER String. Bis Charge B1-FE
// setzte der Planer es hinter das letzte Code-Token - vor das Literal
// ('FState :=; ''x''', als bedeutungsgleich gekennzeichnet).
procedure TTestRdxInheritedFixes.Sca097_StringLiteralLast;
const
  LASTS: array[0..6] of string = ('FState := ''x''', 'S := S + ''x''',
    'FName := #13''a''', 'FName := ''it''''s''', 'FName := ''a'' // c',
    'FName := FName + ''x'' { c }', 'FName := ''a''#13#10');
  FIXED: array[0..6] of string = ('FState := ''x'';', 'S := S + ''x'';',
    'FName := #13''a'';', 'FName := ''it''''s'';', 'FName := ''a''; // c',
    'FName := FName + ''x''; { c }', 'FName := ''a''#13#10;');
var
  R : string;
  P : TRdxResultPlan;
  i : Integer;
begin
  for i := 0 to High(LASTS) do
  begin
    Assert.AreEqual(DtorUnit('class', 'override;', ['destructor TFoo.Destroy;',
      'begin', '  ' + FIXED[i], '  inherited;', 'end;']),
      Dtor(DtorUnit('class', 'override;', ['destructor TFoo.Destroy;', 'begin',
        '  ' + LASTS[i], 'end;']), 'destructor TFoo', R, P), LASTS[i] + ': ' + R);
    Assert.IsFalse(P.Changes, LASTS[i] + ': TObject.Destroy ist leer');
  end;
  // Ein mehrzeiliges String-Literal (Delphi 12): das ';' hinter die
  // schliessenden Quotes.
  Assert.AreEqual(DtorUnit('class', 'override;', ['destructor TFoo.Destroy;',
    'begin', '  FName := ''''''', '    multi', '    '''''';', '  inherited;',
    'end;']),
    Dtor(DtorUnit('class', 'override;', ['destructor TFoo.Destroy;', 'begin',
      '  FName := ''''''', '    multi', '    ''''''', 'end;']),
      'destructor TFoo', R, P), R);
end;

// Dasselbe inline - 'end' nicht am Zeilenanfang (R5-01): bis Charge B1-FE
// 'FState :=; inherited; ''destroyed'' end;'.
procedure TTestRdxInheritedFixes.Sca097_StringLiteralInline;
var
  R : string;
  P : TRdxResultPlan;
begin
  Assert.AreEqual(DtorUnit('class', 'override;', ['destructor TFoo.Destroy;',
    'begin', '  FBar.Free; FState := ''destroyed''; inherited; end;']),
    Dtor(DtorUnit('class', 'override;', ['destructor TFoo.Destroy;', 'begin',
      '  FBar.Free; FState := ''destroyed'' end;']), 'destructor TFoo', R, P), R);
  Assert.AreEqual(DtorUnit('class(TObject)', 'override;',
    ['destructor TFoo.Destroy;', 'begin',
    '  FName := FName + '' (closed)''; inherited; end;']),
    Dtor(DtorUnit('class(TObject)', 'override;', ['destructor TFoo.Destroy;',
      'begin', '  FName := FName + '' (closed)'' end;']), 'destructor TFoo',
      R, P), R);
end;

// Qualifizierte Spruenge und Abbrueche (R5-05, missed 4; Pruefer-Fixtures
// R5/r2.txt, R5_verify/v05.txt): hinter '.' war das Wort kein
// Schluesselwort, die letzte Anweisung begann mit 'system' bzw.
// 'sysutils' - bis Charge B1-FE kam ein totes 'inherited;' dahinter bzw.
// verliess 'System.Exit' den Destruktor vor dem Ende. Eine Methode 'Abort'
// eines Objekts ist kein Abbruch.
procedure TTestRdxInheritedFixes.Refuse097_QualifiedDeadEnd;
const
  ENDS: array[0..3] of string = ('System.Exit', 'System.Halt',
    'SysUtils.Abort', 'System.SysUtils.Abort');
var
  E, R : string;
  P    : TRdxResultPlan;
begin
  for E in ENDS do
    AssertDtorRefused(DtorUnit('class(TComponent)', 'override;',
      ['destructor TFoo.Destroy;', 'begin', '  FBar.Free;', '  ' + E + ';',
      'end;']), 'destructor TFoo', 'die letzte Anweisung ist ' + E);
  AssertDtorRefused(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  if FShared then System.Exit;',
    '  FBar.Free;', 'end;']), 'destructor TFoo', 'Exit in Zeile 11');
  Assert.AreEqual(DtorUnit('class(TComponent)', 'override;',
    ['destructor TFoo.Destroy;', 'begin', '  FConn.Abort;', '  inherited;',
    'end;']),
    Dtor(DtorUnit('class(TComponent)', 'override;', ['destructor TFoo.Destroy;',
      'begin', '  FConn.Abort;', 'end;']), 'destructor TFoo', R, P), R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxInheritedFixes);

end.
