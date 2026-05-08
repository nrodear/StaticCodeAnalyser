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

end.
