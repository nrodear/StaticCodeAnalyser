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
    [Test] procedure Param_MultiParamEventHandler_Skipped;
    [Test] procedure Param_UnderscorePrefix_Skipped;
    [Test] procedure Param_VirtualMethod_AllParamsSkipped;
    // Core-Audit 2026-07-18 (SCA054 Welle 1): bare/klammerloses 'inherited'
    // reicht Params implizit an den Parent weiter -> nicht ungenutzt.
    [Test] procedure Param_BareInherited_Skipped;
    [Test] procedure Param_InheritedNoParens_Skipped;
    [Test] procedure Param_InheritedWithExplicitArgs_StillReported;
    // Ist-Messung 2026-07-18: die zwei Parser-Blindstellen der SCA054-FP-Klasse
    [Test] procedure Param_UsedAsCaseSelector_NotReported;
    [Test] procedure Param_UsedOnlyInNestedProc_NotReported;
    [Test] procedure Param_UnusedDespiteNestedProc_StillReported;   // TP-Gegenprobe

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure Param_Finding_KindAndSeverity;
    [Test] procedure Param_Finding_MissingVarMentionsParamName;
    // Track B1 (2026-07-12): Write/Read-Statement-Call parst jetzt -> Param-Uses sichtbar
    [Test] procedure Param_UsedViaWriteCall_NotReported;
    [Test] procedure Param_KeywordNamedMethodUnused_Reported;
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

procedure TTestUnusedParameter.Param_MultiParamEventHandler_Skipped;
// FP-Fix (Real-World 2026-06-28): Multi-Param-Event-Handler (erster Param
// Sender) - weitere Params sind durch den Event-Typ vorgeschrieben und oft
// ungenutzt. Frueher nur Single-Sender erfasst -> hier 2 FPs (Sender + State).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.GridDrawCell(Sender: TObject; ACol: Integer; State: Integer);'#13#10 +
  'begin Bar(ACol); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Multi-Param-Event-Handler (erster Param Sender) wird komplett geskippt');
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

procedure TTestUnusedParameter.Param_UsedViaWriteCall_NotReported;
// Track B1 (2026-07-12): der Body ruft 'Write(Buf)' auf Statement-Ebene. Vor dem
// Parser-Fix wurde dieser keyword-Call NICHT als nkCall geparst -> Buf-Nutzung
// unsichtbar -> falsches 'unused parameter'. Jetzt parst 'Write(Buf)' als Call
// -> Buf ist benutzt -> kein Fund. (Ersetzt den entfernten IsKeywordRoutineName-Guard.)
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Send(Buf: Integer);'#13#10 +
  'begin Write(Buf); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Buf ist via Write(Buf)-Call benutzt - kein unused-parameter-Fund');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_KeywordNamedMethodUnused_Reported;
// Track B1 TP-Gegenprobe: eine keyword-benannte Methode 'Write' mit ECHT
// ungenutztem Param wird jetzt korrekt gemeldet (der fruehere Guard hatte diesen
// echten TP faelschlich unterdrueckt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Write(Buf: Integer);'#13#10 +
  'begin DoSomething; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
    'keyword-benannte Methode mit echt ungenutztem Param -> Fund (Guard entfernt)');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_BareInherited_Skipped;
// Core-Audit 2026-07-18 (SCA054 Welle 1, 5%-FP-Konzept): bare 'inherited;'
// reicht die aktuellen Parameter implizit an die Elternmethode weiter -> der
// Parameter ist NICHT ungenutzt (Parser: nkInherited mit leerem Namen).
// Groesste absolute FP-Klasse (~7.950).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Run(LogLevel: Integer);'#13#10 +
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'bare inherited; reicht Params weiter -> kein unused-Param');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_InheritedNoParens_Skipped;
// Klammerloses 'inherited Create;' reicht die aktuellen Parameter ebenfalls
// implizit weiter (Delphi-Semantik) -> nkInherited.Name='Create' ohne '('.
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create(AOwner: TComponent);'#13#10 +
  'begin inherited Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'klammerloses inherited Create reicht Params weiter -> kein unused-Param');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_InheritedWithExplicitArgs_StillReported;
// TP-Gegenprobe: 'inherited Run(0)' MIT expliziten Args reicht die aktuellen
// Parameter NICHT implizit weiter (nkInherited.Name enthaelt '(') -> ein hier
// ungenutzter Parameter bleibt ein echter Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Run(LogLevel: Integer);'#13#10 +
  'begin inherited Run(0); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
    'inherited Run(0) mit expliziten Args reicht nicht weiter -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UsedAsCaseSelector_NotReported;
// Ist-Messung 2026-07-18: Parameter, der NUR als case-Selektor gelesen wird
// ('case AWeight of'). Der Parser verwarf den Selektor frueher via
// SkipTo(tkKwOf) -> unsichtbar -> FP. Jetzt landet er in nkCaseStmt.TypeRef
// und zaehlt als Nutzung (CollectAllTokens).
const SRC =
  'unit t; implementation'#13#10 +
  'function Map(AWeight: Integer): string;'#13#10 +
  'begin'#13#10 +
  '  case AWeight of'#13#10 +
  '    1: Result := ''thin'';'#13#10 +
  '    2: Result := ''bold'';'#13#10 +
  '  else Result := ''normal'';'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'case-Selektor ist eine Nutzung des Parameters');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UsedOnlyInNestedProc_NotReported;
// Ist-Messung 2026-07-18: Parameter wird NUR in einer nested proc gelesen.
// Der Parser verwirft nested-Bodies (nkNestedRange-Marker bleibt) -> frueher
// FP. Jetzt scannt der Detektor die Marker-Ranges in der gestrippten Quelle.
// FindingsOfFile noetig (echte Datei -> AcquireLines).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer(AStream: TObject);'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '    Process(AStream);'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedParameter),
    'Nutzung in nested proc (nkNestedRange-Quelle) ist eine Nutzung');
  finally F.Free; end;
end;

procedure TTestUnusedParameter.Param_UnusedDespiteNestedProc_StillReported;
// TP-Gegenprobe: Methode HAT eine nested proc, aber der Parameter kommt darin
// NICHT vor -> bleibt ein echter unused-Param-Fund (Fallback matcht nicht).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Outer(AOrphan: Integer);'#13#10 +
  '  procedure Inner;'#13#10 +
  '  begin'#13#10 +
  '    DoStuff;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Inner;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnusedParameter),
    'Param ohne Vorkommen in der nested-Range bleibt ungenutzt -> Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnusedParameter);

end.
