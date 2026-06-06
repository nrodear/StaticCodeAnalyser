unit uTestInheritedMethodEmpty;

// Tests fuer den TInheritedMethodEmptyDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInheritedMethodEmpty = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure BareInherited_Reported;
    [Test] procedure InheritedWithSameName_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure InheritedPlusOtherStatement_NoFinding;
    [Test] procedure InheritedWithDifferentName_NoFinding;
    [Test] procedure NotOverride_NoFinding;
    [Test] procedure EmptyBody_NoFinding;
    [Test] procedure AbstractMethod_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInheritedMethodEmpty.BareInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.InheritedWithSameName_Reported;
// 'inherited Bar;' ist semantisch identisch zu 'inherited;' wenn die
// Methode den gleichen Namen hat - immer noch leer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.InheritedPlusOtherStatement_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoSomething;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.InheritedWithDifferentName_NoFinding;
// 'inherited OtherMethod;' ruft bewusst eine andere Parent-Methode auf -
// Method-Hijacking, legitim.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited Baz; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.NotOverride_NoFinding;
// Method ohne 'override'-Direktive - kein Pattern, kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.EmptyBody_NoFinding;
// Leerer Body (kein inherited) wird von EmptyRoutineCheck gefangen,
// nicht von uns.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.AbstractMethod_NoFinding;
// abstract = kein Body, kein Pattern.
const SRC =
  'unit t; interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Bar; virtual; abstract;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkInheritedMethodEmpty then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkInheritedMethodEmpty finding expected');
    Assert.AreEqual(fkInheritedMethodEmpty, Hit.Kind);
    Assert.AreEqual(lsHint,                 Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInheritedMethodEmpty);

end.
