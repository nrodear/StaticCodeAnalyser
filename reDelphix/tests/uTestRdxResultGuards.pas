unit uTestRdxResultGuards;

// Gegen-Review der Charge H5 (Charge H5c): die Fixtures des Pruefers als
// Tests gegen uRdxResultFixes - ohne Parser, ohne Detektor (laeuft in
// reDelphix.Test UND im FPC-Pruefstand). Jeder Test war gegen den Stand
// 111fed9d rot.
//   SCA096 Major 1: Delegation an einen eigenen Konstruktor ohne 'Create'
//          im Namen (mORMot THttpClientSocket.OpenFrom -> OpenOptions),
//          auch aus dem Vorfahren der Unit; ein Aufruf einer Prozedur
//          sperrt nicht;
//          Minor 1: abstrakte geerbte Methode in der Unit (auch zwei Stufen
//          hoeher), {$mode objfpc} mit Vorfahr ausserhalb der Unit - beides
//          auch fuer SCA097;
//          Minor 3: Direktive in der Vorfahrenliste, qualifiziertes
//          Interface als erster Eintrag;
//          Erweiterung: TPersistent, TInterfacedObject, TCustomAttribute -
//          'inherited Create' bedeutungsgleich, ausser die Unit deklariert
//          den Namen selbst; SCA097 bleibt dort gekennzeichnet;
//   SCA097 Minor 2: Exit bzw. goto auf jeder Tiefe;
//   SCA121 Minor 4: Literal fuer einfache Typen, Typen der Unit
//          (Aufzaehlung, Klasse, Menge, Record), Default(T) sonst und
//          gesperrt bei Spuren alter Compiler;
//          Minor 5: Zuweisung an Result bzw. den Funktionsnamen im Rumpf
//          (auch im inaktiven Zweig), Exit(Wert); eine lokale Routine, die
//          Result schreibt, sperrt nicht;
//   SCA196 Minor 8: eine Typdefinition der Unit gilt vor dem RTL-Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxResultGuards = class
  public
    [Test] procedure Refuse096_DelegationOwnConstructor;
    [Test] procedure Sca096_ProcedureCallIsNoDelegation;
    [Test] procedure Refuse096_AbstractInherited;
    [Test] procedure Refuse096_ObjFpcForeignParent;
    [Test] procedure Refuse097_AbstractOrObjFpc;
    [Test] procedure Refuse097_JumpAtAnyDepth;
    [Test] procedure Refuse096_DirectiveInHeritage;
    [Test] procedure Refuse096_QualifiedFirstEntry;
    [Test] procedure Sca096_ParentsWithoutConstructor;
    [Test] procedure Refuse096_ParentNameRedeclared;
    [Test] procedure Sca097_PersistentStaysMarked;
    [Test] procedure Sca121_Literals;
    [Test] procedure Sca121_UnitTypes;
    [Test] procedure Refuse121_OldCompilerDefault;
    [Test] procedure Refuse121_ResultWritten;
    [Test] procedure Sca121_LocalRoutineWritesResult;
    [Test] procedure Refuse196_OwnTypeDefinition;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxResultFixes;

const
  MSG_CTOR = 'Constructor has no `inherited` call - parent class is not '
    + 'initialized. Add `inherited Create(...)` or `inherited;` (use // '
    + 'noinspection if intentional).';
  MSG_DTOR = 'Destructor has no `inherited` call - parent class cleanup is '
    + 'skipped, likely leak. Add `inherited Destroy;` or `inherited;` at the '
    + 'end of the body.';
  MSG_121 = 'Function %s never assigns Result (return value undefined)';
  MSG_196 = 'Function %s reads Result before assigning it (Result appears '
    + 'on the right-hand side of its own first assignment) - for return type '
    + '%s, Result is a hidden var parameter aliasing the caller''s target '
    + 'variable and starts with its OLD content, not empty.';

// ---- Helfer ----

function Apply(const ASource: string; const AEdits: TArray<TRdxEdit>): string;
var
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, AEdits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Zeilen mit CRLF verbunden (TStringBuilder: string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Eine Unit mit den Kopfzeilen AHead (vor interface, etwa '{$mode objfpc}'),
// den Typen ATypes und den Zeilen AImpl.
function UnitWith(const AHead, ATypes, AImpl: array of string): string;
begin
  Result := Join(['unit u;']) + #13#10 + Join(AHead) + #13#10
    + Join(['interface', 'type']) + #13#10 + Join(ATypes) + #13#10
    + 'implementation' + #13#10 + Join(AImpl) + #13#10 + 'end.';
end;

// Die erste Zeile (1-basiert), die mit AStart beginnt (Leerraum davor
// zaehlt nicht); 0 ohne.
function LineOf(const ASource, AStart: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Copy(TrimLeft(SL[i]), 1, Length(AStart)) = AStart then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

// Der Plan des Planers APlanner fuer die Zeile, die mit AHead beginnt;
// AReason = '' heisst Hilfe.
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
    APlanner(Map, LineOf(ASource, AHead), AMessage, Result, AReason);
  finally
    Map.Free;
    SL.Free;
  end;
end;

type
  // Ein Lauf des Planers: neuer Text ('' bei Ablehnung), Grund und Plan.
  TFixRun = record
    Text   : string;
    Reason : string;
    Plan   : TRdxResultPlan;
  end;

function RunFix(APlanner: TRdxResultPlanner; const ASource, AHead,
  AMessage: string): TFixRun;
begin
  Result.Text := '';
  Result.Plan := PlanAt(APlanner, ASource, AHead, AMessage, Result.Reason);
  if Result.Reason = '' then
    Result.Text := Apply(ASource, Result.Plan.Edits);
end;

procedure AssertRefused(APlanner: TRdxResultPlanner; const ASource, AHead,
  AMessage, APart: string);
var
  F : TFixRun;
begin
  F := RunFix(APlanner, ASource, AHead, AMessage);
  Assert.AreEqual('', F.Text, 'keine Hilfe');
  Assert.IsTrue(Pos(APart, F.Reason) > 0, F.Reason);
end;

// SCA096 am Konstruktor TFoo.Create(A: Integer) mit dem Rumpf ABody.
function CtorSource(const AHead, ATypes, ABody: array of string): string;
begin
  Result := UnitWith(AHead, ATypes, ['constructor TFoo.Create(A: Integer);',
    'begin']);
  Result := StringReplace(Result, #13#10'end.', #13#10 + Join(ABody)
    + #13#10'end;'#13#10'end.', []);
end;

// Der Wert, den SCA121 fuer die Funktion F: AType in einer Unit mit den
// Typen ATypes und den Kopfzeilen AHead einsetzt; '' bei Ablehnung (AReason).
function Value121(const AHead, ATypes: array of string; const AType: string;
  out AReason: string): string;
var
  F : TFixRun;
begin
  F := RunFix(TRdxResultFixes.ResultDefault, UnitWith(AHead, ATypes,
    ['function F(A: Integer): ' + AType + ';', 'begin', '  Log(A);', 'end;']),
    'function F', Format(MSG_121, ['F']));
  AReason := F.Reason;
  Result := '';
  if F.Text <> '' then
    Result := F.Plan.Name;
end;

const
  NO_HEAD: array[0..0] of string = ('');
  NO_TYPES: array[0..0] of string = ('  TAlias = Integer;');

// ---- SCA096: Delegation (Major 1) ----

procedure TTestRdxResultGuards.Refuse096_DelegationOwnConstructor;
const
  // mORMot THttpClientSocket.OpenFrom (Gegen-Review H5, Fixture E5).
  SOCKET_TYPES: array[0..6] of string = ('  TCrtSocket = class',
    '    constructor OpenFrom(aClient: TCrtSocket); virtual;', '  end;',
    '  THttpClientSocket = class(TCrtSocket)',
    '    constructor OpenOptions(const aUri: string);',
    '    constructor OpenFrom(aClient: TCrtSocket); override;', '  end;');
  // Der gerufene Konstruktor steht im Vorfahren der Unit.
  CHAIN_TYPES: array[0..6] of string = ('  TBase = class(TComponent)',
    '    constructor Make(N: Integer);', '  end;', '  TFoo = class(TBase)',
    '    constructor Create(A: Integer); override;', '  end;', '');
var
  S : string;
begin
  S := UnitWith(NO_HEAD, SOCKET_TYPES,
    ['constructor THttpClientSocket.OpenFrom(aClient: TCrtSocket);', 'begin',
    '  OpenOptions(''x'');', 'end;']);
  AssertRefused(TRdxResultFixes.ConstructorInherited, S,
    'constructor THttpClientSocket.OpenFrom', MSG_CTOR, 'Delegation');
  S := CtorSource(NO_HEAD, CHAIN_TYPES, ['  if A > 0 then', '    Make(A);']);
  AssertRefused(TRdxResultFixes.ConstructorInherited, S, 'constructor TFoo',
    MSG_CTOR, 'Aufruf Make');
end;

procedure TTestRdxResultGuards.Sca096_ProcedureCallIsNoDelegation;
const
  TYPES: array[0..3] of string = ('  TFoo = class(TComponent)',
    '    procedure Init;', '    constructor Create(A: Integer); override;',
    '  end;');
var
  S : string;
  F : TFixRun;
begin
  // 'Init' ist eine Prozedur der Klasse - keine Delegation.
  S := CtorSource(NO_HEAD, TYPES, ['  Init;']);
  F := RunFix(TRdxResultFixes.ConstructorInherited, S, 'constructor TFoo',
    MSG_CTOR);
  Assert.AreEqual(StringReplace(S, '  Init;', '  inherited;'#13#10'  Init;', []),
    F.Text, F.Reason);
end;

// ---- SCA096/SCA097: abstrakt, objfpc (Minor 1) ----

procedure TTestRdxResultGuards.Refuse096_AbstractInherited;
const
  DIRECT: array[0..5] of string = ('  TBase = class',
    '    constructor Create(A: Integer); virtual; abstract;', '  end;',
    '  TFoo = class(TBase)', '    constructor Create(A: Integer); override;',
    '  end;');
  // Zwei Stufen: TMid deklariert Create nicht, TBase abstrakt.
  CHAIN: array[0..7] of string = ('  TBase = class',
    '    constructor Create(A: Integer); virtual; abstract;', '  end;',
    '  TMid = class(TBase)', '  end;', '  TFoo = class(TMid)',
    '    constructor Create(A: Integer); override;', '  end;');
begin
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(NO_HEAD, DIRECT, ['  Log(A);']), 'constructor TFoo', MSG_CTOR,
    'TBase.Create ist abstrakt');
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(NO_HEAD, CHAIN, ['  Log(A);']), 'constructor TFoo', MSG_CTOR,
    'TBase.Create ist abstrakt');
end;

procedure TTestRdxResultGuards.Refuse096_ObjFpcForeignParent;
const
  TYPES: array[0..2] of string = ('  TFoo = class(TComponent)',
    '    constructor Create(A: Integer); override;', '  end;');
  OBJFPC: array[0..0] of string = ('{$mode objfpc}{$H+}');
  DELPHI_MODE: array[0..0] of string = ('{$mode delphi}');
var
  F : TFixRun;
begin
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(OBJFPC, TYPES, ['  Log(A);']), 'constructor TFoo', MSG_CTOR,
    'nicht beweisbar');
  // Im Delphi-Modus bleibt das Angebot.
  F := RunFix(TRdxResultFixes.ConstructorInherited,
    CtorSource(DELPHI_MODE, TYPES, ['  Log(A);']), 'constructor TFoo', MSG_CTOR);
  Assert.AreNotEqual('', F.Text, F.Reason);
end;

procedure TTestRdxResultGuards.Refuse097_AbstractOrObjFpc;
const
  ABSTRACT_TYPES: array[0..5] of string = ('  TBase = class',
    '    destructor Destroy; override; abstract;', '  end;',
    '  TFoo = class(TBase)', '    destructor Destroy; override;', '  end;');
  FOREIGN_TYPES: array[0..2] of string = ('  TFoo = class(TComponent)',
    '    destructor Destroy; override;', '  end;');
  OBJFPC: array[0..0] of string = ('{$MODE OBJFPC}');
  IMPL: array[0..3] of string = ('destructor TFoo.Destroy;', 'begin',
    '  FList.Free;', 'end;');
begin
  AssertRefused(TRdxResultFixes.DestructorInherited,
    UnitWith(NO_HEAD, ABSTRACT_TYPES, IMPL), 'destructor TFoo', MSG_DTOR,
    'TBase.Destroy ist abstrakt');
  AssertRefused(TRdxResultFixes.DestructorInherited,
    UnitWith(OBJFPC, FOREIGN_TYPES, IMPL), 'destructor TFoo', MSG_DTOR,
    'nicht beweisbar');
end;

// ---- SCA097: Exit/goto (Minor 2) ----

procedure TTestRdxResultGuards.Refuse097_JumpAtAnyDepth;
const
  TYPES: array[0..2] of string = ('  TFoo = class(TComponent)',
    '    destructor Destroy; override;', '  end;');
begin
  // Abbrevia TMultiTree.Destroy: 'exit' in einer Schleife.
  AssertRefused(TRdxResultFixes.DestructorInherited, UnitWith(NO_HEAD, TYPES,
    ['destructor TFoo.Destroy;', 'begin', '  while Curr <> nil do',
    '    if Curr = Root then', '    begin', '      Curr.Free;', '      exit;',
    '    end', '    else', '      Curr := Curr.Parent;', 'end;']),
    'destructor TFoo', MSG_DTOR, 'exit in Zeile');
  AssertRefused(TRdxResultFixes.DestructorInherited, UnitWith(NO_HEAD, TYPES,
    ['destructor TFoo.Destroy;', 'begin', '  if A = nil then Exit;',
    '  A.Free;', 'end;']), 'destructor TFoo', MSG_DTOR, 'Exit in Zeile');
  AssertRefused(TRdxResultFixes.DestructorInherited, UnitWith(NO_HEAD, TYPES,
    ['destructor TFoo.Destroy;', 'label Done;', 'begin',
    '  if A = nil then goto Done;', '  A.Free;', 'Done:', 'end;']),
    'destructor TFoo', MSG_DTOR, 'goto in Zeile');
end;

// ---- SCA096: Vorfahrenliste (Minor 3) ----

procedure TTestRdxResultGuards.Refuse096_DirectiveInHeritage;
const
  IN_LIST: array[0..1] of string = (
    '  TFoo = class({$IFDEF FPC}TPersistent{$ELSE}TObject{$ENDIF})',
    '    constructor Create(A: Integer);');
  AROUND_LIST: array[0..1] of string = (
    '  TFoo = class{$IFDEF X}(TComponent){$ENDIF}',
    '    constructor Create(A: Integer); override;');
  END_LINE: array[0..0] of string = ('  end;');
begin
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(NO_HEAD, [IN_LIST[0], IN_LIST[1], END_LINE[0]], ['  Log(A);']),
    'constructor TFoo', MSG_CTOR, 'Direktive in der Vorfahrenliste');
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(NO_HEAD, [AROUND_LIST[0], AROUND_LIST[1], END_LINE[0]],
    ['  Log(A);']), 'constructor TFoo', MSG_CTOR,
    'Direktive in der Vorfahrenliste');
end;

procedure TTestRdxResultGuards.Refuse096_QualifiedFirstEntry;
const
  // Ein eigenes IFoo in der Unit beweist nichts ueber Other.IFoo.
  TYPES: array[0..4] of string = ('  IFoo = interface', '  end;',
    '  TFoo = class(Other.IFoo)', '    constructor Create(A: Integer);',
    '  end;');
begin
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(NO_HEAD, TYPES, ['  Log(A);']), 'constructor TFoo', MSG_CTOR,
    'Elternklasse IFoo');
end;

// ---- SCA096/SCA097: Vorfahren ohne Konstruktor (Erweiterung) ----

procedure TTestRdxResultGuards.Sca096_ParentsWithoutConstructor;
const
  PARENTS: array[0..4] of string = ('TPersistent', 'Classes.TPersistent',
    'TInterfacedObject', 'System.TInterfacedObject', 'TCustomAttribute');
var
  S, H : string;
  F    : TFixRun;
begin
  for H in PARENTS do
  begin
    S := CtorSource(NO_HEAD, ['  TFoo = class(' + H + ')',
      '    constructor Create(A: Integer);', '  end;'], ['  Log(A);']);
    F := RunFix(TRdxResultFixes.ConstructorInherited, S, 'constructor TFoo',
      MSG_CTOR);
    Assert.AreEqual(StringReplace(S, '  Log(A);',
      '  inherited Create;'#13#10'  Log(A);', []), F.Text, H + ': ' + F.Reason);
    Assert.AreEqual(STMT_INHERITED_CREATE, F.Plan.Name, H);
    Assert.IsFalse(F.Plan.Changes, H + ': TObject.Create ist leer');
  end;
end;

procedure TTestRdxResultGuards.Refuse096_ParentNameRedeclared;
const
  // Die Unit bringt ein eigenes TPersistent mit - dessen Konstruktor kennt
  // die Liste nicht.
  TYPES: array[0..5] of string = ('  TPersistent = class',
    '    constructor Create(A: Integer); virtual;', '  end;',
    '  TFoo = class(TPersistent)', '    constructor Create(A: Integer);',
    '  end;');
begin
  AssertRefused(TRdxResultFixes.ConstructorInherited,
    CtorSource(NO_HEAD, TYPES, ['  Log(A);']), 'constructor TFoo', MSG_CTOR,
    'Entwurf');
end;

procedure TTestRdxResultGuards.Sca097_PersistentStaysMarked;
var
  F : TFixRun;
begin
  // TPersistent.Destroy ist NICHT leer - gekennzeichnet wie bisher.
  F := RunFix(TRdxResultFixes.DestructorInherited,
    UnitWith(NO_HEAD, ['  TFoo = class(TPersistent)',
    '    destructor Destroy; override;', '  end;'], ['destructor TFoo.Destroy;',
    'begin', '  FList.Free;', 'end;']), 'destructor TFoo', MSG_DTOR);
  Assert.AreNotEqual('', F.Text, F.Reason);
  Assert.IsTrue(F.Plan.Changes, 'TPersistent.Destroy');
end;

// ---- SCA121: Werte (Minor 4) ----

procedure TTestRdxResultGuards.Sca121_Literals;
const
  TYPES: array[0..10] of string = ('Boolean', 'Integer', 'Double', 'string',
    'string[20]', 'Char', 'Pointer', 'TObject', 'TBytes', 'TStringDynArray',
    'System.Int64');
  VALUES: array[0..10] of string = ('False', '0', '0', '''''', '''''', '#0',
    'nil', 'nil', 'nil', 'nil', '0');
var
  R : string;
  i : Integer;
begin
  for i := 0 to High(TYPES) do
    Assert.AreEqual(VALUES[i], Value121(NO_HEAD, NO_TYPES, TYPES[i], R),
      TYPES[i] + ': ' + R);
  // Records, Typparameter und Unbekanntes: Default(T).
  Assert.AreEqual('Default(TGUID)', Value121(NO_HEAD, NO_TYPES, 'TGUID', R), R);
  Assert.AreEqual('Default(TFremd)', Value121(NO_HEAD, NO_TYPES, 'TFremd', R), R);
end;

procedure TTestRdxResultGuards.Sca121_UnitTypes;
const
  OWN: array[0..5] of string = ('  TMode = (mdNone, mdFast);',
    '  TItem = class', '  end;', '  TModes = set of TMode;',
    '  TPoint3 = record X, Y, Z: Integer; end;', '  TInts = array of Integer;');
  ASSIGNED_ENUM: array[0..0] of string = ('  TMode = (mdNone = 1, mdFast);');
  SCOPED: array[0..0] of string = ('{$SCOPEDENUMS ON}');
  ENUM_ONLY: array[0..0] of string = ('  TMode = (mdNone, mdFast);');
  // Die Unit definiert Integer um (Typ der Unit vor der RTL).
  REDEFINED: array[0..0] of string = ('  Integer = record A: Byte; end;');
var
  R : string;
begin
  Assert.AreEqual('mdNone', Value121(NO_HEAD, OWN, 'TMode', R), R);
  Assert.AreEqual('nil', Value121(NO_HEAD, OWN, 'TItem', R), R);
  Assert.AreEqual('[]', Value121(NO_HEAD, OWN, 'TModes', R), R);
  Assert.AreEqual('Default(TPoint3)', Value121(NO_HEAD, OWN, 'TPoint3', R), R);
  Assert.AreEqual('nil', Value121(NO_HEAD, OWN, 'TInts', R), R);
  // Eigene Ordinalwerte bzw. {$SCOPEDENUMS ON}: Default(T).
  Assert.AreEqual('Default(TMode)', Value121(NO_HEAD, ASSIGNED_ENUM, 'TMode',
    R), R);
  Assert.AreEqual('Default(TMode)', Value121(SCOPED, ENUM_ONLY, 'TMode', R), R);
  Assert.AreEqual('Default(Integer)', Value121(NO_HEAD, REDEFINED, 'Integer',
    R), R);
end;

procedure TTestRdxResultGuards.Refuse121_OldCompilerDefault;
const
  TRACES: array[0..4] of string = ('{$I jvcl.inc}', '{$I ..\Source\CnWizards.inc}',
    '{$IFDEF DELPHI2007_UP}{$ENDIF}', '{$IF CompilerVersion < 20}{$IFEND}',
    '{$IFNDEF VER150}{$ENDIF}');
  NEW_ONLY: array[0..1] of string = ('{$IF CompilerVersion >= 23}{$IFEND}',
    '{$IFDEF DELPHI12_UP}{$ENDIF}');
var
  R, T : string;
begin
  for T in TRACES do
  begin
    Assert.AreEqual('', Value121([T], NO_TYPES, 'TGUID', R), T);
    Assert.IsTrue(Pos('Spuren aelterer Compiler', R) > 0, T + ': ' + R);
    // Ein Literal kennt jeder Compiler.
    Assert.AreEqual('False', Value121([T], NO_TYPES, 'Boolean', R), T + ': ' + R);
  end;
  for T in NEW_ONLY do
    Assert.AreEqual('Default(TGUID)', Value121([T], NO_TYPES, 'TGUID', R),
      T + ': ' + R);
end;

// ---- SCA121: Zuweisung im Rumpf (Minor 5) ----

procedure TTestRdxResultGuards.Refuse121_ResultWritten;
const
  // Indy IdStackDotNet.HostByAddress: Result nur im inaktiven Zweig.
  BODIES: array[0..3] of string = ('{$IFDEF DOTNET} Result := Host; {$ENDIF}',
    'F := 1;', 'Result.X := 1;', 'if A > 0 then Exit(A);');
var
  B, S : string;
begin
  for B in BODIES do
  begin
    S := UnitWith(NO_HEAD, NO_TYPES, ['function F(A: Integer): TPt;',
      'begin', '  ' + B, 'end;']);
    AssertRefused(TRdxResultFixes.ResultDefault, S, 'function F',
      Format(MSG_121, ['F']), 'schreibt Result');
  end;
end;

procedure TTestRdxResultGuards.Sca121_LocalRoutineWritesResult;
var
  S : string;
  F : TFixRun;
begin
  // TES5Edit TwbNifFile.GetLinkArrays: die lokale Prozedur haengt an Result
  // an, die Funktion selbst weist nie zu - die Hilfe bleibt.
  S := UnitWith(NO_HEAD, NO_TYPES, ['function F: TBytes;',
    '  procedure Add(B: Byte);', '  begin', '    Result := Result + [B];',
    '  end;', 'begin', '  Add(1);', 'end;']);
  F := RunFix(TRdxResultFixes.ResultDefault, S, 'function F',
    Format(MSG_121, ['F']));
  Assert.AreEqual(StringReplace(S, '  Add(1);', '  Result := nil;'#13#10
    + '  Add(1);', []), F.Text, F.Reason);
end;

// ---- SCA196: Typ der Unit (Minor 8) ----

procedure TTestRdxResultGuards.Refuse196_OwnTypeDefinition;
const
  STATIC_BYTES: array[0..0] of string = ('  TBytes = array[0..3] of Byte;');
  DYN_BYTES: array[0..0] of string = ('  TBytes = array of Byte;');
  OWN_STRING: array[0..0] of string = ('  RawUtf8 = type AnsiString;');
var
  S : string;
  F : TFixRun;
begin
  S := UnitWith(NO_HEAD, STATIC_BYTES, ['function F: TBytes;', 'begin',
    '  Result[0] := 1;', 'end;']);
  AssertRefused(TRdxResultFixes.ManagedResultInit, S, 'Result[0]',
    Format(MSG_196, ['F', 'TBytes']), 'array ...');
  S := UnitWith(NO_HEAD, DYN_BYTES, ['function F: TBytes;', 'begin',
    '  Result[0] := 1;', 'end;']);
  F := RunFix(TRdxResultFixes.ManagedResultInit, S, 'Result[0]',
    Format(MSG_196, ['F', 'TBytes']));
  Assert.AreNotEqual('', F.Text, F.Reason);
  Assert.AreEqual('Result := nil', F.Plan.Name);
  S := UnitWith(NO_HEAD, OWN_STRING, ['function F: RawUtf8;', 'begin',
    '  Result := Result + ''x'';', 'end;']);
  F := RunFix(TRdxResultFixes.ManagedResultInit, S, 'Result := Result',
    Format(MSG_196, ['F', 'RawUtf8']));
  Assert.AreNotEqual('', F.Text, F.Reason);
  Assert.AreEqual('Result := ''''', F.Plan.Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxResultGuards);

end.
