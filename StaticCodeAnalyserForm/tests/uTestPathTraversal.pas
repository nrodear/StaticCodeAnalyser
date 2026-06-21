unit uTestPathTraversal;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPathTraversal = class
  public
    [Test] procedure FileStreamWithEditText_Reported;
    [Test] procedure FileOpenWithLiteral_NotReported;
    [Test] procedure FileStreamWithoutConcat_NotReported;
    [Test] procedure ConstWithTextSubstring_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPathTraversal.FileStreamWithEditText_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(BaseDir + edPath.Text, fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkPathTraversal) >= 1,
      'TFileStream.Create + edPath.Text muss als Path-Traversal-Risk gemeldet werden');
  finally F.Free; end;
end;

procedure TTestPathTraversal.FileOpenWithLiteral_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(''C:\fixed\path.log'', fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      'Literal-only Path ist kein User-Input-Risk');
  finally F.Free; end;
end;

procedure TTestPathTraversal.FileStreamWithoutConcat_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(edPath.Text, fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // Heuristik braucht '+' - ohne Concat kein Finding (vermeidet
    // FP wenn das ganze Edit der intendierte File-Path ist).
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      'Ohne + ist Heuristik nicht aktiv (akzeptierter FN)');
  finally F.Free; end;
end;

procedure TTestPathTraversal.ConstWithTextSubstring_NotReported;
// FP-Fix (Real-World 2026-06-21): '.text' darf NICHT als Substring in
// 'MediaType.TEXT_HTML' matchen (rechts steht '_' = Identifier-Char).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: TFileStream;'#13#10 +
  'begin'#13#10 +
  '  s := TFileStream.Create(BaseDir + MediaType.TEXT_HTML, fmOpenRead);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPathTraversal),
      '.TEXT_HTML ist kein User-Input-Token (Wortgrenze)');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPathTraversal);

end.
