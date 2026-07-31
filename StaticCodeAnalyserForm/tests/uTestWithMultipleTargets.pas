unit uTestWithMultipleTargets;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWithMultipleTargets = class
  public
    [Test] procedure WithTwoTargets_Reported;
    [Test] procedure WithThreeTargets_Reported;
    [Test] procedure WithSingleTarget_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Klammer-Gate (Real-World-Audit 2026-07-31): Kommas in Argument-,
    // Index- und Typargumentlisten sind KEINE Target-Trenner.
    [Test] procedure WithCallMultipleArgs_NotReported;
    [Test] procedure WithCallArgsAcrossLines_NotReported;
    [Test] procedure WithIndexedTwoDim_NotReported;
    [Test] procedure WithGenericTypeArgs_NotReported;
    [Test] procedure WithStringLiteralComma_NotReported;
    // TP-Gegenproben: echtes Multi-Target hinter Klammerkonstrukten.
    [Test] procedure WithCallResultAndSecondTarget_Reported;
    [Test] procedure WithIndexedAndSecondTarget_Reported;
    [Test] procedure WithGenericAndSecondTarget_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestWithMultipleTargets.WithTwoTargets_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with Form1, List1 do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithThreeTargets_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with A, B, C do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithSingleTarget_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with Form1 do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with A, B do DoStuff;'#13#10 +
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
      if Fnd.Kind = fkWithMultipleTargets then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkWithMultipleTargets finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithCallMultipleArgs_NotReported;
// FP-Klasse 1 (8326 Korpus-Funde): EIN Ziel = Funktionsergebnis, die Kommas
// gehoeren zur Argumentliste. Ohne Klammer-Gate meldet die Regex hier.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with CL.AddInterface(CL.FindInterface(''IOTANotifier''), IOTAFoo, ''X'') do'#13#10 +
  '    RegisterMethod;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithCallArgsAcrossLines_NotReported;
// Gleiche Klasse, aber die Argumentliste laeuft ueber den Zeilenumbruch -
// die Regex matcht mehrzeilig, das Gate muss also ueber #10 hinweg zaehlen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with CL.AddInterface(AItem,'#13#10 +
  '    BItem) do'#13#10 +
  '    RegisterMethod;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithIndexedTwoDim_NotReported;
// FP-Klasse 2 (62 Korpus-Funde): zweidimensionaler Index, EIN Ziel.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with Grid.Cells[Col, Row] do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithGenericTypeArgs_NotReported;
// FP-Klasse 3: das Komma trennt Typargumente, nicht Targets.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with TDictionary<string, Integer>.Create do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithStringLiteralComma_NotReported;
// Das Komma im String-Literal ist beim Strip schon Leerzeichen - gemeldet
// wurde bisher trotzdem, wegen des ZWEITEN Arguments. Ein Ziel, kein Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with MakeItem(''a,b'', X) do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithMultipleTargets));
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithCallResultAndSecondTarget_Reported;
// TP-Gegenprobe: Argument-Kommas UND ein echtes zweites Target. Der Fund
// muss bleiben - inklusive unveraenderter Fundzeile (Monotonie-Anker).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with GetForm(A, B), Query1 do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1,
      'echtes zweites Target darf nicht stillgestellt werden');
    Hit := TFindingHelper.FirstOf(F, fkWithMultipleTargets);
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'GetForm'), Hit.LineNumber);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithIndexedAndSecondTarget_Reported;
// TP-Gegenprobe: Index-Kommas UND ein echtes zweites Target.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with Grid.Cells[Col, Row], Canvas do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1);
  finally F.Free; end;
end;

procedure TTestWithMultipleTargets.WithGenericAndSecondTarget_Reported;
// TP-Gegenprobe: Typargument-Kommas UND ein echtes zweites Target.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with TDictionary<string, Integer>.Create, List1 do'#13#10 +
  '    DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkWithMultipleTargets) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWithMultipleTargets);

end.
