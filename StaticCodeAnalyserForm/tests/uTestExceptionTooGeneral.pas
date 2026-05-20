unit uTestExceptionTooGeneral;

// Tests fuer den TExceptionTooGeneralDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExceptionTooGeneral = class
  public
    [Test] procedure OnException_Reported;
    [Test] procedure OnSpecificException_NotReported;
    [Test] procedure MixedHandlers_OnlyExceptionFlagged;
    [Test] procedure BareExceptBlock_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestExceptionTooGeneral.OnException_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    on E: Exception do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.OnSpecificException_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    on E: EConvertError do Log(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.MixedHandlers_OnlyExceptionFlagged;
// Spezifischer Handler zuerst, dann generischer Fallback - der generische
// soll geflaggt werden, der spezifische nicht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    on E: EConvertError do Handle1(E);'#13#10 +
  '    on E: Exception do Handle2(E);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.BareExceptBlock_NotReported;
// except ohne on - faengt zwar auch alles, ist aber Top-Level-Crash-Handler-
// Pattern und liegt ausserhalb des Scopes dieses Detektors.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    Bar;'#13#10 +
  '  except'#13#10 +
  '    Log(''crash'');'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkExceptionTooGeneral));
  finally F.Free; end;
end;

procedure TTestExceptionTooGeneral.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try Bar; except on E: Exception do; end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkExceptionTooGeneral then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkExceptionTooGeneral finding expected');
    Assert.AreEqual(fkExceptionTooGeneral, Hit.Kind);
    Assert.AreEqual(lsWarning,             Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExceptionTooGeneral);

end.
