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

initialization
  TDUnitX.RegisterTestFixture(TTestNilDeref);

end.
