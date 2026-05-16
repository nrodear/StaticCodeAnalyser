unit uTestEmptyFinallyBlock;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyFinallyBlock = class
  public
    [Test] procedure FinallyWithCleanup_NoFinding;
    [Test] procedure EmptyFinally_Reported;
    [Test] procedure EmptyFinallyMultiline_Reported;
    [Test] procedure EmptyFinallyBlock_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyFinallyBlock.FinallyWithCleanup_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; finally Cleanup; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyFinallyBlock));
  finally F.Free; end;
end;

procedure TTestEmptyFinallyBlock.EmptyFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try DoStuff; finally end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyFinallyBlock));
  finally F.Free; end;
end;

procedure TTestEmptyFinallyBlock.EmptyFinallyMultiline_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  finally'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyFinallyBlock));
  finally F.Free; end;
end;

procedure TTestEmptyFinallyBlock.EmptyFinallyBlock_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; try DoStuff; finally end; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyFinallyBlock then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyFinallyBlock, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsWarning,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyFinallyBlock finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyFinallyBlock);

end.
