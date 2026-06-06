unit uTestTodoComment;

// Tests fuer den TTodoCommentDetector (filebasiert).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- TodoComment (TTodoCommentDetector) - filebasiert ------------------------------
  [TestFixture]
  TTestTodoComment = class
  public
    [Test] procedure Todo_LineComment_ReportsHint;
    [Test] procedure Todo_FixmeMarker_ReportsHint;
    [Test] procedure Todo_HackMarker_ReportsHint;
    [Test] procedure Todo_XxxMarker_ReportsHint;
    [Test] procedure Todo_BraceComment_ReportsHint;
    [Test] procedure Todo_MultilineBraceComment_ReportsHint;
    [Test] procedure Todo_TodoInsideStringLiteral_NoFinding;
    [Test] procedure Todo_TodoAsIdentifier_NoFinding;
    [Test] procedure Todo_LowercaseMarker_StillReported;
    [Test] procedure Todo_NoMarker_NoFinding;
  end;

implementation

// =============================================================================
// TodoComment-Tests (filebasiert via FindingsOfFile)
// =============================================================================

procedure TTestTodoComment.Todo_LineComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// TODO: Tabelle persistieren'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_FixmeMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// FIXME: race condition'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_HackMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// HACK: workaround fuer Bug'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_XxxMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// XXX: muss noch geklaert werden'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_BraceComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '{ TODO: refactoring noetig }'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_MultilineBraceComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '{'#13#10+
  '  FIXME: das hier muss neu gebaut werden'#13#10+
  '  weil...'#13#10+
  '}'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_TodoInsideStringLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := ''TODO marker im String''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_TodoAsIdentifier_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var TodoList: Integer;'#13#10+
  'begin TodoList := 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_LowercaseMarker_StillReported;
const SRC =
  'unit t; implementation'#13#10+
  '// todo: kleinschreibung'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_NoMarker_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  '// gewoehnlicher Kommentar'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

end.
