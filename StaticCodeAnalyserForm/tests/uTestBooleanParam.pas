unit uTestBooleanParam;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBooleanParam = class
  public
    [Test] procedure BoolParamUsedInIf_Reported;
    // Voll-Review 2026-09-12 (Blocker): P.Name traegt das
    // Modifier-Praefix - const/var/out-Parameter waren unsichtbar.
    [Test] procedure ConstBoolParamUsedInIf_Reported;
    [Test] procedure VarHandledParam_SkipGreiftTrotzModifier;
    [Test] procedure BoolParamPassedThrough_NotReported;
    [Test] procedure NoBoolParam_NotReported;
    [Test] procedure Setter_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Voll-Review 2026-09-12: die versprochene Handler-Ausnahme greift
    [Test] procedure EventHandlerCanClose_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestBooleanParam.BoolParamUsedInIf_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SendMsg(const M: string; IsError: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if IsError then'#13#10 +
  '    NotifyRed(M)'#13#10 +
  '  else'#13#10 +
  '    NotifyBlack(M);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBooleanParam) >= 1);
  finally F.Free; end;
end;

procedure TTestBooleanParam.ConstBoolParamUsedInIf_Reported;
// Identisch zum Kernmuster, nur mit const - der uebliche Stil. Vor dem
// Fix war IdentLow='const iserror', das in keiner if-Bedingung
// vorkommt: null Funde fuer den Normalfall des eigenen Patterns.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SendMsg(const M: string; const IsError: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if IsError then'#13#10 +
  '    NotifyRed(M)'#13#10 +
  '  else'#13#10 +
  '    NotifyBlack(M);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkBooleanParam) >= 1,
    'const-Boolean-Parameter mit internem Branching muss melden');
  finally F.Free; end;
end;

procedure TTestBooleanParam.VarHandledParam_SkipGreiftTrotzModifier;
// Die Gegenrichtung desselben Fixes: der Handled-Skip verglich gegen
// den vollen Namen 'var handled' und griff nie - ein var Handled
// haette (nach dem Modifier-Fix) faelschlich gemeldet, wenn der Skip
// nicht ebenfalls am bereinigten Bezeichner haengt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure OnClose(Sender: TObject; var Handled: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if Handled then'#13#10 +
  '    Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam),
    'Handled ist API-Konvention - der Skip muss auch mit var greifen');
  finally F.Free; end;
end;

procedure TTestBooleanParam.BoolParamPassedThrough_NotReported;
// Bool wird nur weitergegeben - kein internes Branching -> kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SetVisible(V: Boolean);'#13#10 +
  'begin'#13#10 +
  '  DoSomething(V);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam));
  finally F.Free; end;
end;

procedure TTestBooleanParam.NoBoolParam_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(N: Integer);'#13#10 +
  'begin'#13#10 +
  '  if N > 0 then DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam));
  finally F.Free; end;
end;

procedure TTestBooleanParam.Setter_NotReported;
// Property-Setter mit Boolean-Param ist Konvention - kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.SetEnabled(Value: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if Value then DoEnable else DoDisable;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam));
  finally F.Free; end;
end;

procedure TTestBooleanParam.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(IsError: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if IsError then DoA else DoB;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkBooleanParam then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkBooleanParam finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestBooleanParam.EventHandlerCanClose_NotReported;
// Voll-Review 2026-09-12 (Posten 45): der Unit-Kopf verspricht die
// Event-Handler-Ausnahme seit jeher, implementiert war sie nicht -
// zufaellig maskiert vom Modifier-Bug ('var canclose' kam im
// Vollnamen-Vergleich nie in einer if-Bedingung vor). Nach dem
// Modifier-Fix wuerde FormCloseQuery(Sender: TObject; var CanClose:
// Boolean) mit 'if CanClose ...' als Flag-API-Smell gemeldet, obwohl
// die Signatur ein fremder VCL-Vertrag ist ('canclose' steht nicht in
// der Namens-Skip-Liste). Jetzt haelt das Signatur-Gate
// (TDetectorUtils.IsEventHandlerSignature) das Versprechen ein.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TForm1 = class'#13#10 +
  '  private'#13#10 +
  '    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);'#13#10 +
  'begin'#13#10 +
  '  if CanClose then'#13#10 +
  '    Speichere;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanParam),
    'Sender-Signatur ist ein fremder VCL-Vertrag - CanClose ist keine ' +
    'selbstgewaehlte Flag-API');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBooleanParam);

end.
