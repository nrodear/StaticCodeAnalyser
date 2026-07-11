unit uTestConstructorWithoutInherited;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConstructorWithoutInherited = class
  public
    [Test] procedure CtorWithInherited_NoFinding;
    [Test] procedure CtorWithoutInherited_Reported;
    [Test] procedure RegularProcedure_NoFinding;
    [Test] procedure CtorForwardDecl_NotReported;
    [Test] procedure ClassConstructor_NotReported;
    [Test] procedure StandaloneCtorOutsideClass_NotReported;
    [Test] procedure CtorWithoutInherited_KindAndSeverity;
    // FP-Regression (Record-Guard 2026-06-29): Records haben KEINE Vererbungs-
    // Hierarchie - ein record-Konstruktor ohne `inherited` ist kein Bug.
    [Test] procedure RecordConstructor_NoFinding;
    // Gegenprobe: ein echter Klassen-Konstruktor ohne `inherited` feuert weiter.
    [Test] procedure ClassConstructorNoInherited_StillReported;
    // Real-World FP-Audit 2026-07-10: Sibling-Konstruktor-Delegation
    [Test] procedure CtorWithSiblingCreate_NoFinding;
    [Test] procedure CtorConstructsOtherObject_StillReported;
    // Real-World FP-Audit 2026-07-11: raises-only-Konstruktor (blockierter Singleton)
    [Test] procedure CtorRaisesOnly_NoFinding;
    [Test] procedure CtorConditionalRaise_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConstructorWithoutInherited.CtorWithInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorWithoutInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.RegularProcedure_NoFinding;
// Eine normale Methode ohne `inherited` ist KEIN Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorForwardDecl_NotReported;
// Regression: Forward-Deklaration im Class-Body (`constructor Create;`)
// hat keinen Body und darf NICHT als "fehlendes inherited" gemeldet
// werden. Implementation steht im implementation-Teil.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    constructor Create;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.ClassConstructor_NotReported;
// Spiegelt den realen FP aus uLexer.pas: class constructor laeuft einmal
// pro Klasse beim Modul-Initialize und hat KEINE inheritance chain -
// `inherited` ist hier nicht erwuenscht.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    class constructor Create;'#13#10 +
  '    class destructor Destroy;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  InitKeywords;'#13#10 +
  'end;'#13#10 +
  'class destructor TFoo.Destroy;'#13#10 +
  'begin'#13#10 +
  '  FreeAndNil(FStaticThing);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.StandaloneCtorOutsideClass_NotReported;
// FP-Regression: Top-level Konstruktor ohne Klassen-Kontext (Demo- oder
// Fixture-File, z.B. docs/samples/uUnusedRoutine_SCA164_Demo.pas). Es gibt
// keine Parent-Klasse, der man `inherited` rufen koennte - der Detector
// darf hier nicht feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor StandaloneCtor;'#13#10 +
  'begin'#13#10 +
  '  // keine Parent-Klasse - inherited waere syntaktisch unsinnig'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited));
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorWithoutInherited_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkConstructorWithoutInherited then
      begin
        Assert.AreEqual<TFindingKind>(fkConstructorWithoutInherited, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,                    Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkConstructorWithoutInherited finding');
  finally Findings.Free; end;
end;

procedure TTestConstructorWithoutInherited.RecordConstructor_NoFinding;
// Record-Guard (2026-06-29): TMyRec ist ein record - er hat keine Parent-
// Klasse, `inherited` ist syntaktisch unmoeglich. Der Detector sammelt
// record-Typnamen vorab und ueberspringt Konstruktoren, deren Qualifier
// ein record-Name ist. 'TMyRec.Create' ohne inherited ist daher KEIN Bug.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMyRec = record'#13#10 +
  '    FX: Integer;'#13#10 +
  '    constructor Create(AX: Integer);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'constructor TMyRec.Create(AX: Integer);'#13#10 +
  'begin'#13#10 +
  '  FX := AX;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited),
        'Record-Konstruktor ohne inherited darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.ClassConstructorNoInherited_StillReported;
// Gegenprobe zum Record-Guard: TFoo ist eine echte class. Sein Konstruktor
// ohne `inherited` laesst die Parent-Klasse uninitialisiert -> Treffer bleibt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    FX: Integer;'#13#10 +
  '    constructor Create;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstructorWithoutInherited) >= 1);
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorWithSiblingCreate_NoFinding;
// Real-World FP-Audit 2026-07-10: Sibling-Konstruktor-Delegation - der ctor ruft
// den unqualifizierten Geschwister-Create (der seinerseits inherited ruft), der
// Parent wird also transitiv initialisiert.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create(A: Integer);'#13#10 +
  'begin'#13#10 +
  '  Create;'#13#10 +
  '  FA := A;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited),
    'unqualifizierter Create-Aufruf = Sibling-Delegation, kein fehlendes inherited');
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorConstructsOtherObject_StillReported;
// Gegenprobe: 'TList.Create' konstruiert ein ANDERES Objekt (typ-qualifiziert),
// keine Sibling-Delegation -> fehlendes inherited bleibt Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  FList := TList.Create;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkConstructorWithoutInherited),
    'TList.Create ist typ-qualifiziert, keine Sibling-Delegation - bleibt Fund');
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorRaisesOnly_NoFinding;
// Real-World FP-Audit 2026-07-11 (Grijjy.ErrorReporting.pas:347): der ctor
// besteht ausschliesslich aus einem unbedingten `raise` (blockierter Singleton-
// Konstruktor). Es entsteht NIE eine Instanz - fehlendes inherited kann keinen
// Folgefehler ausloesen, also KEIN Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TgoExceptionReporter.Create;'#13#10 +
  'begin'#13#10 +
  '  raise EInvalidOperation.Create(''Invalid singleton constructor call'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstructorWithoutInherited),
    'raises-only-Konstruktor erzeugt nie eine Instanz - kein fehlendes inherited');
  finally F.Free; end;
end;

procedure TTestConstructorWithoutInherited.CtorConditionalRaise_StillReported;
// Gegenprobe zum raises-only-Guard: der raise ist BEDINGT (Guard-Clause). Ist
// die Bedingung falsch, wird das Objekt real und ohne inherited konstruiert ->
// echter Bug. Erste Anweisung ist ein if (kein unbedingtes raise), der Fund bleibt.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  if not Assigned(FConfig) then'#13#10 +
  '    raise EInvalidOperation.Create(''no config'');'#13#10 +
  '  FX := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkConstructorWithoutInherited) >= 1,
    'bedingter raise rettet den fehlenden inherited nicht - Fund bleibt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstructorWithoutInherited);

end.
