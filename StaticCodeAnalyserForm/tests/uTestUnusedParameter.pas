unit uTestUnusedParameter;

// Tests fuer den TUnusedParameterDetector (fkUnusedParameter).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnusedParameter = class
  public
    // ---- Positive ---------------------------------------------------------
    [Test] procedure Param_DeclaredNeverUsed_Reported;
    [Test] procedure Param_TwoParamsOneUnused_OneReported;
    [Test] procedure Param_MultipleUnusedInSameMethod_AllReported;

    // ---- Negative / Skip-Regeln -------------------------------------------
    [Test] procedure Param_Used_NoFinding;
    [Test] procedure Param_OverrideMethod_AllParamsSkipped;
    [Test] procedure Param_EventHandlerSender_Skipped;
    [Test] procedure Param_UnderscorePrefix_Skipped;
    [Test] procedure Param_VirtualMethod_AllParamsSkipped;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Param_Finding_KindAndSeverity;
    [Test] procedure Param_Finding_MissingVarMentionsParamName;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnusedParameter.Param_DeclaredNeverUsed_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(LogLevel: Integer);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_TwoParamsOneUnused_OneReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Data: Integer; LogLevel: Integer);'#13#10 +
  'begin Bar(Data); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_MultipleUnusedInSameMethod_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Integer; b: Integer; c: Integer);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_Used_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(LogLevel: Integer);'#13#10 +
  'begin Bar(LogLevel); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter));
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_OverrideMethod_AllParamsSkipped;
// override-Methode: Signatur ist von Basis-Klasse vorgegeben, Parameter
// auch wenn ungenutzt notwendig.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Run(LogLevel: Integer); override;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Run(LogLevel: Integer);'#13#10 +
  'begin Bar; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'override-Methoden werden geskippt (Signatur-Konformitaet)');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_EventHandlerSender_Skipped;
// Single-Sender:TObject = Event-Handler-Konvention. Sender wird oft
// nicht gebraucht und ist trotzdem Teil des Vertrags.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.ButtonClick(Sender: TObject);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Event-Handler mit Single-Sender-Param wird geskippt');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UnderscorePrefix_Skipped;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(_LogLevel: Integer);'#13#10 +
  'begin Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    '_-Prefix = intentionally unused -> Skip');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_VirtualMethod_AllParamsSkipped;
// virtual-Methoden duerfen von Subklassen ueberschrieben werden, die
// Parameter brauchen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Hook(Data: Integer); virtual;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Hook(Data: Integer);'#13#10 +
  'begin Bar; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'virtual-Methoden werden geskippt (Subklassen-Vertrag)');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(orphan: Integer);'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedParameter then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkUnusedParameter finding expected');
    Assert.AreEqual(fkUnusedParameter, Hit.Kind);
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_Finding_MissingVarMentionsParamName;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(orphan: Integer);'#13#10 +
  'begin Bar; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnusedParameter then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'orphan');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedParameter);

end.
