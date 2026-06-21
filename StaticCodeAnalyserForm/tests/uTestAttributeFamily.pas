unit uTestAttributeFamily;

// Konsolidierte Tests fuer SCA179-183 (Attribute-Detector-Familie).
// Ein einziges Unit-File spart Plumbing-Overhead (5 Test-Units waeren
// 25+ Edits in TestProject.dpr/dproj).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAttributeIgnoreWithoutReason = class
  public
    [Test] procedure IgnoreNoArg_Reported;
    [Test] procedure IgnoreEmptyParens_Reported;
    [Test] procedure IgnoreWithMessage_NotReported;
  end;

  [TestFixture]
  TTestAttributeDuplicate = class
  public
    [Test] procedure SameAttributeTwice_Reported;
    [Test] procedure DifferentArgs_NotReported;
  end;

  [TestFixture]
  TTestAttributeCategoryWithoutString = class
  public
    [Test] procedure CategoryNoArg_Reported;
    [Test] procedure CategoryWithName_NotReported;
  end;

  [TestFixture]
  TTestAttributeTestFixtureWithoutTests = class
  public
    [Test] procedure FixtureNoTests_Reported;
    [Test] procedure FixtureWithTest_NotReported;
  end;

  [TestFixture]
  TTestAttributeMisalignment = class
  public
    [Test] procedure AttrWithBlankLine_Reported;
    [Test] procedure AttrDirectlyBeforeMember_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ TTestAttributeIgnoreWithoutReason }

procedure TTestAttributeIgnoreWithoutReason.IgnoreNoArg_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Ignore]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeIgnoreWithoutReason.IgnoreEmptyParens_Reported;
// Coverage-Fix (2026-06-21): [Ignore()] mit leeren Klammern = ebenfalls
// kein Grund - muss gemeldet werden.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Ignore()]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason) >= 1,
    '[Ignore()] ohne Grund muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestAttributeIgnoreWithoutReason.IgnoreWithMessage_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Ignore(''TBD ticket #1234'')]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeIgnoreWithoutReason));
  finally F.Free; end;
end;

{ TTestAttributeDuplicate }

procedure TTestAttributeDuplicate.SameAttributeTwice_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Test]'#13#10 +
  '    [Test]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeDuplicate) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeDuplicate.DifferentArgs_NotReported;
// [TestCase('A', '1')] + [TestCase('B', '2')] sind LEGITIM multi-applied.
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [TestCase(''A'', ''1'')]'#13#10 +
  '    [TestCase(''B'', ''2'')]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeDuplicate));
  finally F.Free; end;
end;

{ TTestAttributeCategoryWithoutString }

procedure TTestAttributeCategoryWithoutString.CategoryNoArg_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Category]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeCategoryWithoutString) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeCategoryWithoutString.CategoryWithName_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Category(''Slow'')]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeCategoryWithoutString));
  finally F.Free; end;
end;

{ TTestAttributeTestFixtureWithoutTests }

procedure TTestAttributeTestFixtureWithoutTests.FixtureNoTests_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  public'#13#10 +
  '    procedure Helper;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeTestFixtureWithoutTests.FixtureWithTest_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TFooTests = class'#13#10 +
  '  public'#13#10 +
  '    [Test] procedure DoesX;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeTestFixtureWithoutTests));
  finally F.Free; end;
end;

{ TTestAttributeMisalignment }

procedure TTestAttributeMisalignment.AttrWithBlankLine_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Test]'#13#10 +
  ''#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkAttributeMisalignment) >= 1);
  finally F.Free; end;
end;

procedure TTestAttributeMisalignment.AttrDirectlyBeforeMember_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TTest = class'#13#10 +
  '  public'#13#10 +
  '    [Test]'#13#10 +
  '    procedure Foo;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAttributeMisalignment));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAttributeIgnoreWithoutReason);
  TDUnitX.RegisterTestFixture(TTestAttributeDuplicate);
  TDUnitX.RegisterTestFixture(TTestAttributeCategoryWithoutString);
  TDUnitX.RegisterTestFixture(TTestAttributeTestFixtureWithoutTests);
  TDUnitX.RegisterTestFixture(TTestAttributeMisalignment);

end.
