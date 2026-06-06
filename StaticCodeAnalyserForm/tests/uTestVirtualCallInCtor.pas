unit uTestVirtualCallInCtor;

// Tests fuer den TVirtualCallInCtorDetector (AST + parser-Modifiers).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVirtualCallInCtor = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure VCall_Virtual_InCtor_Reported;
    [Test] procedure VCall_Override_InCtor_Reported;
    [Test] procedure VCall_TwoVirtuals_InCtor_BothReported;
    [Test] procedure VCall_ExplicitSelf_InCtor_Reported;

    // ---- Negative Varianten ------------------------------------------------
    [Test] procedure NonVirtual_InCtor_NoFinding;
    [Test] procedure VirtualMethod_OutsideCtor_NoFinding;
    [Test] procedure InheritedCreate_NoFinding;
    [Test] procedure CallOnOtherObject_NoFinding;
    [Test] procedure NoConstructor_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure VCall_Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestVirtualCallInCtor.VCall_Virtual_InCtor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  Init;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_Override_InCtor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_TwoVirtuals_InCtor_BothReported;
// Konstruktor ruft zwei verschiedene virtual-Methoden -> beide Treffer.
// Wichtig: Self.SetupB und SetupA muessen beide als nkCall registriert sein.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure SetupA; virtual;'#13#10 +
  '  procedure SetupB; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create;'#13#10 +
  'begin'#13#10 +
  '  SetupA;'#13#10 +
  '  SetupB;'#13#10 +
  'end;'#13#10 +
  'procedure TBase.SetupA; begin end;'#13#10 +
  'procedure TBase.SetupB; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkVirtualCallInCtor),
    'Zwei virtuelle Calls im Ctor -> zwei Findings');
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_ExplicitSelf_InCtor_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Self.Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.NonVirtual_InCtor_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init;'#13#10 +     // KEIN virtual
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VirtualMethod_OutsideCtor_NoFinding;
// Virtual-Call in einer normalen Methode (nicht Constructor) ist OK.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  '  procedure DoStuff;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.DoStuff; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.InheritedCreate_NoFinding;
// inherited Create geht zur Basisklasse hoch, kein Override-Risiko
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin inherited Create; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.CallOnOtherObject_NoFinding;
// FFoo.DoSomething - kein Self-Call, kein Virtual-Override-Risiko
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  FFoo: TObject;'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin FFoo.Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.NoConstructor_NoFinding;
// Klasse ohne Constructor - dann kann es auch keinen Virtual-Call darin geben
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  '  procedure Other;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.Other; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkVirtualCallInCtor));
  finally F.Free; end;
end;

procedure TTestVirtualCallInCtor.VCall_Finding_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBase = class'#13#10 +
  '  constructor Create;'#13#10 +
  '  procedure Init; virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TBase.Create; begin Init; end;'#13#10 +
  'procedure TBase.Init; begin end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkVirtualCallInCtor then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkVirtualCallInCtor finding expected');
    Assert.AreEqual(fkVirtualCallInCtor, Hit.Kind);
    Assert.AreEqual(lsError,             Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVirtualCallInCtor);

end.
