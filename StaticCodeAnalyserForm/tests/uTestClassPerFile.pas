unit uTestClassPerFile;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClassPerFile = class
  public
    [Test] procedure SingleClass_NoFinding;
    [Test] procedure TwoClasses_Reported;
    [Test] procedure ForwardDecl_NotCounted;
    [Test] procedure ClassOfReference_NotCounted;
    [Test] procedure ClassPerFile_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestClassPerFile.SingleClass_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkClassPerFile));
  finally F.Free; end;
end;

procedure TTestClassPerFile.TwoClasses_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  '  TBaz = class'#13#10 +
  '    procedure Qux;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkClassPerFile));
  finally F.Free; end;
end;

procedure TTestClassPerFile.ForwardDecl_NotCounted;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class;'#13#10 +              // forward decl
  '  TFoo = class'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkClassPerFile));
  finally F.Free; end;
end;

procedure TTestClassPerFile.ClassOfReference_NotCounted;
// `class of` ist eine Reference, keine eigene Klasse
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFooClass = class of TObject;'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkClassPerFile));
  finally F.Free; end;
end;

procedure TTestClassPerFile.ClassPerFile_KindAndSeverity;
const SRC =
  'unit t; interface type TA = class end; TB = class end; implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkClassPerFile then
      begin
        Assert.AreEqual<TFindingKind>(fkClassPerFile, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,        Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkClassPerFile finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClassPerFile);

end.
