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
    // T1-Fensterfix (Review 2026-07-28, umgesetzt 2026-07-29): Schleife um
    // EIN if genuegt fuer Ganz-Methoden-Fenster; Zeilenvergleiche inklusiv.
    [Test] procedure CorrelatedLoopAroundDeref_MutationAfter_StillReported;
    [Test] procedure CorrelatedLoopAroundAssign_MutationBefore_StillReported;
    [Test] procedure CorrelatedSameLineMutation_StillReported;
    [Test] procedure CorrelatedNoLoopNoMutation_StillDropped;
    // Review 2026-07-30: IfA/IfB duerfen sich im Conds-Scan nicht selbst
    // vetoen - die Assigned()-Form der Whitelist traegt Klammern und
    // matchte als vermeintliche var/out-Uebergabe (T1-Regression).
    [Test] procedure CorrelatedAssignedForm_NoMutation_Dropped;
    [Test] procedure CorrelatedAssignedForm_FlagMutated_StillReported;
    [Test] procedure CorrelatedAssignedForm_VarOutCondBetween_StillReported;
    // SCA008-Autopsie 2026-08-27 (S-Paket, 40er-Stichprobe / 44 von 48 FP):
    // fuenf Gates gegen die gezaehlten FP-Klassen, je mit TP-Gegenprobe.
    [Test] procedure IndexedNilTarget_NotReported;
    [Test] procedure ValueTypeDynArray_NotReported;
    [Test] procedure ValueTypeNullable_NotReported;
    [Test] procedure ValueTypeLookalikeName_StillReported;
    [Test] procedure ValueTypeGenericInlineVar_NotReported;
    [Test] procedure BoolAliasGuard_NotReported;
    [Test] procedure BoolAliasAssignInBranch_StillReported;
    [Test] procedure BoolAliasFlagMutated_StillReported;
    [Test] procedure BoolAliasFlagPassedAsVarArg_StillReported;
    [Test] procedure WhileGuardAroundDeref_NotReported;
    [Test] procedure WhileGuardDerefAfterLoop_StillReported;
    [Test] procedure NestedNilTestGuardSameArm_NotReported;
    [Test] procedure NestedNilTestGuardOtherArm_StillReported;
    // Nachzug zum Parserfix 38ac2ea (2026-08-28): IsInExclusiveBranch kennt
    // jetzt auch zwei verschiedene Arme DESSELBEN case. Warum die Faelle mit
    // 'with' gebaut sind, steht bei ExclusiveCaseArms_NotReported.
    [Test] procedure ExclusiveCaseArms_NotReported;
    [Test] procedure ExclusiveCaseElseArm_NotReported;
    [Test] procedure ExclusiveCaseSameArm_StillReported;
    [Test] procedure ExclusiveNestedCaseInnerArms_NotReported;
    [Test] procedure CaseArmIfThenWithCaseElse_NotReported;
    [Test] procedure MultiLabelCaseArmIsOneArm_StillReported;
    // Ueberreichweiten-Waechter zur Arm-Pruefung (Gegenpruefung 2026-08-28).
    // Genau die vier Richtungen, in denen die Unterdrueckung still zu weit
    // greifen wuerde: Schleife um das case, Deref hinter dem case, zwei
    // verschiedene case, Deref hinter einem INNEREN case im selben
    // Aussen-Arm.
    [Test] procedure LoopAroundCaseArms_StillReported;
    [Test] procedure DerefAfterCase_StillReported;
    [Test] procedure TwoSeparateCases_StillReported;
    [Test] procedure DerefAfterInnerCaseInSameOuterArm_StillReported;
    // Nachzug MINOR 1 (Gegenpruefung 2026-08-28): das Schleifen-Veto begruendet
    // sich damit, dass der CFG den Fall ueber die Rueckkante schon loest - und
    // genau diese Loesung mass kein Test, weil LoopAroundCaseArms den
    // with-Hebel traegt und deshalb NUR das Veto sieht. Der erste Test unten
    // ist die nackte Form und haelt beides fest (Veto UND uCFG-Rueckkante);
    // die beiden anderen nageln fest, dass das Veto auch repeat und for
    // mitnimmt - das stand vorher nur in der Kind-Menge im Quelltext.
    [Test] procedure PlainLoopAroundCaseArms_StillReported;
    [Test] procedure RepeatAroundCaseArms_StillReported;
    [Test] procedure ForAroundCaseArms_StillReported;
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

procedure TTestNilDeref.CorrelatedLoopAroundDeref_MutationAfter_StillReported;
// DER Review-Fall: Schleife nur um das Deref-if, Flag-Mutation NACH dessen
// Zeile. Iteration 2 dereferenziert x = nil. Vor dem Fix verlangte das
// Fenster eine Schleife um BEIDE ifs - die Mutation lag hinter WindowEnd
// und der echte Bug wurde gedroppt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a, c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if a then'#13#10 +
  '    x := nil;'#13#10 +
  '  while c do'#13#10 +
  '  begin'#13#10 +
  '    if not a then'#13#10 +
  '      x.DoStuff;'#13#10 +
  '    a := not a;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Cross-Iteration-nil-Deref darf nicht gedroppt werden');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedLoopAroundAssign_MutationBefore_StillReported;
// Spiegelfall: Schleife nur um das Assign-if, Mutation VOR dessen Zeile -
// gehoert im naechsten Durchlauf ZWISCHEN die Auswertungen. Braucht die
// Fenster-START-Erweiterung, nicht nur das Ende.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a, c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  while c do'#13#10 +
  '  begin'#13#10 +
  '    a := not a;'#13#10 +
  '    if a then'#13#10 +
  '      x := nil;'#13#10 +
  '  end;'#13#10 +
  '  if not a then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Mutation vor IfA in der Schleife darf die Exklusivitaet nicht retten');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedSameLineMutation_StillReported;
// Einzeiler: Mutation AUF der IfA-Zeile. Der alte exklusive Vergleich
// (N.Line > IfA.Line) uebersah sie.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if a then begin x := nil; a := False; end;'#13#10 +
  '  if not a then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Mutation auf der IfA-Zeile macht die Zweige gemeinsam erreichbar');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedNoLoopNoMutation_StillDropped;
// Regressionswaechter: der urspruengliche FP-Fall (exklusive ifs, KEINE
// Schleife, KEINE Mutation) muss weiterhin gedroppt bleiben - der Fix darf
// das Gate nur verengen, wo Iteration/Mutation im Spiel ist.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if a then'#13#10 +
  '    x := nil;'#13#10 +
  '  Beep;'#13#10 +
  '  if not a then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'ohne Schleife und ohne Mutation bleibt der Drop bestehen');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedAssignedForm_NoMutation_Dropped;
// Review 2026-07-30 (T1-Regression): WindowStart-1 zog IfA selbst in den
// Conds-Scan von IsPassedAsArgBetween; dessen eigenes 'assigned ( a )'
// matchte in HasBareArgUse als var/out-Uebergabe -> das Gate vetote sich
// selbst und die Assigned()-Form (idiomatischste Whitelist-Form) wurde
// nie gedroppt. IfA/IfB sind jetzt per Referenz ausgenommen - ihre
// Bedingungen haben ParseCorrelatedCond passiert, sind also
// nebenwirkungsfrei. Bare-Flag-Formen ('a'/'not a') sahen den Defekt
// nicht: ohne Klammer bricht HasBareArgUse sofort ab.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: TObject);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(a) then'#13#10 +
  '    x := nil;'#13#10 +
  '  Beep;'#13#10 +
  '  if not Assigned(a) then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'Assigned()-korrelierte Separat-ifs ohne Mutation muessen droppen');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedAssignedForm_FlagMutated_StillReported;
// TP-Gegenprobe: Mutation der Korrelations-Variable ZWISCHEN den ifs
// bricht die Exklusivitaet (a zunaechst assigned: erst x := nil, dann
// a := nil -> IfB-Zweig laeuft MIT x = nil). Der Assign-Scan des
// Fensters muss den Drop weiterhin verhindern - die IfA/IfB-Ausnahme
// darf NUR die eigenen Bedingungen betreffen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(a: TObject);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(a) then'#13#10 +
  '    x := nil;'#13#10 +
  '  a := nil;'#13#10 +
  '  if not Assigned(a) then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Flag-Mutation zwischen Assigned()-ifs bricht die Korrelation');
  finally F.Free; end;
end;

procedure TTestNilDeref.CorrelatedAssignedForm_VarOutCondBetween_StillReported;
// TP-Gegenprobe: ein DRITTES if zwischen dem Paar uebergibt die
// Korrelations-Variable als potentielles var/out-Argument
// ('if TryMutate(a) then') - dieses Veto muss erhalten bleiben; die
// Referenz-Ausnahme gilt ausschliesslich fuer IfA und IfB selbst.
const SRC =
  'unit t; implementation'#13#10 +
  'function TryMutate(var o: TObject): Boolean; forward;'#13#10 +
  'procedure Foo(a: TObject);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(a) then'#13#10 +
  '    x := nil;'#13#10 +
  '  if TryMutate(a) then'#13#10 +
  '    Beep;'#13#10 +
  '  if not Assigned(a) then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'var/out-Uebergabe in fremder Bedingung muss weiter vetoen');
  finally F.Free; end;
end;

{ SCA008-Autopsie 2026-08-27 (S-Paket): Gates gegen die gezaehlten FP-Klassen
  der 40er-Stichprobe (44 von 48 Verdikten FP). Jeder Drop-Test hat, wo das
  Gate ueberhaupt eine Grenze kennt, seine TP-Gegenprobe daneben. }

procedure TTestNilDeref.IndexedNilTarget_NotReported;
// Indexed-Skip (4 Drops): ParsePrimary kollabiert JEDEN Index-Ausdruck zu
// '[]' - 'Items[0]' und 'Items[1]' heissen im AST beide 'Items[]'. Der
// Detektor kann Elemente also gar nicht auseinanderhalten und meldet den
// Guard-geschuetzten Zugriff auf ein ANDERES Element als nil-Deref. Genau
// so lagen alle vier Korpus-Faelle: nil auf Element A, verifizierter Guard
// und Zugriff auf Element B.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Items: TList);'#13#10 +
  'begin'#13#10 +
  '  Items[0] := nil;'#13#10 +
  '  if Assigned(Items[1]) then'#13#10 +
  '    Items[1].DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'Element-Tracking ueber Indizes ist unsound - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.ValueTypeDynArray_NotReported;
// Werttyp-Gate (5 Drops), trennerlose Schreibweise: die klassische var-
// Sektion konkateniert die Typ-Tokens ohne Blank, der TypeRef lautet
// 'arrayofTObject'. Bei einem dynamischen Array ist nil ein WERT (Laenge 0),
// kein genullter Zeiger - ein Member-Zugriff kann dort nie eine AV sein.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: array of TObject;'#13#10 +
  'begin'#13#10 +
  '  Buf := nil;'#13#10 +
  '  Buf.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'nil ist bei array of T ein Wert, kein Zeiger - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.ValueTypeNullable_NotReported;
// Werttyp-Gate, zweite Form: Nullable<T> (Spring4D-Stil). 'Opt := nil'
// leert den Wrapper, es entsteht kein dereferenzierbarer Zeiger.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Opt: Nullable<TObject>;'#13#10 +
  'begin'#13#10 +
  '  Opt := nil;'#13#10 +
  '  Opt.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'Nullable<T> traegt nil als Wert - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.ValueTypeGenericInlineVar_NotReported;
// Gegenpruefungs-MINOR 2026-08-27: ParseInlineVarStmt und ParseForStmt
// setzen zwischen ALLE Typ-Tokens ein Leerzeichen - ein inline
// deklariertes 'TArray<TObject>' kommt als 'tarray < tobject >' an und
// wurde vom Praefix-Test verfehlt. Das Werttyp-Gate strippt die Blanks
// jetzt vor der Generic-Pruefung.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  var Buf: TArray<TObject> := nil;'#13#10 +
  '  Buf.DoStuff;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'nil ist bei einem dynamischen Array ein WERT - kein Deref moeglich');
  finally F.Free; end;
end;

procedure TTestNilDeref.ValueTypeLookalikeName_StillReported;
// TP-Gegenprobe zum Werttyp-Gate: ein KLASSENname, der nur wie ein Array
// klingt ('TArrayBuffer'), ist eine Referenz - der Praefix-Test darf nicht
// auf den blossen Wortbestandteil anspringen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: TArrayBuffer;'#13#10 +
  'begin'#13#10 +
  '  Buf := nil;'#13#10 +
  '  Buf.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'TArrayBuffer ist eine Klasse, kein dynamisches Array - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.BoolAliasGuard_NotReported;
// Boolean-Zwischenvariable (7 Drops): das nil-Praedikat wird zwischen-
// gespeichert und erst danach abgefragt. 'if ok then' sieht fuer den
// Detektor wie eine beliebige Bedingung aus, traegt aber exakt die Aussage
// 'x <> nil'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  x: TObject;'#13#10 +
  '  ok: Boolean;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  ok := x <> nil;'#13#10 +
  '  if ok then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'kopierpropagiertes nil-Praedikat ist ein Guard - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.BoolAliasAssignInBranch_StillReported;
// *** SKEPTIKER-MAJOR der Autopsie 2026-08-27 ***: ohne Dominanz-Zwang
// frisst das Gate echte Funde. Hier laeuft die Flag-Zuweisung NUR im
// c-Zweig; bei c = False traegt ok noch das alte True und der Deref sieht
// x = nil. Die Zuweisung muss also auf demselben Arm liegen wie das
// Guard-if, nicht in einem Zweig darunter.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(c: Boolean);'#13#10 +
  'var'#13#10 +
  '  x: TObject;'#13#10 +
  '  ok: Boolean;'#13#10 +
  'begin'#13#10 +
  '  ok := True;'#13#10 +
  '  x := nil;'#13#10 +
  '  if c then'#13#10 +
  '    ok := x <> nil;'#13#10 +
  '  if ok then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'bedingte Flag-Zuweisung laeuft nicht auf jedem Pfad - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.BoolAliasFlagMutated_StillReported;
// TP-Gegenprobe: das Flag wird nach dem Praedikat ueberschrieben - die
// Kopplung an 'x <> nil' ist damit gebrochen und 'if ok' schuetzt nichts.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  x: TObject;'#13#10 +
  '  ok: Boolean;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  ok := x <> nil;'#13#10 +
  '  ok := True;'#13#10 +
  '  if ok then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'Mutation des Flags bricht die Kopierpropagation - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.BoolAliasFlagPassedAsVarArg_StillReported;
// TP-Gegenprobe: das Flag geht als potentielles var/out-Argument in einen
// fremden Aufruf - der kann es beliebig setzen. Dasselbe Veto wie im
// Korrelations-Gate, nur auf die Zwischenvariable angewandt.
const SRC =
  'unit t; implementation'#13#10 +
  'function TryToggle(var b: Boolean): Boolean; forward;'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  x: TObject;'#13#10 +
  '  ok: Boolean;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  ok := x <> nil;'#13#10 +
  '  TryToggle(ok);'#13#10 +
  '  if ok then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'var/out-Uebergabe des Flags muss den Drop verhindern');
  finally F.Free; end;
end;

procedure TTestNilDeref.WhileGuardAroundDeref_NotReported;
// while-Guard (1 Drop): der Schleifenkopf ist fuer jede Iteration des
// RUMPFS derselbe Guard wie eine if-Bedingung. Die Assigned()-Form faellt
// schon vorher weg (sie sieht fuer IsPassedAsArgBetween wie eine var/out-
// Uebergabe aus); die klammerfreie Vergleichsform legt ParseWhileStmt als
// 'x<>nil' ab und niemand hat sie bisher gelesen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  while x <> nil do'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'Deref im Rumpf laeuft nur mit erfuellter Schleifenbedingung');
  finally F.Free; end;
end;

procedure TTestNilDeref.WhileGuardDerefAfterLoop_StillReported;
// TP-Gegenprobe zum while-Guard: NACH der Schleife ist die Bedingung per
// Definition falsch, x also nil. Ohne den Rumpf-Zwang (NodeContainsRef)
// wuerde genau dieser echte Fund stillschweigend verschwinden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  while x <> nil do'#13#10 +
  '    Beep;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'nach der Schleife ist x garantiert nil - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.NestedNilTestGuardSameArm_NotReported;
// Nested-Guard-Lockerung (1 Drop): der Early-Exit-Guard steckt zwar in
// einem anderen if, der Deref aber im SELBEN Arm dahinter - jeder Pfad zum
// Deref fuehrt durch den Guard. Korpus-Vorbild cnwizards
// CnEditorToggleVar.pas (nil Z.304, Guard Z.350/351, Deref Z.392 - alle im
// else-Arm des if aus Z.293).
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
  '    x.DoStuff;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
    'Guard und Deref im selben Arm - der Guard dominiert den Deref');
  finally F.Free; end;
end;

procedure TTestNilDeref.NestedNilTestGuardOtherArm_StillReported;
// *** SKEPTIKER-MAJOR der Autopsie 2026-08-27 ***: die Lockerung muss
// ARM-genau sein, nicht Container-genau. Hier enthaelt das aeussere if die
// nil-Zuweisung (then) UND den Guard (else) - der Deref steht aber DAHINTER.
// Bei c = True laeuft x := nil, der Guard im else-Arm laeuft nie, und
// x.DoStuff dereferenziert nil. Eine Lockerung auf blosses
// 'Container enthaelt beides' haette diesen echten Fund gedroppt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  if c then'#13#10 +
  '    x := nil'#13#10 +
  '  else'#13#10 +
  '  begin'#13#10 +
  '    if x = nil then'#13#10 +
  '      Exit;'#13#10 +
  '  end;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
    'Guard im anderen Arm dominiert den Deref nicht - Fund bleibt');
  finally F.Free; end;
end;

{ Arm-Exklusivitaet im case - Nachzug zum Parserfix 38ac2ea (2026-08-28) }

procedure TTestNilDeref.ExclusiveCaseArms_NotReported;
// Zwei verschiedene Arme desselben case laufen nie gemeinsam.
//
// WARUM DAS 'with' IM ARM STEHT - das ist der ganze Trick dieses Tests:
// die nackte Form ('0: x := nil; 1: x.DoStuff;') prueft CfgCaseArmSiblings_
// NotReported oben schon, und sie ist GRUEN ohne die Arm-Erweiterung, weil
// CfgDropsNilDeref sie ueber CanReach droppt. Sie taugt deshalb nur als
// Waechter, nicht als Beweis. Der CFG-Builder steigt in nkCall-Kinder nicht
// ab, und ein with-Rumpf haengt als nkCall-Kind im Baum (uParser2 Z.2386) -
// die nil-Zuweisung landet damit in KEINEM CFG-Block, NilBlk bleibt nil und
// CfgDropsNilDeref droppt per Vertrag nicht. Hier ist die neue Arm-Pruefung
// das einzige Netz: OHNE sie ist dieser Test ROT.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: with Owner do x := nil;'#13#10 +
  '    1: x.DoStuff;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'Arm 0 und Arm 1 schliessen sich aus - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.ExclusiveCaseElseArm_NotReported;
// Wie oben, aber der Deref steht im else-Arm. Der else-Arm ist gegenueber
// jedem regulaeren Arm genauso exklusiv wie zwei regulaere Arme
// untereinander - im AST ist er schlicht ein weiterer nkCaseArm
// (Name='else', uParser2 Z.2702), das Gate braucht dafuer keinen Sonderfall.
// 'with' aus demselben Grund wie oben -> OHNE die Arm-Pruefung ROT.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: with Owner do x := nil;'#13#10 +
  '  else'#13#10 +
  '    x.DoStuff;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'regulaerer Arm und else-Arm schliessen sich aus - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.ExclusiveCaseSameArm_StillReported;
// UEBERREICHWEITEN-WAECHTER zur Arm-Pruefung: nil-Zuweisung UND Deref stehen
// im SELBEN Arm, sie laufen also sequentiell. Der zweite Arm ist noetig,
// damit das case den Vorfilter DirectChildCount(nkCaseArm) >= 2 passiert und
// die Arm-Pruefung wirklich laeuft (mit nur einem Arm wuerde der Test
// gruen bleiben, ohne etwas ueber das Gate auszusagen). Das 'with' ist hier
// NICHT tragend, und zwar auf BEIDEN Wegen: mit dem 'with' liegt der
// nkAssign in gar keinem CFG-Block (uCFG behandelt nkCall als Blatt,
// Ausstieg 'NilBlk = nil'); OHNE das 'with' laegen beide Knoten im selben
// Block und der Ausstieg waere 'NilBlk = DerefBlk'. Keiner der beiden
// Wege droppt - das 'with' haelt hier nur die Fixture formgleich mit
// ExclusiveCaseArms_NotReported.
// Gruen mit UND ohne die Aenderung; rot nur, wenn das Gate zu weit greift
// (z.B. 'beide irgendwo im selben case' statt 'in verschiedenen Armen').
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: begin'#13#10 +
  '         with Owner do x := nil;'#13#10 +
  '         x.DoStuff;'#13#10 +
  '       end;'#13#10 +
  '    1: DoOther;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'nil und Deref im SELBEN Arm laufen sequentiell - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.ExclusiveNestedCaseInnerArms_NotReported;
// VERSCHACHTELTE case: im AEUSSEREN case liegen beide Knoten im SELBEN Arm
// (Arm 0), im INNEREN in verschiedenen. Erwartet ist Unterdrueckung, und das
// ist die strengere der beiden Aussagen: das aeussere case sagt nur, dass
// beide denselben Weg nehmen KOENNEN, das innere sagt, dass sie es NICHT
// koennen. Es genuegt also EIN case, das die beiden trennt - deshalb fragt
// das Gate jedes case einzeln, statt einen gemeinsamen Vorfahren zu suchen.
// Der umgekehrte Fall (im inneren zusammen, im aeusseren getrennt) braucht
// keinen eigenen Test: dort findet das innere case nur EINEN der beiden
// Knoten in seinen Armen und enthaelt sich, und das aeussere entscheidet -
// das ist strukturell derselbe Lauf wie ExclusiveCaseArms_NotReported.
// OHNE die Arm-Pruefung ROT (with-Trick s.o.).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k, m: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: case m of'#13#10 +
  '         0: with Owner do x := nil;'#13#10 +
  '         1: x.DoStuff;'#13#10 +
  '       end;'#13#10 +
  '    1: DoOther;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'Trennung im INNEREN case genuegt - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.CaseArmIfThenWithCaseElse_NotReported;
// Die im Bewegungsvertrag von 38ac2ea namentlich genannte Form: nil-Zuweisung
// im then-Zweig des Arm-ifs, Deref im case-else. Bis zum Parserfix wurde sie
// ueber den PHANTOM-nkElseBranch gedroppt (richtiges Ergebnis, falscher
// Grund), seither sind es zwei echte Arme.
// WAECHTER, nicht Beweis: dieser Test ist in allen drei Zustaenden gruen -
// vor dem Parserfix ueber das Phantom, danach ueber CfgDropsNilDeref, und
// jetzt zusaetzlich ueber die Arm-Pruefung (die als erste antwortet). Er
// haelt genau die Stelle fest, an der das Paket sonst FPs eintauschen wuerde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer; c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: if c then x := nil;'#13#10 +
  '  else'#13#10 +
  '    x.DoStuff;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref),
      'Arm-if-then und case-else sind verschiedene Arme - kein Fund');
  finally F.Free; end;
end;

procedure TTestNilDeref.MultiLabelCaseArmIsOneArm_StillReported;
// Delphi kennt kein fall-through, aber mehrere LABELS je Arm. Der Parser
// verschluckt die Label-Liste per SkipTo(tkColon) vor dem Arm-Body
// (uParser2 Z.2694), '0, 1:' ergibt also EINEN nkCaseArm. Beide Knoten
// liegen damit im selben Arm-Knoten und duerfen NICHT gedroppt werden.
// Waechter fuer genau diese Parser-Zusage: gruen mit und ohne die
// Aenderung, rot falls Labels je einen eigenen Arm bekaemen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0, 1: begin'#13#10 +
  '            with Owner do x := nil;'#13#10 +
  '            x.DoStuff;'#13#10 +
  '          end;'#13#10 +
  '    2: DoOther;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'mehrere Labels ergeben EINEN Arm - Fund bleibt');
  finally F.Free; end;
end;

{ Ueberreichweiten-Waechter zur Arm-Pruefung (Gegenpruefung 2026-08-28).
  Der Waechter oben prueft nur die Richtung 'beide im selben Arm'. Die vier
  hier decken die uebrigen ab.

  ZUM with-HEBEL, korrigiert (MINOR 4 der Gegenpruefung - die Erstfassung
  behauptete hier pauschal, ohne 'with' gaebe der CFG die Antwort statt der
  Arm-Pruefung). Tragend ist der Hebel nur in den drei _NotReported-Faellen,
  die ihn tragen: dort wuerde CfgDropsNilDeref ohne ihn selbst droppen und
  die neue Pruefung maskieren. In den _StillReported-Faellen hier droppt der
  CFG so oder so
  nicht - die Knoten sind sequentiell erreichbar (Deref hinter dem case,
  zweites case, innerer Arm) bzw. gar nicht erst in einem Block, weil das
  'with' den nkAssign zum Blatt-Kind macht (selber Arm; ohne das 'with'
  laegen sie im selben Block, was ebenfalls nicht droppt), und ueber die
  Schleifen-Rueckkante ebenfalls (LoopAroundCaseArms). Der Hebel
  bleibt trotzdem drin, aber aus einem anderen Grund: er haelt die Fixtures
  formgleich mit den _NotReported-Faellen, die sie bewachen - genau EINE
  Sache ist geaendert. }

procedure TTestNilDeref.LoopAroundCaseArms_StillReported;
// Regressionswaechter zum Schleifen-Veto, with-Variante. Die Arm-
// Exklusivitaet gilt je DURCHLAUF: Iteration 1 nimmt Arm 0 (x := nil),
// Iteration 2 nimmt Arm 1 und dereferenziert. Echter Fund.
// Ohne das Veto in InDifferentCaseArms ist dieser Test ROT - der with-Hebel
// haelt CfgDropsNilDeref draussen (NilBlk bleibt nil), also ist das Veto hier
// das einzige Netz. Das ist der BEWEIS fuer das Veto, misst aber NUR das
// Veto - die CFG-Rueckkante, mit der das Veto begruendet ist, sieht dieser
// Test nicht. Dafuer gibt es PlainLoopAroundCaseArms_StillReported unten.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer; c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  while c do'#13#10 +
  '    case k of'#13#10 +
  '      0: with Owner do x := nil;'#13#10 +
  '      1: x.DoStuff;'#13#10 +
  '    end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Schleife um das case - zwei Iterationen nehmen beide Arme, Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.DerefAfterCase_StillReported;
// Der Deref steht HINTER dem case, die nil-Zuweisung in Arm 0. Sequentiell,
// echter Fund. Haengt allein daran, dass ArmHolding fuer den Deref nil
// liefert (er steht in KEINEM Arm) und die Schleife dieses case ueberspringt.
// Rot, sobald die Pruefung von 'in verschiedenen Armen' auf 'einer im Arm,
// der andere irgendwo' aufweichen wuerde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: with Owner do x := nil;'#13#10 +
  '    1: DoOther;'#13#10 +
  '  end;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Deref hinter dem case laeuft nach Arm 0 - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.TwoSeparateCases_StillReported;
// ZWEI verschiedene case-Statements: nil in Arm 0 des ersten, Deref in Arm 0
// des zweiten. Verschiedene Arme, aber eben nicht DESSELBEN case - die
// beiden laufen hintereinander, der Fund ist echt. Jedes case findet nur
// EINEN der beiden Knoten und muss sich enthalten.
// KEIN Waechter fuer den Zeilen-Vorfilter, anders als die Erstfassung hier
// behauptete (MINOR 2 der Gegenpruefung): richtig ist zwar, dass das zweite
// case hinter der nil-Zuweisung beginnt und schon dort uebersprungen wird -
// nur haengt das Ergebnis nicht daran. Nimmt man den Filter heraus, liefert
// ArmHolding fuer die nil-Zuweisung im zweiten case trotzdem nil und die
// Schleife enthaelt sich genauso. Der Filter ist per Parser-Invariante
// ergebnisneutral und damit ueberhaupt nicht durch einen Test absicherbar -
// die Begruendung steht bei CaseStartsAfterEither in uNilDeref.pas. Was
// dieser Test wirklich haelt, ist die Aussage im Namen: Arme ZWEIER case
// trennen nichts.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k, m: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: with Owner do x := nil;'#13#10 +
  '    1: DoOther;'#13#10 +
  '  end;'#13#10 +
  '  case m of'#13#10 +
  '    0: x.DoStuff;'#13#10 +
  '    1: DoMore;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'Arme ZWEIER case trennen nichts - Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.DerefAfterInnerCaseInSameOuterArm_StillReported;
// Gegenstueck zu ExclusiveNestedCaseInnerArms_NotReported: nil in Arm 0 des
// INNEREN case, Deref dahinter - beide im SELBEN Arm 0 des aeusseren case.
// Das aeussere case findet beide im gleichen Arm (kein Beweis), das innere
// findet nur die nil-Zuweisung (kein Beweis). Sequentiell erreichbar, der
// Fund ist echt.
// Rot, wenn ein case, das beide Knoten irgendwo enthaelt, als Trennung
// zaehlen wuerde - oder wenn ArmHolding beim inneren case den Deref faelsch-
// lich einem Arm zuschlagen wuerde.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k, m: Integer);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  case k of'#13#10 +
  '    0: begin'#13#10 +
  '         case m of'#13#10 +
  '           0: with Owner do x := nil;'#13#10 +
  '           1: DoOther;'#13#10 +
  '         end;'#13#10 +
  '         x.DoStuff;'#13#10 +
  '       end;'#13#10 +
  '    1: DoMore;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'inneres case trennt nicht, aeusseres haelt beide im selben Arm - Fund bleibt');
  finally F.Free; end;
end;

{ Die drei Schleifenformen des Vetos (Nachzug MINOR 1, 2026-08-28).
  Kein 'with' im ersten Fall - genau darum geht es: er soll durch den CFG
  laufen. Die beiden Nachbarn behalten den Hebel, damit dort wirklich nur
  die Kind-Menge in NodeIsInsideLoop antwortet und nicht der CFG. }

procedure TTestNilDeref.PlainLoopAroundCaseArms_StillReported;
// DIE NACKTE while-FORM. Der Doppelwaechter, den LoopAroundCaseArms_
// StillReported nicht sein kann, weil dessen with-Hebel den CFG aussperrt.
// Hier laeuft der Fall durch beide Mechanismen, und er ist rot, sobald EINER
// von beiden faellt:
//   * nimmt jemand das Schleifen-Veto aus InDifferentCaseArms heraus, droppt
//     die Arm-Pruefung den Fund noch VOR dem CFG - rot;
//   * entfernt jemand in uCFG die Rueckkante (Z.513 'Connect(BodyTail,
//     LoopHead)') oder aendert CanReach so, dass Arm 1 von Arm 0 aus
//     unerreichbar wird, droppt CfgDropsNilDeref - ebenfalls rot.
// Damit haengt die BEGRUENDUNG des Vetos ("der Fall ist beim CFG geloest, ein
// Gate davor darf die Loesung nicht wegwerfen") erstmals an einer Assertion
// statt nur an einem Kommentar. Echter Fund: Iteration 1 nimmt Arm 0, setzt x
// auf nil, Iteration 2 nimmt Arm 1 und dereferenziert.
// Erwarteter Weg heute: kein Arm-Drop (Veto), NilBlk = Arm-0-Block,
// DerefBlk = Arm-1-Block, CanReach ueber CaseMerge -> LoopHead -> BodyStart
// -> BranchBlk -> Arm 1 = True, also kein CFG-Drop.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer; c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  while c do'#13#10 +
  '    case k of'#13#10 +
  '      0: x := nil;'#13#10 +
  '      1: x.DoStuff;'#13#10 +
  '    end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'while um das case - Veto UND CFG-Rueckkante muessen den Fund halten');
  finally F.Free; end;
end;

procedure TTestNilDeref.RepeatAroundCaseArms_StillReported;
// repeat..until. Dass das Veto auch diese Schleifenform mitnimmt, stand bis
// heute nur in der Kind-Menge [nkWhileStmt, nkForStmt, nkRepeatStmt] von
// NodeIsInsideLoop - keine Assertion hielt es fest.
// BEWEIS, nicht Waechter: mit 'with' bleibt CfgDropsNilDeref draussen
// (NilBlk = nil), das Veto ist also das einzige Netz. Streicht man
// nkRepeatStmt aus der Menge, droppt die Arm-Pruefung und der Test wird ROT.
// Der Fund ist echt - Durchlauf 1 nimmt Arm 0, Durchlauf 2 Arm 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer; c: Boolean);'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  repeat'#13#10 +
  '    case k of'#13#10 +
  '      0: with Owner do x := nil;'#13#10 +
  '      1: x.DoStuff;'#13#10 +
  '    end;'#13#10 +
  '  until c;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'repeat um das case - zwei Durchlaeufe nehmen beide Arme, Fund bleibt');
  finally F.Free; end;
end;

procedure TTestNilDeref.ForAroundCaseArms_StillReported;
// for-Schleife, dritte Form der Kind-Menge. Gleiche Bauweise und gleiche
// Beweiskraft wie der repeat-Fall: ohne nkForStmt in NodeIsInsideLoop ROT.
// IsForLoopAssigned kommt hier NICHT dazwischen, zweifach geprueft
// (uNilDeref.pas:323 im Original, jetzt in derselben Routine): die Schleife
// steigt bei 'FN.Line <= AfterLine' aus, und das for steht VOR der
// nil-Zuweisung; ausserdem ist der Header 'i := 0 to 9', beginnt also nicht
// mit 'x := '. Es waere sonst ein stiller Zweitgrund fuer Gruen und der Test
// wuerde am Veto vorbeimessen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(k: Integer);'#13#10 +
  'var'#13#10 +
  '  x: TObject;'#13#10 +
  '  i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    case k of'#13#10 +
  '      0: with Owner do x := nil;'#13#10 +
  '      1: x.DoStuff;'#13#10 +
  '    end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'for um das case - zwei Iterationen nehmen beide Arme, Fund bleibt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNilDeref);

end.
