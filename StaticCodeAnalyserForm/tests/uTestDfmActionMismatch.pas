unit uTestDfmActionMismatch;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmActionMismatch = class
  public
    [Test] procedure Test_ActionAndOnClick_Detected;
    [Test] procedure Test_OnlyAction_NoFinding;
    [Test] procedure Test_OnlyOnClick_NoFinding;
    [Test] procedure Test_EmptyAction_NoFinding;
    [Test] procedure Test_NestedComponent_StillDetected;
    [Test] procedure Test_Finding_KindAndSeverity;
    [Test] procedure Test_Finding_MissingVarMentionsBoth;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uDfmParser, uComponentGraph,
  uDfmActionMismatch;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var Parser: TDfmParser; Graph: TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try TDfmActionMismatchDetector.Analyze(Graph, 'test.dfm', Result);
    finally Graph.Free; end;
  finally Parser.Free; end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var X: TLeakFinding;
begin
  Result := 0;
  for X in F do if X.Kind = K then Inc(Result);
end;

procedure TTestDfmActionMismatch.Test_ActionAndOnClick_Detected;
const DFM =
  'object F: TF'#13#10 +
  '  object b: TButton'#13#10 +
  '    Action = ActSave'#13#10 +
  '    OnClick = btnSaveClick'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(1, Count(F, fkDfmActionMismatch));
  finally F.Free; end;
end;

procedure TTestDfmActionMismatch.Test_OnlyAction_NoFinding;
const DFM = 'object F: TF object b: TButton Action = ActSave end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(0, Count(F, fkDfmActionMismatch));
  finally F.Free; end;
end;

procedure TTestDfmActionMismatch.Test_OnlyOnClick_NoFinding;
const DFM = 'object F: TF object b: TButton OnClick = doClick end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(0, Count(F, fkDfmActionMismatch));
  finally F.Free; end;
end;

procedure TTestDfmActionMismatch.Test_EmptyAction_NoFinding;
// Wenn Action leer ist (DFM-Streamer schreibt das eigentlich nicht, aber
// pathologisch denkbar), liegt kein Konflikt vor.
const DFM =
  'object F: TF'#13#10 +
  '  object b: TButton'#13#10 +
  '    Action = '#13#10 +                  // leere Identifier-Property
  '    OnClick = doClick'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(0, Count(F, fkDfmActionMismatch));
  finally F.Free; end;
end;

procedure TTestDfmActionMismatch.Test_NestedComponent_StillDetected;
const DFM =
  'object F: TF'#13#10 +
  '  object pnl: TPanel'#13#10 +
  '    object b: TButton Action = A OnClick = C end'#13#10 +
  '  end'#13#10 +
  'end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try Assert.AreEqual(1, Count(F, fkDfmActionMismatch));
  finally F.Free; end;
end;

procedure TTestDfmActionMismatch.Test_Finding_KindAndSeverity;
const DFM =
  'object F: TF object b: TButton Action = A OnClick = C end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.AreEqual(fkDfmActionMismatch, F[0].Kind);
    Assert.AreEqual(lsWarning, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmActionMismatch.Test_Finding_MissingVarMentionsBoth;
const DFM =
  'object F: TF object btnSave: TButton Action = ActSave OnClick = btnSaveClick end end';
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(DFM);
  try
    Assert.Contains(F[0].MissingVar, 'btnSave');
    Assert.Contains(F[0].MissingVar, 'ActSave');
    Assert.Contains(F[0].MissingVar, 'btnSaveClick');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmActionMismatch);

end.
