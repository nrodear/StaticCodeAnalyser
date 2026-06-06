unit uTestFreeAndNilHint;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeAndNilHint = class
  public
    [Test] procedure FreeAlone_NoFinding;
    [Test] procedure FreeAndNilOnNextLine_Reported;
    [Test] procedure DifferentReceiver_NoFinding;
    [Test] procedure FreeAndNilHint_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFreeAndNilHint.FreeAlone_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnNextLine_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.DifferentReceiver_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  A.Free;'#13#10 +
  '  B := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilHint_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkFreeAndNilHint then
      begin
        Assert.AreEqual<TFindingKind>(fkFreeAndNilHint, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFreeAndNilHint finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeAndNilHint);

end.
