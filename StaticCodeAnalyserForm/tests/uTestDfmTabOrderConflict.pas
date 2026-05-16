unit uTestDfmTabOrderConflict;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmTabOrderConflict = class
  public
    [Test] procedure Test_TwoSiblings_SameTabOrder_Detected;
    [Test] procedure Test_ThreeSiblings_TwoWithSameTabOrder_TwoReported;
    [Test] procedure Test_UniqueTabOrders_NoFinding;
    [Test] procedure Test_DifferentParents_SameTabOrder_NoFinding;
    [Test] procedure Test_NoTabOrderProperty_NoFinding;
    [Test] procedure Test_OnlyOneChild_NoFinding;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsValueAndParent;

    // --- Mehr Varianten ---
    [Test] procedure Test_FourSiblings_AllSameTabOrder_FourReported;
    [Test] procedure Test_TabOrderInDifferentTypes_Detected;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmTabOrderConflict;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmTabOrderConflictDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

procedure TTestDfmTabOrderConflict.Test_TwoSiblings_SameTabOrder_Detected;
const DFM =
  'object Form: TForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object a: TEdit TabOrder = 0 end'#13#10 +
  '    object b: TEdit TabOrder = 0 end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(2, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_ThreeSiblings_TwoWithSameTabOrder_TwoReported;
// 3 Siblings: zwei mit TabOrder=0 (Konflikt), einer mit TabOrder=1 -
// nur die zwei Konfliktpartner werden gemeldet.
const DFM =
  'object Form: TForm'#13#10 +
  '  object a: TEdit TabOrder = 0 end'#13#10 +
  '  object b: TEdit TabOrder = 0 end'#13#10 +
  '  object c: TEdit TabOrder = 1 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(2, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_UniqueTabOrders_NoFinding;
const DFM =
  'object Form: TForm'#13#10 +
  '  object a: TEdit TabOrder = 0 end'#13#10 +
  '  object b: TEdit TabOrder = 1 end'#13#10 +
  '  object c: TEdit TabOrder = 2 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(0, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_DifferentParents_SameTabOrder_NoFinding;
// TabOrder ist nur innerhalb eines Parents relevant. Zwei Edits in
// unterschiedlichen Panels duerfen beide TabOrder=0 haben.
const DFM =
  'object Form: TForm'#13#10 +
  '  object pnlA: TPanel'#13#10 +
  '    object a: TEdit TabOrder = 0 end'#13#10 +
  '  end'#13#10 +
  '  object pnlB: TPanel'#13#10 +
  '    object b: TEdit TabOrder = 0 end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(0, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_NoTabOrderProperty_NoFinding;
// Komponenten ohne TabOrder-Property sind nicht im Conflict-Game.
const DFM =
  'object Form: TForm'#13#10 +
  '  object a: TLabel end'#13#10 +
  '  object b: TLabel end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(0, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_OnlyOneChild_NoFinding;
const DFM =
  'object Form: TForm'#13#10 +
  '  object only: TEdit TabOrder = 0 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(0, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_Finding_KindAndSeverity;
const DFM =
  'object Form: TForm'#13#10 +
  '  object a: TEdit TabOrder = 0 end'#13#10 +
  '  object b: TEdit TabOrder = 0 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmTabOrderConflict, F[0].Kind);
    Assert.AreEqual(lsHint, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_Finding_MissingVarMentionsValueAndParent;
const DFM =
  'object Form: TForm'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object a: TEdit TabOrder = 3 end'#13#10 +
  '    object b: TEdit TabOrder = 3 end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, '3');
    Assert.Contains(F[0].MissingVar, 'pnl');
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_FourSiblings_AllSameTabOrder_FourReported;
// Vier Siblings, alle TabOrder=0 -> alle vier sind Konfliktpartner.
const DFM =
  'object Form: TForm'#13#10 +
  '  object a: TEdit TabOrder = 0 end'#13#10 +
  '  object b: TEdit TabOrder = 0 end'#13#10 +
  '  object c: TEdit TabOrder = 0 end'#13#10 +
  '  object d: TEdit TabOrder = 0 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(4, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

procedure TTestDfmTabOrderConflict.Test_TabOrderInDifferentTypes_Detected;
// Konflikt gilt typ-uebergreifend: TEdit + TComboBox + TButton mit
// identischer TabOrder kollidieren genau wie Edits untereinander.
const DFM =
  'object Form: TForm'#13#10 +
  '  object a: TEdit TabOrder = 2 end'#13#10 +
  '  object b: TComboBox TabOrder = 2 end'#13#10 +
  '  object c: TButton TabOrder = 2 end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(3, Count(F, fkDfmTabOrderConflict));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmTabOrderConflict);

end.
