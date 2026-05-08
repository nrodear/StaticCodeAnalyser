unit uTestCodeMetrics;

// Tests fuer Code-Metrik-Detektoren: LongParamList, MagicNumbers,
// LongMethod (Erweiterungen), DeepNesting (Erweiterungen).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- LongParamList (TLongParamListDetector) ----------------------------------------
  [TestFixture]
  TTestLongParamList = class
  public
    [Test] procedure LongParamList_FiveParams_NoFinding;
    [Test] procedure LongParamList_SixParams_ReportsHint;
    [Test] procedure LongParamList_TenParams_ReportsHint;
    [Test] procedure LongParamList_NoParams_NoFinding;
    [Test] procedure LongParamList_AllConstParams_StillCounted;
    [Test] procedure LongParamList_VarParams_StillCounted;
    [Test] procedure LongParamList_FunctionWithSeven_ReportsHint;
    [Test] procedure LongParamList_TwoMethodsBothLong_BothReported;
    [Test] procedure LongParamList_GroupedSameType_StillCounted;
    [Test] procedure LongParamList_MixedShortAndLong_OnlyLongReported;
  end;

  // ---- MagicNumbers (TMagicNumberDetector) -------------------------------------------
  [TestFixture]
  TTestMagicNumbers = class
  public
    [Test] procedure Magic_GreaterThanLargeLiteral_ReportsHint;
    [Test] procedure Magic_LessThanLargeLiteral_ReportsHint;
    [Test] procedure Magic_EqualsLargeLiteral_ReportsHint;
    [Test] procedure Magic_NotEqualsLargeLiteral_ReportsHint;
    [Test] procedure Magic_TrivialZero_NoFinding;
    [Test] procedure Magic_TrivialOne_NoFinding;
    [Test] procedure Magic_TrivialMinusOne_NoFinding;
    [Test] procedure Magic_TrivialHundred_NoFinding;
    [Test] procedure Magic_NoIfStatement_NoFinding;
    [Test] procedure Magic_TwoIfsBothMagic_BothReported;
    // Linke Boundary akzeptiert auch '(', ',', '[': '(Count>100)' wird erkannt
    [Test] procedure Magic_ParenthesisLeftBoundary_ReportsHint;
  end;

  // ---- LongMethod Erweiterungen ------------------------------------------------------
  [TestFixture]
  TTestLongMethodExt = class
  public
    [Test] procedure LongMethod_TenLineBody_NoFinding;
    [Test] procedure LongMethod_OnlyLineCountTooHigh_NoFinding;
    [Test] procedure LongMethod_OnlyStatementCountTooHigh_NoFinding;
    [Test] procedure LongMethod_TwoMethodsOneLong_OnlyLongReported;
    [Test] procedure LongMethod_EmptyBody_NoFinding;
    [Test] procedure LongMethod_LongCommentNoStatements_NoFinding;
    [Test] procedure LongMethod_BothThresholdsExceeded_ReportsHint;
  end;

  // ---- DeepNesting Erweiterungen -----------------------------------------------------
  [TestFixture]
  TTestDeepNestingExt = class
  public
    [Test] procedure DeepNesting_NoNesting_NoFinding;
    [Test] procedure DeepNesting_FourIfsExactlyAtLimit_NoFinding;
    [Test] procedure DeepNesting_FiveIfsOverLimit_ReportsHint;
    [Test] procedure DeepNesting_DeepForLoops_ReportsHint;
    [Test] procedure DeepNesting_DeepCases_ReportsHint;
    [Test] procedure DeepNesting_RepeatLoops_Counted;
    [Test] procedure DeepNesting_TwoMethodsOneDeep_OnlyDeepReported;
  end;

  // ---- CyclomaticComplexity (TCyclomaticComplexityDetector) --------------------------
  [TestFixture]
  TTestCyclomaticComplexity = class
  public
    [Test] procedure Cyclomatic_TrivialMethod_NoFinding;
    [Test] procedure Cyclomatic_SingleIf_NoFinding;
    [Test] procedure Cyclomatic_ElseDoesNotCount_NoFinding;
    [Test] procedure Cyclomatic_BooleanAndOrInCondition_Counted;
    [Test] procedure Cyclomatic_ManyIfs_OverLimit_ReportsHint;
    [Test] procedure Cyclomatic_CaseArmsCounted_OverLimit_ReportsHint;
    [Test] procedure Cyclomatic_ForWhileRepeat_Counted;
    [Test] procedure Cyclomatic_OnHandlerCounted_OverLimit_ReportsHint;
    [Test] procedure Cyclomatic_TryFinally_NotCounted_NoFinding;
    [Test] procedure Cyclomatic_TwoMethodsOneOver_OneFinding;
  end;

implementation

// =============================================================================
// LongParamList-Tests
// =============================================================================

procedure TTestLongParamList.LongParamList_FiveParams_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E: Integer);'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongParamList));
  finally F.Free; end;
end;

procedure TTestLongParamList.LongParamList_SixParams_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E, F: Integer);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_TenParams_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E, F, G, H, I, J: Integer);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_NoParams_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongParamList));
  finally F.Free; end;
end;

procedure TTestLongParamList.LongParamList_AllConstParams_StillCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(const A, B, C, D, E, F: Integer);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_VarParams_StillCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(var A, B, C: Integer; var D, E, F: string);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_FunctionWithSeven_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'function Calc(A, B, C, D, E, F, G: Integer): Integer;'#13#10+
  'begin Result := A; end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_TwoMethodsBothLong_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E, F: Integer); begin end;'#13#10+
  'procedure Bar(A, B, C, D, E, F, G: Integer); begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_GroupedSameType_StillCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C: Integer; D, E, F: string);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_MixedShortAndLong_OnlyLongReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Short(A: Integer); begin end;'#13#10+
  'procedure Long(A, B, C, D, E, F: Integer); begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

// =============================================================================
// MagicNumbers-Tests
// =============================================================================

procedure TTestMagicNumbers.Magic_GreaterThanLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X > 50 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_LessThanLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X < 200 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_EqualsLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X = 4711 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_NotEqualsLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X <> 999 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialZero_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X > 0 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialOne_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X >= 1 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialMinusOne_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X = -1 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialHundred_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X = 100 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_NoIfStatement_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var X: Integer;'#13#10+
  'begin X := 4711; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TwoIfsBothMagic_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X, Y: Integer);'#13#10+
  'begin'#13#10+
  '  if X > 50 then Exit;'#13#10+
  '  if Y < 200 then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_ParenthesisLeftBoundary_ReportsHint;
// '(Count>250)' ohne Whitespace zwischen '(' und Operator. Vor dem Fix
// in ExtractMagicNumber wurde nur ' >' als Vorgaenger akzeptiert -
// dieser Case wurde uebersehen.
// Achtung: 100 ist in IsTrivial-Liste (uMagicNumbers.pas) -> 250 verwenden
// damit der Detektor wirklich anschlaegt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Count: Integer);'#13#10+
  'begin'#13#10+
  '  if (Count>250) then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber),
    '(Count>250) ohne Spaces muss erkannt werden');
  finally F.Free; end;
end;

// =============================================================================
// LongMethod-Erweiterungen
// =============================================================================

procedure TTestLongMethodExt.LongMethod_TenLineBody_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var X: Integer;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  X := 2;'#13#10+
  '  X := 3;'#13#10+
  '  X := 4;'#13#10+
  '  X := 5;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_OnlyLineCountTooHigh_NoFinding;
// Body hat 60 Zeilen, aber nur 10 Statements (sonst alles Leerzeilen/Kommentare).
// Da BEIDE Schwellen ueberschritten sein muessen, kein Befund.
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  // 10 Statements
  for i := 1 to 10 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  // 55 leere Zeilen (Kommentare zaehlen nicht als statements)
  for i := 1 to 55 do
    SRC := SRC + '  // dummy comment line'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_OnlyStatementCountTooHigh_NoFinding;
// 40 Statements aber nur ~40 Zeilen - unter Zeilen-Schwelle (50).
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  for i := 1 to 40 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_TwoMethodsOneLong_OnlyLongReported;
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Short;'#13#10+
         'begin DoStuff; end;'#13#10+
         'procedure Long;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  for i := 1 to 60 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_EmptyBody_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_LongCommentNoStatements_NoFinding;
// Viele Kommentar-Zeilen, kein Code - keine Statements -> kein Befund.
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'begin'#13#10;
  for i := 1 to 70 do
    SRC := SRC + '  // ' + IntToStr(i)+ ' kommentar'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_BothThresholdsExceeded_ReportsHint;
// 60 Zeilen UND 60 statements - beide Schwellen ueberschritten.
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  for i := 1 to 60 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLongMethod) >= 1);
  finally F.Free; end;
end;

// =============================================================================
// DeepNesting-Erweiterungen
// =============================================================================

procedure TTestDeepNestingExt.DeepNesting_NoNesting_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  DoA;'#13#10+
  '  DoB;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting));
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_FourIfsExactlyAtLimit_NoFinding;
// MAX_DEPTH = 4, also genau 4 Ebenen ist OK.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    if B then'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting));
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_FiveIfsOverLimit_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    if B then'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          if E then'#13#10+
  '            DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_DeepForLoops_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var i, j, k, l, m: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 1 to 10 do'#13#10+
  '    for j := 1 to 10 do'#13#10+
  '      for k := 1 to 10 do'#13#10+
  '        for l := 1 to 10 do'#13#10+
  '          for m := 1 to 10 do'#13#10+
  '            DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_DeepCases_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  case A of'#13#10+
  '    1: case B of'#13#10+
  '         1: case C of'#13#10+
  '              1: case D of'#13#10+
  '                   1: case E of 1: DoIt; end;'#13#10+
  '                 end;'#13#10+
  '            end;'#13#10+
  '       end;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_RepeatLoops_Counted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  repeat'#13#10+
  '    repeat'#13#10+
  '      repeat'#13#10+
  '        repeat'#13#10+
  '          repeat'#13#10+
  '            DoIt;'#13#10+
  '          until X1;'#13#10+
  '        until X2;'#13#10+
  '      until X3;'#13#10+
  '    until X4;'#13#10+
  '  until X5;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_TwoMethodsOneDeep_OnlyDeepReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Shallow;'#13#10+
  'begin DoIt; end;'#13#10+
  'procedure Deep;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    if B then'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          if E then DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDeepNesting));
  finally F.Free; end;
end;

// =============================================================================
// CyclomaticComplexity-Tests
// =============================================================================
// Default-Schwelle ist 10 (Sonar/Checkstyle/PMD-Standard). Base = 1, jede
// Verzweigung +1. Tests sind so dimensioniert, dass sie deutlich UEBER bzw.
// UNTER der Schwelle liegen - so bleiben sie auch dann aussagekraeftig wenn
// jemand die Default-Schwelle in uSCAConsts veraendert.

procedure TTestCyclomaticComplexity.Cyclomatic_TrivialMethod_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  WriteLn(''hi'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCyclomaticComplexity));
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_SingleIf_NoFinding;
// Base 1 + if 1 = 2, weit unter Schwelle 10
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if a then b;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCyclomaticComplexity));
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_ElseDoesNotCount_NoFinding;
// 5 if/else = base 1 + 5 if = 6, NICHT 11. else darf nicht zaehlen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if a then b else c;'#13#10+
  '  if d then e else f;'#13#10+
  '  if g then h else i;'#13#10+
  '  if j then k else l;'#13#10+
  '  if m then n else o;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCyclomaticComplexity),
    '5x if/else = CC 6, soll nicht melden');
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_BooleanAndOrInCondition_Counted;
// Base 1 + 1 if + 5 and/or = 7. Mit weiteren if's deutlich ueber 10.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if (a and b) or (c and d) and (e or f) then x;'#13#10+
  '  if y then z;'#13#10+
  '  if y then z;'#13#10+
  '  if y then z;'#13#10+
  '  if y then z;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCyclomaticComplexity),
    'Boolean-Operatoren muessen mitzaehlen');
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_ManyIfs_OverLimit_ReportsHint;
// 11 if = base 1 + 11 = 12, ueber Schwelle 10
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if a1 then x; if a2 then x; if a3 then x; if a4 then x;'#13#10+
  '  if a5 then x; if a6 then x; if a7 then x; if a8 then x;'#13#10+
  '  if a9 then x; if a10 then x; if a11 then x;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCyclomaticComplexity));
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_CaseArmsCounted_OverLimit_ReportsHint;
// 11 case-arme = base 1 + 11 = 12
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  case x of'#13#10+
  '    1: a; 2: a; 3: a; 4: a; 5: a; 6: a;'#13#10+
  '    7: a; 8: a; 9: a; 10: a; 11: a;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCyclomaticComplexity),
    'Jeder case-arm zaehlt +1');
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_ForWhileRepeat_Counted;
// Base 1 + for + while + repeat + 8x if = 12
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  for i := 1 to 10 do x;'#13#10+
  '  while a do x;'#13#10+
  '  repeat x until b;'#13#10+
  '  if c1 then x; if c2 then x; if c3 then x; if c4 then x;'#13#10+
  '  if c5 then x; if c6 then x; if c7 then x; if c8 then x;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCyclomaticComplexity));
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_OnHandlerCounted_OverLimit_ReportsHint;
// Base 1 + 11 on-Handler = 12
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try x'#13#10+
  '  except'#13#10+
  '    on E1: Exception do x;'#13#10+
  '    on E2: Exception do x;'#13#10+
  '    on E3: Exception do x;'#13#10+
  '    on E4: Exception do x;'#13#10+
  '    on E5: Exception do x;'#13#10+
  '    on E6: Exception do x;'#13#10+
  '    on E7: Exception do x;'#13#10+
  '    on E8: Exception do x;'#13#10+
  '    on E9: Exception do x;'#13#10+
  '    on E10: Exception do x;'#13#10+
  '    on E11: Exception do x;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCyclomaticComplexity),
    'on-Handler zaehlen +1 wie if/case-arm');
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_TryFinally_NotCounted_NoFinding;
// 12 try/finally schachteln = base 1 + 0 = 1. try selbst zaehlt nicht.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try try try try try try try try try try try try'#13#10+
  '    x'#13#10+
  '  finally a; end; finally a; end; finally a; end; finally a; end;'#13#10+
  '  finally a; end; finally a; end; finally a; end; finally a; end;'#13#10+
  '  finally a; end; finally a; end; finally a; end; finally a; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCyclomaticComplexity),
    'try/finally selbst zaehlt nicht (Resource-Handling, kein Branch)');
  finally F.Free; end;
end;

procedure TTestCyclomaticComplexity.Cyclomatic_TwoMethodsOneOver_OneFinding;
// Eine triviale Methode + eine komplexe -> nur die komplexe wird gemeldet
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Trivial;'#13#10+
  'begin'#13#10+
  '  x;'#13#10+
  'end;'#13#10+
  'procedure TFoo.Complex;'#13#10+
  'begin'#13#10+
  '  if a1 then x; if a2 then x; if a3 then x; if a4 then x;'#13#10+
  '  if a5 then x; if a6 then x; if a7 then x; if a8 then x;'#13#10+
  '  if a9 then x; if a10 then x; if a11 then x;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkCyclomaticComplexity),
      'nur die komplexe Methode wird gemeldet');
    Assert.IsTrue(F[0].MethodName.EndsWith('Complex'),
      'gemeldete Methode endet auf Complex (nicht Trivial)');
  finally F.Free; end;
end;

end.
