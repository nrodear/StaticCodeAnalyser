unit uTestConfidenceFilter;

// Tests fuer das Confidence-Feature: TLeakFinding.Confidence-Default,
// ParseConfidence/ConfidenceName und den Post-Filter TConfidenceFilter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConfidenceFilter = class
  public
    // ---- Default / Helpers ----
    [Test] procedure NewFinding_DefaultsToHigh;
    [Test] procedure ParseConfidence_KnownValues;
    [Test] procedure ParseConfidence_UnknownUsesDefault;
    [Test] procedure ConfidenceName_RoundTrip;
    // ---- A.1 Confidence-Audit ----
    [Test] procedure KindDefaultConfidence_BugKindsAreHigh;
    [Test] procedure KindDefaultConfidence_MetricsAreMedium;
    [Test] procedure KindDefaultConfidence_PatternMatchersAreMedium;
    [Test] procedure KindDefaultConfidence_HardenedHeuristicsAreLow;
    [Test] procedure SetKind_AppliesKindDefaultConfidence;
    // ---- Filter ----
    [Test] procedure Medium_DropsLowOnly;
    [Test] procedure Low_IsNoOp;
    [Test] procedure High_DropsLowAndMedium;
    [Test] procedure FileReadError_NeverFiltered;
    [Test] procedure EmptyList_NoCrash;
  end;

implementation

uses
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uConfidenceFilter;

function MakeFinding(K: TFindingKind; C: TFindingConfidence): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(K);
  Result.Confidence := C;
end;

{ ---- Default / Helpers ---- }

procedure TTestConfidenceFilter.NewFinding_DefaultsToHigh;
var F: TLeakFinding;
begin
  F := TLeakFinding.Create;
  try
    Assert.AreEqual<TFindingConfidence>(fcHigh, F.Confidence,
      'frischer Befund muss hochkonfident sein (kein Default-Filtering)');
  finally
    F.Free;
  end;
end;

procedure TTestConfidenceFilter.ParseConfidence_KnownValues;
begin
  Assert.AreEqual<TFindingConfidence>(fcLow,    ParseConfidence('low'));
  Assert.AreEqual<TFindingConfidence>(fcMedium, ParseConfidence('MEDIUM'));
  Assert.AreEqual<TFindingConfidence>(fcHigh,   ParseConfidence('  High '));
end;

procedure TTestConfidenceFilter.ParseConfidence_UnknownUsesDefault;
begin
  Assert.AreEqual<TFindingConfidence>(fcMedium, ParseConfidence('garbage'),
    'unbekannt -> Default fcMedium');
  Assert.AreEqual<TFindingConfidence>(fcHigh, ParseConfidence('', fcHigh),
    'leer -> expliziter Default');
end;

procedure TTestConfidenceFilter.ConfidenceName_RoundTrip;
begin
  Assert.AreEqual('low',    ConfidenceName(fcLow));
  Assert.AreEqual('medium', ConfidenceName(fcMedium));
  Assert.AreEqual('high',   ConfidenceName(fcHigh));
  // Name -> Parse -> Name ist stabil
  Assert.AreEqual<TFindingConfidence>(fcLow,
    ParseConfidence(ConfidenceName(fcLow)));
end;

{ ---- A.1 Confidence-Audit ---- }

procedure TTestConfidenceFilter.KindDefaultConfidence_BugKindsAreHigh;
// Struktureller Bug-Match -> fcHigh
begin
  Assert.AreEqual<TFindingConfidence>(fcHigh,
    KindDefaultConfidence(fkMemoryLeak));
  // fkUseAfterFree wurde 2026-06-28 auf fcLow demotet (~94% FP, CFG noetig) -
  // siehe KindDefaultConfidence_HardenedHeuristicsAreLow.
  Assert.AreEqual<TFindingConfidence>(fcHigh,
    KindDefaultConfidence(fkNilDeref));
  Assert.AreEqual<TFindingConfidence>(fcHigh,
    KindDefaultConfidence(fkFreeWithoutNil));
  Assert.AreEqual<TFindingConfidence>(fcHigh,
    KindDefaultConfidence(fkUnusedRoutine));
  Assert.AreEqual<TFindingConfidence>(fcHigh,
    KindDefaultConfidence(fkUnusedSuppression));
end;

procedure TTestConfidenceFilter.KindDefaultConfidence_MetricsAreMedium;
// Metrik-Schwellwerte sind heuristisch -> fcMedium
begin
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkLongMethod));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkLongParamList));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkCyclomaticComplexity));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkGodClass));
end;

procedure TTestConfidenceFilter.KindDefaultConfidence_PatternMatchersAreMedium;
// Pattern-/Heuristik-Detektoren -> fcMedium
begin
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkHardcodedSecret));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkHardcodedPath));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkTodoComment));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkCommentedOutCode));
  Assert.AreEqual<TFindingConfidence>(fcMedium,
    KindDefaultConfidence(fkMagicNumber));
end;

procedure TTestConfidenceFilter.KindDefaultConfidence_HardenedHeuristicsAreLow;
// Detector-Hardening 2026-06-28: Detektoren mit gemessener/struktureller hoher
// FP-Rate, die nur mit Cross-Unit-Index fixbar waeren, sind nach fcLow demotet
// -> raus aus dem Default-Profil (fcMedium-Schwelle), bleiben opt-in.
begin
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkCanBeClassMethod), 'SCA148 ~68% FP -> fcLow');
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkConstStringParameter), 'SCA170 ~26% FP + war fcHigh -> fcLow');
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkCanBeUnitPrivate), 'Single-File-Scope -> fcLow');
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkCanBeProtected));
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkCanBeStrictPrivate));
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkUnusedPublicMember), 'Single-File-Scope -> fcLow');
  // Bug-Detektoren mit >50% FP ohne billigen Vollfix (CFG/Cross-Unit noetig).
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkUseAfterFree), 'SCA134 ~94% FP -> fcLow');
  Assert.AreEqual<TFindingConfidence>(fcLow,
    KindDefaultConfidence(fkAbstractNotImpl), 'SCA135 ~79% FP -> fcLow');
end;

procedure TTestConfidenceFilter.SetKind_AppliesKindDefaultConfidence;
// SetKind muss Confidence aus KindDefaultConfidence ziehen - sonst landen
// neue fcMedium-Tags nie bei den Detektoren.
var F: TLeakFinding;
begin
  F := TLeakFinding.Create;
  try
    F.SetKind(fkLongMethod);
    Assert.AreEqual<TFindingConfidence>(fcMedium, F.Confidence,
      'SetKind soll fcMedium fuer Metrik-Kind setzen');

    F.SetKind(fkMemoryLeak);
    Assert.AreEqual<TFindingConfidence>(fcHigh, F.Confidence,
      'SetKind soll fcHigh fuer Bug-Kind setzen');
  finally
    F.Free;
  end;
end;

{ ---- Filter ---- }

procedure TTestConfidenceFilter.Medium_DropsLowOnly;
var
  L : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkMemoryLeak, fcLow));
    L.Add(MakeFinding(fkMemoryLeak, fcMedium));
    L.Add(MakeFinding(fkMemoryLeak, fcHigh));
    Dropped := TConfidenceFilter.ApplyToFindings(L, fcMedium);
    Assert.AreEqual<Integer>(1, Dropped, 'genau der fcLow-Befund faellt raus');
    Assert.AreEqual<Integer>(2, L.Count);
  finally
    L.Free;
  end;
end;

procedure TTestConfidenceFilter.Low_IsNoOp;
var
  L : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkMemoryLeak, fcLow));
    L.Add(MakeFinding(fkMemoryLeak, fcMedium));
    L.Add(MakeFinding(fkMemoryLeak, fcHigh));
    Dropped := TConfidenceFilter.ApplyToFindings(L, fcLow);
    Assert.AreEqual<Integer>(0, Dropped, 'fcLow-Schwelle filtert nichts');
    Assert.AreEqual<Integer>(3, L.Count);
  finally
    L.Free;
  end;
end;

procedure TTestConfidenceFilter.High_DropsLowAndMedium;
var
  L : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkMemoryLeak, fcLow));
    L.Add(MakeFinding(fkMemoryLeak, fcMedium));
    L.Add(MakeFinding(fkMemoryLeak, fcHigh));
    Dropped := TConfidenceFilter.ApplyToFindings(L, fcHigh);
    Assert.AreEqual<Integer>(2, Dropped, 'fcLow + fcMedium raus');
    Assert.AreEqual<Integer>(1, L.Count);
    Assert.AreEqual<TFindingConfidence>(fcHigh, L[0].Confidence);
  finally
    L.Free;
  end;
end;

procedure TTestConfidenceFilter.FileReadError_NeverFiltered;
var
  L : TObjectList<TLeakFinding>;
  Dropped : Integer;
begin
  // fkFileReadError ist ein Diagnose-Befund und darf nie unterdrueckt
  // werden - auch nicht bei fcLow und strenger Schwelle.
  L := TObjectList<TLeakFinding>.Create(True);
  try
    L.Add(MakeFinding(fkFileReadError, fcLow));
    L.Add(MakeFinding(fkMemoryLeak,    fcLow));
    Dropped := TConfidenceFilter.ApplyToFindings(L, fcHigh);
    Assert.AreEqual<Integer>(1, Dropped, 'nur der echte Low-Befund faellt');
    Assert.AreEqual<Integer>(1, L.Count);
    Assert.AreEqual<TFindingKind>(fkFileReadError, L[0].Kind);
  finally
    L.Free;
  end;
end;

procedure TTestConfidenceFilter.EmptyList_NoCrash;
var
  L : TObjectList<TLeakFinding>;
begin
  L := TObjectList<TLeakFinding>.Create(True);
  try
    Assert.AreEqual<Integer>(0, TConfidenceFilter.ApplyToFindings(L, fcHigh));
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConfidenceFilter);

end.
