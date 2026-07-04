unit uTestUnusedLocal;

// Tests fuer den TUnusedLocalDetector (fkUnusedLocalVar).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedLocal = class
  public
    // ---- Positive ---------------------------------------------------------
    [Test] procedure Local_DeclaredNeverUsed_Reported;
    [Test] procedure Local_TwoUnusedVars_BothReported;
    [Test] procedure Local_MultipleHitsInSameMethod_AllReported;

    // ---- Negative ---------------------------------------------------------
    [Test] procedure Local_UsedAsAssignTarget_NoFinding;
    [Test] procedure Local_UsedInExpression_NoFinding;
    [Test] procedure Local_UnderscorePrefix_Skipped;
    [Test] procedure Local_UsedInCondition_NoFinding;

    // ---- Edge -------------------------------------------------------------
    [Test] procedure Local_NameAsSubstring_DoesNotCount;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Local_Finding_KindAndSeverity;
    [Test] procedure Local_Finding_MissingVarMentionsVarName;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnusedLocal.Local_DeclaredNeverUsed_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_TwoUnusedVars_BothReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_MultipleHitsInSameMethod_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedAsAssignTarget_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin x := 42; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedInExpression_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin Bar(x); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UnderscorePrefix_Skipped;
// `_var` ist Konvention fuer "intentionally unused".
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var _unused: Integer;'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_UsedInCondition_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin if x > 0 then Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedLocalVar));
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_NameAsSubstring_DoesNotCount;
// `x` als Substring von `xLength` darf NICHT als Referenz zaehlen
// (Wortgrenze ist Pflicht).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const xLength: Integer);'#13#10 +
  'var x: Integer;'#13#10 +
  'begin Bar(xLength); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedLocalVar),
    'x ist ungenutzt; xLength ist Parameter und matched nicht als Wort');
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var orphan: Integer;'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedLocalVar then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkUnusedLocalVar finding expected');
    Assert.AreEqual(fkUnusedLocalVar, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestUnusedLocal.Local_Finding_MissingVarMentionsVarName;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var orphan: Integer;'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedLocalVar then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'orphan');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedLocal);

end.
