unit uTestLengthUnderflow;

// Tests fuer den TLengthUnderflowDetector (file-basiert).
//
// Schwelle: MIN_OFFSET_TO_FLAG = 2 - `Length(s) - 1` ist das gaengige
// `0 to Length-1` Loop-Idiom (mit -1 als Endgrenze ist es 0 Iterationen
// bei leerem String, also harmlos). Ab `- 2` wird's verdaechtig.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLengthUnderflow = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure Length_MinusTwo_Reported;
    [Test] procedure Length_MinusFour_Reported;
    [Test] procedure DotCount_MinusThree_Reported;
    [Test] procedure DotLength_MinusFive_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure Length_MinusOne_LoopIdiom_NoFinding;
    [Test] procedure Length_Plus_NoFinding;
    [Test] procedure InStringLiteral_NotDetected;
    [Test] procedure InLineComment_NotDetected;
    [Test] procedure Identifier_LengthMinusX_NotMatched;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Length_Finding_KindAndSeverity;
    [Test] procedure Length_MultipleHitsInSameMethod_AllReported;
    [Test] procedure Length_TwoHitsOnSameLine_BothReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLengthUnderflow.Length_MinusTwo_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Length(s) - 2;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Length_MinusFour_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'begin'#13#10 +
  '  Move(s[Length(s) - 4], buf, 4);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.DotCount_MinusThree_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TList);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := L.Count - 3;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.DotLength_MinusFive_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: TSomeString);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := s.Length - 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Length_MinusOne_LoopIdiom_NoFinding;
// 0 to Length(s) - 1 ist das idiomatische 0-basierte Loop-Pattern.
// -1 = MIN_OFFSET_TO_FLAG - 1 -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to Length(s) - 1 do Bar(s[i]);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Length_Plus_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Length(s) + 10;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.InStringLiteral_NotDetected;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := ''Length(x) - 3'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.InLineComment_NotDetected;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // i := Length(s) - 3;'#13#10 +
  '  Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Identifier_LengthMinusX_NotMatched;
// `xLength` ist Substring von Length, aber kein Length-Aufruf - Wortgrenze.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const xLength: Integer);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := xLength - 3;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLengthUnderflow));
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Length_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Length(s) - 3;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkLengthUnderflow then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkLengthUnderflow finding expected');
    Assert.AreEqual(fkLengthUnderflow, Hit.Kind);
    Assert.AreEqual(lsHint,            Hit.Severity);
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Length_MultipleHitsInSameMethod_AllReported;
// Zwei Length-2-Subtraktionen in derselben Methode -> beide werden gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s, t: string);'#13#10 +
  'var i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Length(s) - 3;'#13#10 +
  '  j := Length(t) - 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkLengthUnderflow),
      'Zwei Underflow-Hits in derselben Methode -> 2 Findings');
  finally F.Free; end;
end;

procedure TTestLengthUnderflow.Length_TwoHitsOnSameLine_BothReported;
// Regression: vor dem Off-by-One-Fix an der LinePos-Vorschaltung sprang
// der Scanner ein Zeichen zu weit nach jedem Treffer und konnte direkt-
// angrenzende Length(...)-N-Ausdruecke auf derselben Zeile uebersehen.
// Hier zwei Treffer in einem zusammengesetzten Ausdruck.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s, t: string);'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := Length(s) - 2 + Length(t) - 3;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkLengthUnderflow),
      'Zwei Underflows in derselben Zeile -> beide Findings');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLengthUnderflow);

end.
