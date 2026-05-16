unit uTestSuperfluousSemicolon;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSuperfluousSemicolon = class
  public
    [Test] procedure NormalCode_NoFinding;
    [Test] procedure DoubleSemi_Reported;
    [Test] procedure SemiSpaceSemi_Reported;
    [Test] procedure SemiInString_NotReported;
    [Test] procedure SuperfluousSemicolon_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSuperfluousSemicolon.NormalCode_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.DoubleSemi_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff;; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SemiSpaceSemi_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff;  ;  end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SemiInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; WriteLn('';;''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SuperfluousSemicolon_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; DoStuff;; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkSuperfluousSemicolon then
      begin
        Assert.AreEqual<TFindingKind>(fkSuperfluousSemicolon, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkSuperfluousSemicolon finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSuperfluousSemicolon);

end.
