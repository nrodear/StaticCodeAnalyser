unit uTestEmptyFile;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyFile = class
  public
    [Test] procedure FileWithDecl_NoFinding;
    [Test] procedure EmptyUnit_Reported;
    [Test] procedure JustConst_NoFinding;
    [Test] procedure EmptyFile_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyFile.FileWithDecl_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'procedure Foo;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.EmptyUnit_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.JustConst_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'const X = 1;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyFile));
  finally F.Free; end;
end;

procedure TTestEmptyFile.EmptyFile_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyFile then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyFile, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyFile finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyFile);

end.
