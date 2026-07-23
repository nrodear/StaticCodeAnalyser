unit uTestNilDeref;

// Tests fuer TNilDerefDetector. Pattern: Variable koennte nil sein
// (z.B. Function-Return ohne Assigned-Check) und wird dereferenziert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNilDeref = class
  public
    [Test] procedure UncheckedReturn_Reported;
    [Test] procedure AssignedCheck_NotReported;
    [Test] procedure NotNilCheck_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Real-World FP-Audit 2026-07-10: out-param-Finder in der if-Bedingung
    [Test] procedure OutParamFinderInIfCondition_NotReported;
    // Real-World FP-Audit 2026-07-12: nil-Zuweisung und Deref in sich
    // ausschliessenden {$IFDEF}/{$ELSE}-Zweigen (preprocessor-branch)
    [Test] procedure PreprocessorSiblingBranch_NotReported;
    [Test] procedure PreprocessorSameBranch_StillReported;
    // #6 Inkr.2 (SCA008 Q1): CFG-Erreichbarkeits-Postfilter
    [Test] procedure CfgTerminatedBranch_NotReported;
    [Test] procedure CfgBranchWithoutExit_StillReported;
    [Test] procedure CfgCaseArmSiblings_NotReported;
    [Test] procedure CfgSameCaseArm_StillReported;
    // #6 Inkr.3 (SCA008 Formen c+d): Korrelations-Gates
    [Test] procedure NilTestEarlyExit_NotReported;
    [Test] procedure NilTestWithoutExit_StillReported;
    [Test] procedure CorrelatedNegatedIfs_NotReported;
    [Test] procedure CorrelatedSameCondition_StillReported;
    [Test] procedure CorrelatedButFlagMutated_StillReported;
    [Test] procedure NestedNilTestGuard_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNilDeref.UncheckedReturn_Reported;
// TNilDerefDetector matched aktuell ausschliesslich `var := nil` gefolgt
// von `var.Method(...)`. Die "function-return-might-be-nil"-Variante
// (`x := FindThing; x.DoStuff`) ist out-of-scope - dafuer braeuchte es
// eine Inter-Procedural-Nullable-Analyse die Delphi-AST nicht
// strukturell erlaubt. Bis dahin hier das Pattern testen das tatsaechlich
// erkannt wird (Audit V5 / 2026-05-30).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1);
  finally F.Free; end;
end;

procedure TTestNilDeref.AssignedCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function FindThing: TObject; forward;'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := FindThing;'#13#10 +
  '  if Assigned(x) then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDeref.NotNilCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function FindThing: TObject; forward;'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := FindThing;'#13#10 +
  '  if x <> nil then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDeref.Finding_KindAndSeverity;
// Siehe UncheckedReturn_Reported - Detector matched nur `var := nil`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  x.DoStuff;'#13#10 +
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
      if Fnd.Kind = fkNilDeref then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkNilDeref finding expected');
    Assert.AreEqual(fkNilDeref, Hit.Kind);
  finally F.Free; end;
end;

procedure TTestNilDeref.OutParamFinderInIfCondition_NotReported;
// Real-World FP-Audit 2026-07-10 'out-param-assignment-guarded': die Variable
// wird als var/out-Argument an einen Finder IN DER BEDINGUNG uebergeben
// ('if FindProcessor(..., lProc) then'); der Deref im if-true-Zweig ist damit
// gefuellt. Der Finder-Call steht als nkIfStmt.TypeRef, nicht als nkCall ->
// vorher von IsPassedAsArgBetween verfehlt (DMVC ActiveRecordController).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const APath: string);'#13#10 +
  'var lProcessor: TObject;'#13#10 +
  'begin'#13#10 +
  '  lProcessor := nil;'#13#10 +
  '  if FindProcessor(APath, lProcessor) then'#13#10 +
  '    lProcessor.Execute;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'out-Param-Finder in der Bedingung fuellt die Variable - kein nil-Deref');
  finally F.Free; end;
end;

procedure TTestNilDeref.PreprocessorSiblingBranch_NotReported;
// Real-World FP-Audit 2026-07-12 'preprocessor-branch' (Teilklasse von
// mutually-exclusive-branches, verifiziertes Vorbild Indy IdSync.pas:744):
// x:=nil steht im {$IFDEF}-Zweig, der Deref x.DoStuff im {$ELSE}-Schwester-
// Zweig. Auf jeder realen Uebersetzung existiert nur EIN Zweig - der Detektor
// (rein zeilenbasiert, ohne Branch-Scope) flaggte das faelschlich. Der
// nkConditionalRange-Guard erkennt die {$ELSE}-Direktivenzeile strikt zwischen
// nil-Zuweisung und Deref und unterdrueckt den Fund.
const SRC =
  'unit t; implementation'#13#10 +   // 1
  'procedure Foo;'#13#10 +           // 2
  'var x: TObject;'#13#10 +          // 3
  'begin'#13#10 +                    // 4
  '{$IFDEF SOMEFLAG}'#13#10 +        // 5
  '  x := nil;'#13#10 +              // 6  nil-Zuweisung (IFDEF-Zweig)
  '{$ELSE}'#13#10 +                  // 7  Direktive STRIKT zwischen 6 und 8
  '  x.DoStuff;'#13#10 +            // 8  Deref (ELSE-Schwesterzweig)
  '{$ENDIF}'#13#10 +                 // 9
  'end;';                            // 10
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'nil-Zuweisung und Deref in sich ausschliessenden {$IFDEF}/{$ELSE}-Zweigen - kein nil-Deref');
  finally F.Free; end;
end;

procedure TTestNilDeref.PreprocessorSameBranch_StillReported;
// TP-Gegenprobe zu PreprocessorSiblingBranch_NotReported: nil-Zuweisung UND
// Deref stehen im SELBEN {$IFDEF}-Zweig - keine Direktivenzeile strikt
// dazwischen. Der Guard darf hier NICHT greifen; der echte nil-Deref bleibt
// ein Fund (beweist, dass die Suppression scope-genau auf 'Direktive strikt
// zwischen nil und Deref' begrenzt ist, nicht 'Direktive irgendwo in Methode').
const SRC =
  'unit t; implementation'#13#10 +   // 1
  'procedure Foo;'#13#10 +           // 2
  'var x: TObject;'#13#10 +          // 3
  'begin'#13#10 +                    // 4
  '{$IFDEF SOMEFLAG}'#13#10 +        // 5
  '  x := nil;'#13#10 +              // 6  nil-Zuweisung
  '  x.DoStuff;'#13#10 +            // 7  Deref - selber Zweig, keine Direktive dazwischen
  '{$ENDIF}'#13#10 +                 // 8
  'end;';                            // 9
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'nil-Deref im selben {$IFDEF}-Zweig bleibt ein echter Fund');
  finally F.Free; end;
end;

{ #6 Inkr.2 (SCA008 Q1): CFG-Erreichbarkeits-Postfilter }

procedure TTestNilDeref.CfgTerminatedBranch_NotReported;
// Form (a): nil-Zuweisung in terminierendem Zweig - der Exit beendet den
// Pfad, der Deref nach dem if laeuft nur ueber den Nicht-nil-Pfad. Vor
// Inkr.2 gemeldet (kein lexikalisches Gate greift: kein else, Bedingung
// ohne Assigned/<>nil-Pattern, kein Reassign).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Fail: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if Fail then'#13#10 +
  '  begin'#13#10 +
  '    x := nil;'#13#10 +
  '    Exit;'#13#10 +
  '  end;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'nil+Exit im Zweig: Deref ist vom nil-Block unerreichbar -> kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.CfgBranchWithoutExit_StillReported;
// TP-Gegenprobe zu Form (a): OHNE Exit fliesst der nil-Pfad zum Merge und
// erreicht den Deref -> der Fund MUSS bleiben (Ueberreichweite-Schutz).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Fail: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if Fail then'#13#10 +
  '    x := nil;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'ohne Exit erreicht der nil-Pfad den Deref -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.CfgCaseArmSiblings_NotReported;
// Form (b): case-Arm-Geschwister sind nie gemeinsam ausfuehrbar;
// IsInExclusiveBranch deckt nur then/else desselben if -> vor Inkr.2
// wurde das gemeldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: x := nil;'#13#10 +
  '    1: x.DoStuff;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'case-Arm-Geschwister: kein gemeinsamer Pfad -> kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.CfgSameCaseArm_StillReported;
// TP-Gegenprobe zu Form (b): nil und Deref im SELBEN Arm laufen
// sequentiell -> der Fund MUSS bleiben (Same-Block => kein Drop).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: begin'#13#10 +
  '         x := nil;'#13#10 +
  '         x.DoStuff;'#13#10 +
  '       end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'nil+Deref im selben case-Arm bleibt ein echter Fund');
  finally F.Free; end;
end;

{ #6 Inkr.3 (SCA008 Formen c+d): Korrelations-Gates }

procedure TTestNilDeref.NilTestEarlyExit_NotReported;
// Form (d): der nil-Test mit terminierendem then toetet die nil-Definition
// auf dem Fall-through-Pfad - x ist am Deref garantiert <> nil. Der Header
// behauptete diese Abdeckung schon immer, CondHasGuard hatte das
// '= nil'-Pattern aber nie (vor Inkr.3 gemeldet).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  if x = nil then'#13#10 +
  '    Exit;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'nil-Test mit Exit zwischen nil und Deref -> Fall-through ist nil-frei');
  finally F.Free; end;
end;

procedure TTestNilDeref.NilTestWithoutExit_StillReported;
// TP-Gegenprobe zu Form (d): then-Teil terminiert NICHT (nur Logging) ->
// der Fall-through kann weiterhin mit x = nil laufen -> Fund bleibt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  if x = nil then'#13#10 +
  '    DoLog;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'nil-Test ohne Terminierung schuetzt den Fall-through nicht');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedNegatedIfs_NotReported;
// Form (c): exakt negierte Bedingungen ('a' vs 'not a') auf gleicher
// Arm-Seite -> die Zweige schliessen sich aus, nil erreicht den Deref nie.
// War in IsInExclusiveBranch explizit als 'braucht Mini-CFG' vorgemerkt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if a then'#13#10 +
  '    x := nil;'#13#10 +
  '  if not a then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'negiert-korrelierte Separat-ifs sind exklusiv -> kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedSameCondition_StillReported;
// TP-Gegenprobe zu Form (c): GLEICHE Bedingung auf gleicher Seite -> beide
// Zweige laufen gemeinsam (a=True) -> echter nil-Deref, Fund MUSS bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if a then'#13#10 +
  '    x := nil;'#13#10 +
  '  if a then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'gleiche Bedingung = gemeinsamer Pfad -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedButFlagMutated_StillReported;
// TP-Gegenprobe zu Form (c): das Flag mutiert ZWISCHEN den ifs -> die
// Korrelation ist gebrochen (a=True: erst nil, dann a=False -> Deref
// laeuft MIT nil). Das Mutations-Fenster muss den Drop verhindern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if a then'#13#10 +
  '    x := nil;'#13#10 +
  '  a := False;'#13#10 +
  '  if not a then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Flag-Mutation zwischen den ifs bricht die Korrelation -> Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.NestedNilTestGuard_StillReported;
// TP-Gegenprobe zu Form (d), Soundness-Fix 2026-07-24: der nil-Test liegt
// selbst in einem anderen Branch - bei y=False laeuft der Fall-through OHNE
// Guard mit x = nil in den Deref -> Fund MUSS bleiben.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(y: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  if y then'#13#10 +
  '  begin'#13#10 +
  '    if x = nil then'#13#10 +
  '      Exit;'#13#10 +
  '  end;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'geschachtelter Guard liegt nicht auf jedem Pfad -> Fund bleibt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNilDeref);

end.
