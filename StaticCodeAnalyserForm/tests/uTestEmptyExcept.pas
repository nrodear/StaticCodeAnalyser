unit uTestEmptyExcept;

// Tests fuer den TEmptyExceptDetector2 (Basis und Erweiterungen).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- EmptyExcept (TEmptyExceptDetector2) -------------------------------------------
  [TestFixture]
  TTestEmptyExcept = class
  public
    [Test] procedure EmptyExcept_NoCode_ReportsWarning;
    [Test] procedure EmptyExcept_CommentOnly_ReportsWarning;
    [Test] procedure EmptyExcept_WithHandler_NoFinding;
    [Test] procedure EmptyExcept_WithRaise_NoFinding;
    [Test] procedure EmptyExcept_MultipleBlocks_AllReported;
  end;

  // ---- EmptyExcept Erweiterungen -----------------------------------------------------
  [TestFixture]
  TTestEmptyExceptExt = class
  public
    [Test] procedure EmptyExcept_OnlyWhitespace_ReportsWarning;
    [Test] procedure EmptyExcept_NestedTryExcept_AllReported;
    [Test] procedure EmptyExcept_InsideTryFinally_Reported;
    [Test] procedure EmptyExcept_TwoExceptBlocks_BothReported;
    [Test] procedure EmptyExcept_WithOnAndEmptyOther_OnlyEmptyReported;
  end;

implementation

{ ---- EmptyExcept ---- }

procedure TTestEmptyExcept.EmptyExcept_NoCode_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyExcept),
      'Leerer except-Block – Warning');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_CommentOnly_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '    // leer – ignorieren'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyExcept),
      'Nur Kommentar im except – trotzdem Warning');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_WithHandler_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '    on E: Exception do'#13#10+
  '      LogError(E.Message);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyExcept),
      'Handler vorhanden – kein Befund');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_WithRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '    raise;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyExcept),
      'raise im except – kein Befund');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_MultipleBlocks_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try DoA; except end;'#13#10+
  '  try DoB; except end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkEmptyExcept),
      'Zwei leere except-Blöcke – beide gemeldet');
  finally F.Free; end;
end;

// =============================================================================
// EmptyExcept-Erweiterungen
// =============================================================================

procedure TTestEmptyExceptExt.EmptyExcept_OnlyWhitespace_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try DoStuff'#13#10+
  '  except'#13#10+
  '     '#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_NestedTryExcept_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try DoStuff'#13#10+
  '    except'#13#10+
  '    end;'#13#10+
  '  except'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_InsideTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try DoStuff except end;'#13#10+
  '  finally'#13#10+
  '    Cleanup;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_TwoExceptBlocks_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try DoA except end;'#13#10+
  '  try DoB except end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_WithOnAndEmptyOther_OnlyEmptyReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try DoA except on E: Exception do Log(E.Message); end;'#13#10+
  '  try DoB except end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

end.
