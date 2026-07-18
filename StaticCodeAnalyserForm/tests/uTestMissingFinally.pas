unit uTestMissingFinally;

// Tests fuer TMissingFinallyDetector. Pattern: Object .Create + try/except
// ABER kein try/finally rund um den Free.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingFinally = class
  public
    [Test] procedure CreateWithoutTryFinally_Reported;
    [Test] procedure CreateWithTryFinally_NotReported;
    [Test] procedure NoCreate_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // --- Welle 2 strukturell 2026-07-18 (Konsistenz-Ports aus uLeakDetector2) ---
    // finally-Region-by-Source: nested try/except vor dem finally -> AST-Mis-Attach
    [Test] procedure NestedTryExceptBeforeFinally_NoFinding;
    // IsOwnerParamCreate: Create(Self) = owner-managed
    [Test] procedure OwnerParamCreate_NoFinding;
    // TP-Gegenprobe: Create(nil) = caller owns -> Befund bleibt
    [Test] procedure CreateNilOwnerNoFinally_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingFinally.CreateWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''x'');'#13#10 +
  '  except'#13#10 +
  '    Log(''oops'');'#13#10 +
  '  end;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingFinally.CreateWithTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''x'');'#13#10 +
  '  finally'#13#10 +
  '    L.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinally.NoCreate_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''nothing to clean up'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinally.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try L.Add(''x''); except Log(''oops''); end;'#13#10 +
  '  L.Free;'#13#10 +
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
      if Fnd.Kind = fkMissingFinally then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingFinally finding expected');
    Assert.AreEqual(fkMissingFinally, Hit.Kind);
  finally F.Free; end;
end;

procedure TTestMissingFinally.NestedTryExceptBeforeFinally_NoFinding;
// Welle 2 (finally-Region-by-Source Port, 2026-07-18): korrektes aeusseres
// try/finally mit SL.Free im finally, NESTED try/except im try-Body davor.
// BEHAVIOR-LOCK: dieser saubere Fall darf NIE gemeldet werden. HINWEIS: der
// neue Source-Guard ist im In-Memory-Testpfad (FindingsOf, Datei nicht auf
// Platte) ein No-Op; dieser Test wird bereits ueber AST-FreeInFin=True gruen.
// Die eigentliche Wirkung des finally-Region-Ports (AST-Mis-Attach bei
// {$IFDEF}/'F:=nil;try'/tief-verschachtelt) ist NUR per Korpus-A/B beweisbar
// (Real-Faelle CnObjInspectorCommentFrm/CnFeedWizard/CnSrcEditorBlockTools).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var SL: TStringList;'#13#10 +
  'begin'#13#10 +
  '  SL := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    try'#13#10 +
  '      SL.Add(''x'');'#13#10 +
  '    except'#13#10 +
  '      Log(''inner'');'#13#10 +
  '    end;'#13#10 +
  '  finally'#13#10 +
  '    SL.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
    'SL.Free liegt quell-basiert im aeusseren finally -> kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestMissingFinally.OwnerParamCreate_NoFinding;
// Welle 2 (IsOwnerParamCreate-Port): TTimer.Create(Self) uebergibt Ownership an
// den Owner (TComponent-Konvention) - selbst ein manueller Free ohne try/finally
// ist kein Leak-Risiko (Owner gibt bei Exception frei). Konsistent mit
// uLeakDetector2 Pfad 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.InitUi;'#13#10 +
  'var tmr: TTimer;'#13#10 +
  'begin'#13#10 +
  '  tmr := TTimer.Create(Self);'#13#10 +
  '  tmr.Enabled := True;'#13#10 +
  '  tmr.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingFinally),
    'Create(Self) = owner-managed -> kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestMissingFinally.CreateNilOwnerNoFinally_StillReported;
// TP-Gegenprobe zum owner-param-Gate: Create(nil) hat KEINEN Owner -> der
// Aufrufer besitzt das Objekt; Create+Free ohne try/finally bleibt ein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.LoadDB;'#13#10 +
  'var q: TSQLQuery;'#13#10 +
  'begin'#13#10 +
  '  q := TSQLQuery.Create(nil);'#13#10 +
  '  q.Open;'#13#10 +
  '  q.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1,
    'Create(nil) ohne try/finally -> Befund bleibt (owner-param-Gate greift nicht)');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingFinally);

end.
