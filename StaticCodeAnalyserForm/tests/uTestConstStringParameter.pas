unit uTestConstStringParameter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConstStringParameter = class
  public
    [Test] procedure StringParam_NoConst_Reported;
    [Test] procedure StringParam_WithConst_NotReported;
    [Test] procedure StringParam_WithVar_NotReported;
    [Test] procedure IntegerParam_NotReported;
    // 2026-06-28 Guard: vertrags-fixierte Signaturen (Real-World ~75% der FP)
    [Test] procedure OverrideMethodStringParam_NotReported;
    [Test] procedure EventHandlerStringParam_NotReported;
    [Test] procedure Finding_ConfidenceIsLow;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestConstStringParameter.StringParam_NoConst_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Hash(s: string): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Hash(s: string): Integer;'#13#10 +
  'begin Result := Length(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkConstStringParameter) >= 1,
      's: string ohne const muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.StringParam_WithConst_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Hash(const s: string): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Hash(const s: string): Integer;'#13#10 +
  'begin Result := Length(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'const s: string ist OK');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.StringParam_WithVar_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    procedure Modify(var s: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Modify(var s: string);'#13#10 +
  'begin s := UpperCase(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'var s: string ist explizite Mutation - OK');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.IntegerParam_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Foo(i: Integer): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Foo(i: Integer): Integer;'#13#10 +
  'begin Result := i * 2; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'Integer-Param ist kein string - kein Finding');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.OverrideMethodStringParam_NotReported;
// FP-Fix (Real-World 2026-06-28): bei override/virtual-Methoden ist die
// Signatur durch die Basisklasse fixiert - der string-Param kann nicht lokal
// auf const umgestellt werden. Die Direktive steht nur auf der Decl, daher
// Name-Match (Decl<->Impl).
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    procedure Handle(s: string); virtual;'#13#10 +
  '  end;'#13#10 +
  '  TFoo = class(TBase)'#13#10 +
  '    procedure Handle(s: string); override;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.Handle(s: string);'#13#10 +
  'begin end;'#13#10 +
  'procedure TFoo.Handle(s: string);'#13#10 +
  'begin Writeln(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'virtual/override-Signatur ist vertrags-fixiert - const nicht lokal moeglich');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.EventHandlerStringParam_NotReported;
// FP-Fix: Event-Handler (erster Param Sender: TObject) sind per Event-Typ/DFM
// gebunden - Signatur nicht aenderbar.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure OnText(Sender: TObject; s: string);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.OnText(Sender: TObject; s: string);'#13#10 +
  'begin Writeln(s); end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkConstStringParameter),
      'Event-Handler-Signatur (Sender: TObject) ist gebunden - kein Finding');
  finally F.Free; end;
end;

procedure TTestConstStringParameter.Finding_ConfidenceIsLow;
// H4-Demotion 2026-06-28 (~26% FP): SCA170 ist fcLow -> raus aus Default-Profil.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    function Hash(s: string): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Hash(s: string): Integer;'#13#10 +
  'begin Result := Length(s); end;'#13#10 +
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
      if Fnd.Kind = fkConstStringParameter then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkConstStringParameter finding expected');
    Assert.AreEqual(fcLow, Hit.Confidence);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConstStringParameter);

end.
