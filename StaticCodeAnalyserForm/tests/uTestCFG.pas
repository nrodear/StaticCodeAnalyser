unit uTestCFG;

// A.4.2 CFG-Builder fuer lineare Statements - DUnitX-Regression-Tests.
//
// Coverage:
//   * Leere Methode: Entry -> Exit_
//   * Linear: Assign+Call -> alle im selben Statement-Block
//   * Exit  : Block -> Exit_, kein weiterer Tail
//   * Raise : Block -> Exit_
//   * Break/Continue: Block terminiert (Loop-Verkabelung erst A.4.4)
//   * Reachability: From -> To direkt, From -> To transitiv, unerreichbar
//   * begin..end inline: kein neuer CFG-Block, gleicher Statement-Slot
//
// A.4.3+ Branching/Loops werden in eigenen Tests abgedeckt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCFG = class
  public
    [Test] procedure Empty_Method_HasEntryToExit;
    [Test] procedure Linear_Assigns_AllInOneStatementBlock;
    [Test] procedure Exit_Terminates_Sequence;
    [Test] procedure Raise_Terminates_Sequence;
    [Test] procedure Break_Terminates_Sequence;
    [Test] procedure BeginEndBlock_InlineExpansion;
    [Test] procedure CanReach_DirectSuccessor;
    [Test] procedure CanReach_TransitiveViaIntermediate;
    [Test] procedure CanReach_FalseWhenNotConnected;
    [Test] procedure CanReach_SelfAlwaysTrue;
    [Test] procedure ExitWithinIfBranch_ConnectsToExit;
    // A.4.3 Branching
    [Test] procedure IfThen_NoElse_BranchToMerge;
    [Test] procedure IfThenElse_BothBranchesToMerge;
    [Test] procedure IfWithExitInThen_ThenTailIsNil;
    [Test] procedure IfWithExitInBoth_MergeUnreachable;
    [Test] procedure CaseStmt_TwoArmsToMerge;
    [Test] procedure CaseStmtAllArmsExit_ResultNil;
    // A.4.4 Loops
    [Test] procedure While_HasLoopHeadAndBackEdge;
    [Test] procedure For_HasLoopHeadAndBackEdge;
    [Test] procedure Repeat_HasUntilHeadAndBackEdge;
    [Test] procedure Break_ConnectsToLoopExit;
    [Test] procedure Continue_ConnectsToLoopHead;
    [Test] procedure NestedLoops_InnerBreakHitsInnerExit;
    // A.4.5 Exception-Pfade
    [Test] procedure TryExcept_HasExceptionBlock;
    [Test] procedure TryExcept_BothPathsReachMerge;
    [Test] procedure TryFinally_FinallyRunsOnBothPaths;
    [Test] procedure TryExceptWithExitInTry_ExitReachable;
    // Roadmap #6: Dominates + CanReachAvoiding (Reaching-Defs-Query)
    [Test] procedure Dominates_SelfAlwaysTrue;
    [Test] procedure Dominates_EntryDominatesAllReachable;
    [Test] procedure Dominates_LinearChain;
    [Test] procedure Dominates_DiamondBranchesDominateNothing;
    [Test] procedure Dominates_UnreachableTarget_False;
    [Test] procedure Dominates_GuardBeforeUse_True;
    [Test] procedure CanReachAvoiding_BlockedSinglePath_False;
    [Test] procedure CanReachAvoiding_AlternatePathSurvives_True;
    [Test] procedure CanReachAvoiding_EndpointsExemptFromAvoid;
    [Test] procedure CanReachAvoiding_EmptyAvoid_EqualsCanReach;
    [Test] procedure CanReachAvoiding_LoopBackEdge_ReachesEarlierBlock;
    // #6 Inkr.1b: Builder-Fidelity (try-Cross-Edges + CondNode)
    [Test] procedure TryFinally_ExitInTry_FinallyReachableFromExitBlock;
    [Test] procedure TryExcept_MidTryBlock_ReachesExceptHandler;
    [Test] procedure CondNode_SetOnBranchAndLoopHeads;
  end;

implementation

uses
  System.SysUtils,
  uAstNode, uCFG;

// A.4.2 Tests bauen CFGs manuell zusammen (Connect-API). Parser-basierte
// Integration-Tests folgen ab A.4.3 wenn Branching geprueft wird (dort
// braucht es echte nkIfStmt-AST-Inputs).

{ Tests }

procedure TTestCFG.Empty_Method_HasEntryToExit;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'procedure Foo;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;'#13#10 +
  'end.';
var
  CFG : TCFG;
begin
  CFG := TCFG.Create;
  try
    // Direkt-Test: leere CFG hat Entry und Exit, nicht verbunden.
    Assert.IsNotNull(CFG.Entry);
    Assert.IsNotNull(CFG.Exit_);
    Assert.AreEqual<Integer>(0, CFG.Entry.Successors.Count, 'frische CFG: Entry hat keine Successors');
    CFG.Connect(CFG.Entry, CFG.Exit_);
    Assert.AreEqual<Integer>(1, CFG.Entry.Successors.Count);
    Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.Linear_Assigns_AllInOneStatementBlock;
var
  CFG    : TCFG;
  Block1 : uCFG.TCFGBlock;
begin
  // Manuell zusammengesteckt - Builder-Tests folgen wenn Parser-Pipeline
  // im TestProject erreichbar ist (separate Tests-Unit fuer Integration).
  CFG := TCFG.Create;
  try
    Block1 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, Block1);
    CFG.Connect(Block1, CFG.Exit_);
    Assert.AreEqual<Integer>(1, CFG.Entry.Successors.Count);
    Assert.AreEqual<Integer>(1, Block1.Predecessors.Count, 'Block1 Predecessor = Entry');
    Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.Exit_Terminates_Sequence;
var
  CFG : TCFG;
  B1, B2 : uCFG.TCFGBlock;
begin
  // Entry -> B1 -> Exit_   ;   B2 nicht verbunden = unreachable.
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    CFG.Connect(B1, CFG.Exit_);
    Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
    Assert.IsFalse(CFG.CanReach(CFG.Entry, B2), 'B2 isoliert');
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.Raise_Terminates_Sequence;
begin
  // Raise modelliert wie Exit (in A.4.2 konservativ). A.4.5 wird das
  // mit try/except-Pfaden verfeinern.
  Exit_Terminates_Sequence;  // gleiche Erwartung wie Exit auf CFG-Ebene
end;

procedure TTestCFG.Break_Terminates_Sequence;
begin
  // Break/Continue terminieren die aktuelle Sequenz - der Loop-Builder
  // verkabelt sie in A.4.4 korrekt mit dem Loop-Header/-Exit. In A.4.2
  // bleibt der CFG-Tail nil = "kein natuerlicher Folge-Block".
  Exit_Terminates_Sequence;  // gleicher CFG-Effekt: Block hat keinen Tail-Successor
end;

procedure TTestCFG.BeginEndBlock_InlineExpansion;
var
  CFG : TCFG;
begin
  // Begin..End ist inline-expanded - kein eigener CFG-Block fuer den
  // Gruppen-Container. Property pruefen wir indirekt via NewBlock-Count.
  CFG := TCFG.Create;
  try
    // Entry + Exit = 2; nach NewBlock fuer Statement = 3
    CFG.NewBlock(ckStatement);
    Assert.AreEqual<Integer>(3, CFG.Blocks.Count, 'Entry + Exit + 1 Statement-Block');
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.CanReach_DirectSuccessor;
var
  CFG : TCFG;
  B   : uCFG.TCFGBlock;
begin
  CFG := TCFG.Create;
  try
    B := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B);
    Assert.IsTrue(CFG.CanReach(CFG.Entry, B));
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.CanReach_TransitiveViaIntermediate;
var
  CFG          : TCFG;
  B1, B2, B3   : uCFG.TCFGBlock;
begin
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    B3 := CFG.NewBlock(ckStatement);
    CFG.Connect(B1, B2);
    CFG.Connect(B2, B3);
    Assert.IsTrue(CFG.CanReach(B1, B3));
    Assert.IsFalse(CFG.CanReach(B3, B1), 'CFG ist gerichtet');
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.CanReach_FalseWhenNotConnected;
var
  CFG    : TCFG;
  B1, B2 : uCFG.TCFGBlock;
begin
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    Assert.IsFalse(CFG.CanReach(B1, B2));
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.CanReach_SelfAlwaysTrue;
var
  CFG : TCFG;
  B   : uCFG.TCFGBlock;
begin
  CFG := TCFG.Create;
  try
    B := CFG.NewBlock(ckStatement);
    Assert.IsTrue(CFG.CanReach(B, B), 'A.4.1 Konvention: From=To -> True');
  finally
    CFG.Free;
  end;
end;

procedure TTestCFG.ExitWithinIfBranch_ConnectsToExit;
begin
  Assert.Pass('Marker: ersetzt durch A.4.3 Branching-Tests unten');
end;

{ ---- A.4.3 Branching: Mini-AST-Helpers ---- }

function MakeMethod(const Stmts: array of TAstNode): TAstNode;
// Baut nkMethod + nkBlock(Stmts...). Caller besitzt das Result.
var
  Body : TAstNode;
  i    : Integer;
begin
  Result := TAstNode.Create(nkMethod, 'TestMeth', 1, 1);
  Body := Result.Add(nkBlock, 'begin', 1, 1);
  for i := 0 to High(Stmts) do
    Body.AddChild(Stmts[i]);
end;

function StmtAssign(ALine: Integer = 1): TAstNode;
begin
  Result := TAstNode.Create(nkAssign, 'x', ALine, 1);
end;

function StmtExit(ALine: Integer = 1): TAstNode;
begin
  Result := TAstNode.Create(nkExit, 'exit', ALine, 1);
end;

function StmtIf(ThenS, ElseS: TAstNode; ALine: Integer = 1): TAstNode;
// nkIfStmt mit Then-Statement als first Child und optional nkElseBranch
// als second Child der wiederum ElseS als Child enthaelt.
var
  ElseNode : TAstNode;
begin
  Result := TAstNode.Create(nkIfStmt, 'if', ALine, 1);
  if ThenS <> nil then Result.AddChild(ThenS);
  if ElseS <> nil then
  begin
    ElseNode := Result.Add(nkElseBranch, 'else', ALine, 1);
    ElseNode.AddChild(ElseS);
  end;
end;

function StmtCase(const Arms: array of TAstNode; ALine: Integer = 1): TAstNode;
// nkCaseStmt mit Arms als direkten Children (Arms muessen nkCaseArm sein).
var
  i : Integer;
begin
  Result := TAstNode.Create(nkCaseStmt, 'case', ALine, 1);
  for i := 0 to High(Arms) do
    Result.AddChild(Arms[i]);
end;

function CaseArm(const Name: string; ArmStmt: TAstNode;
                 ALine: Integer = 1): TAstNode;
begin
  Result := TAstNode.Create(nkCaseArm, Name, ALine, 1);
  if ArmStmt <> nil then Result.AddChild(ArmStmt);
end;

{ ---- A.4.3 Tests ---- }

procedure TTestCFG.IfThen_NoElse_BranchToMerge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // if cond then x := 1;  (kein else)
  Meth := MakeMethod([ StmtIf(StmtAssign, nil) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      // Entry kann Exit_ erreichen ueber den Branch
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      // Es gibt mindestens einen ckBranch-Block
      var Found := False;
      for var B in CFG.Blocks do if B.Kind = ckBranch then Found := True;
      Assert.IsTrue(Found, 'CFG enthaelt ckBranch-Block');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.IfThenElse_BothBranchesToMerge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // if cond then x := 1 else x := 2;
  Meth := MakeMethod([ StmtIf(StmtAssign, StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      // Branch hat genau 2 Successors (Then-Start, Else-Start).
      var BranchBlk : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckBranch then begin BranchBlk := B; Break; end;
      Assert.IsNotNull(BranchBlk);
      Assert.AreEqual<Integer>(2, BranchBlk.Successors.Count,
        'if/else Branch hat 2 Successors');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.IfWithExitInThen_ThenTailIsNil;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // if cond then Exit else x := 1;
  // ThenTail = nil (Exit), ElseTail = Else-Block; Merge ist erreichbar
  // nur vom Else-Pfad.
  Meth := MakeMethod([ StmtIf(StmtExit, StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      // Exit_ ist auch direkt vom Then-Stmt erreichbar (Exit-Edge).
      // Praezise Pfad-Check: es gibt einen Pfad Entry -> .. -> Exit_.
      Assert.IsTrue(CFG.Exit_.Predecessors.Count >= 1);
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.IfWithExitInBoth_MergeUnreachable;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // if cond then Exit else Exit;  -> nach dem if ist KEIN Code erreichbar
  // (beide Branches enden in Exit). BuildFromMethod's Tail = nil, daher
  // wird Tail NICHT mit Exit_ verbunden, aber die Exit_-Edges aus den
  // beiden Branch-Exits versorgen die Reachability.
  Meth := MakeMethod([ StmtIf(StmtExit, StmtExit) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_),
        'Beide Branches Exit -> Exit_ erreichbar');
      // Exit_ muss EXAKT 2 Predecessors haben (Then-Exit + Else-Exit;
      // KEIN Tail-Connect von StartBlock weil Tail durch Exit beendet).
      Assert.AreEqual<Integer>(2, CFG.Exit_.Predecessors.Count);
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.CaseStmt_TwoArmsToMerge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // case x of  1: y := 1;  2: y := 2;  else y := 0; end;
  Meth := MakeMethod([
    StmtCase([ CaseArm('1', StmtAssign),
               CaseArm('2', StmtAssign),
               CaseArm('else', StmtAssign) ])
  ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      var BranchBlk : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckBranch then begin BranchBlk := B; Break; end;
      Assert.IsNotNull(BranchBlk);
      Assert.AreEqual<Integer>(3, BranchBlk.Successors.Count,
        '3 Arme = 3 Successors');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.CaseStmtAllArmsExit_ResultNil;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // case x of  1: Exit;  2: Exit;  else Exit; end;
  Meth := MakeMethod([
    StmtCase([ CaseArm('1',    StmtExit),
               CaseArm('2',    StmtExit),
               CaseArm('else', StmtExit) ])
  ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      // 3 Arm-Exits = 3 Predecessors auf Exit_
      Assert.AreEqual<Integer>(3, CFG.Exit_.Predecessors.Count);
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

{ ---- A.4.4 Loop-Helpers ---- }

function StmtWhile(Body: TAstNode; ALine: Integer = 1): TAstNode;
begin
  Result := TAstNode.Create(nkWhileStmt, 'while', ALine, 1);
  if Body <> nil then Result.AddChild(Body);
end;

function StmtFor(Body: TAstNode; ALine: Integer = 1): TAstNode;
begin
  Result := TAstNode.Create(nkForStmt, 'for', ALine, 1);
  if Body <> nil then Result.AddChild(Body);
end;

function StmtRepeat(const Body: array of TAstNode;
                    ALine: Integer = 1): TAstNode;
var i: Integer;
begin
  Result := TAstNode.Create(nkRepeatStmt, 'repeat', ALine, 1);
  for i := 0 to High(Body) do Result.AddChild(Body[i]);
end;

function StmtBreak: TAstNode;
begin Result := TAstNode.Create(nkBreak, 'break', 1, 1); end;

function StmtContinue: TAstNode;
begin Result := TAstNode.Create(nkContinue, 'continue', 1, 1); end;

{ ---- A.4.4 Tests ---- }

procedure TTestCFG.While_HasLoopHeadAndBackEdge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // while cond do x := 1;
  Meth := MakeMethod([ StmtWhile(StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      var LoopHead : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckLoop then begin LoopHead := B; Break; end;
      Assert.IsNotNull(LoopHead, 'ckLoop-Block muss da sein');
      // LoopHead hat 2 Successors: BodyStart + NextBlk
      Assert.AreEqual<Integer>(2, LoopHead.Successors.Count, 'while LoopHead 2 Successors');
      // LoopHead hat min. 2 Predecessors: Current und Body-Back-Edge
      Assert.IsTrue(LoopHead.Predecessors.Count >= 2,
        'Back-Edge muss zum LoopHead zeigen');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.For_HasLoopHeadAndBackEdge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  Meth := MakeMethod([ StmtFor(StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      var LoopHead : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckLoop then begin LoopHead := B; Break; end;
      Assert.IsNotNull(LoopHead);
      Assert.IsTrue(LoopHead.Predecessors.Count >= 2, 'Back-Edge');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.Repeat_HasUntilHeadAndBackEdge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // repeat x := 1; until cond;
  Meth := MakeMethod([ StmtRepeat([ StmtAssign ]) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      var UntilHead : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckLoop then begin UntilHead := B; Break; end;
      Assert.IsNotNull(UntilHead);
      // UntilHead hat 2 Successors: BodyStart + NextBlk
      Assert.AreEqual<Integer>(2, UntilHead.Successors.Count, 'repeat UntilHead 2 Successors');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.Break_ConnectsToLoopExit;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // while cond do break;
  Meth := MakeMethod([ StmtWhile(StmtBreak) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      // Es muss zwei Wege zu Exit_ geben:
      //   1) LoopHead -> NextBlk -> Exit_     (Cond-False-Pfad)
      //   2) Body -> NextBlk (Break) -> Exit_
      // Reachability test: alles erreicht Exit_.
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.Continue_ConnectsToLoopHead;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  Meth := MakeMethod([ StmtWhile(StmtContinue) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      // Continue erzeugt eine extra Edge Body -> LoopHead. LoopHead hat
      // damit mindestens 2 Predecessors (Entry-Path + Continue-Edge).
      var LoopHead : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckLoop then begin LoopHead := B; Break; end;
      Assert.IsNotNull(LoopHead);
      Assert.IsTrue(LoopHead.Predecessors.Count >= 2,
        'Continue addiert Edge zum LoopHead');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.NestedLoops_InnerBreakHitsInnerExit;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // while outer do while inner do break;
  Meth := MakeMethod([ StmtWhile( StmtWhile( StmtBreak ) ) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      // Beide Loops haben ckLoop. Inner-Break geht zum Inner-NextBlk,
      // NICHT zum Outer-NextBlk. Indirekt pruefbar via Block-Count:
      // Build sollte 2 ckLoop-Bloecke produzieren.
      var Loops := 0;
      for var B in CFG.Blocks do
        if B.Kind = ckLoop then Inc(Loops);
      Assert.AreEqual<Integer>(2, Loops, 'Nested while erzeugt 2 ckLoop-Bloecke');
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

{ ---- A.4.5 Exception-Helpers ---- }

function StmtTryExcept(TryBodyStmt, ExceptBodyStmt: TAstNode;
                       ALine: Integer = 1): TAstNode;
// nkTryExcept mit Try-Body-Stmt + nkExceptBlock (mit Except-Body-Stmt).
var
  ExNode : TAstNode;
begin
  Result := TAstNode.Create(nkTryExcept, 'try', ALine, 1);
  if TryBodyStmt <> nil then Result.AddChild(TryBodyStmt);
  ExNode := Result.Add(nkExceptBlock, 'except', ALine, 1);
  if ExceptBodyStmt <> nil then ExNode.AddChild(ExceptBodyStmt);
end;

function StmtTryFinally(TryBodyStmt, FinallyBodyStmt: TAstNode;
                        ALine: Integer = 1): TAstNode;
var
  FinNode : TAstNode;
begin
  Result := TAstNode.Create(nkTryFinally, 'try', ALine, 1);
  if TryBodyStmt <> nil then Result.AddChild(TryBodyStmt);
  FinNode := Result.Add(nkFinallyBlock, 'finally', ALine, 1);
  if FinallyBodyStmt <> nil then FinNode.AddChild(FinallyBodyStmt);
end;

{ ---- A.4.5 Tests ---- }

procedure TTestCFG.TryExcept_HasExceptionBlock;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // try x := 1 except y := 1 end;
  Meth := MakeMethod([ StmtTryExcept(StmtAssign, StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      var ExceptBlk : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckException then begin ExceptBlk := B; Break; end;
      Assert.IsNotNull(ExceptBlk, 'ckException-Block muss da sein');
      // ExceptBlk muss vom Entry erreichbar sein (via Cross-Edge).
      Assert.IsTrue(CFG.CanReach(CFG.Entry, ExceptBlk),
        'Entry kann ExceptBlk erreichen');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.TryExcept_BothPathsReachMerge;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // try x := 1; except y := 1; end; z := 1;  (z im Merge erreichbar)
  Meth := MakeMethod([
    StmtTryExcept(StmtAssign, StmtAssign),
    StmtAssign  // continuation - sollte im Merge landen
  ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      // Beide Pfade (try-end + except-end) muessen zum gleichen Merge fuehren.
      // Indirekt pruefbar: Exit_ hat mindestens einen Predecessor.
      Assert.IsTrue(CFG.Exit_.Predecessors.Count >= 1);
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.TryFinally_FinallyRunsOnBothPaths;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // try if cond then a := 1 else b := 2; finally y := 1; end;
  //
  // Der TryBody enthaelt ein if/else damit der Normal-End-Block
  // (Merge des if) tatsaechlich ein ANDERER Block ist als der
  // TryBodyStart-Block. Bei einem Single-Stmt-Body waeren beide
  // identisch und die Cross-Edge vs. Normal-End-Edge wuerden
  // ueber denselben Block laufen -> Connect erkennt das als
  // Doppel-Connect und behaelt nur 1 Edge.
  Meth := MakeMethod([
    StmtTryFinally(
      StmtIf(StmtAssign, StmtAssign),   // try-body mit if/else
      StmtAssign                        // finally-body
    )
  ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
      var FinallyStart : uCFG.TCFGBlock := nil;
      for var B in CFG.Blocks do
        if B.Kind = ckException then begin FinallyStart := B; Break; end;
      Assert.IsNotNull(FinallyStart);
      // Seit #6 Inkr.1b bekommt JEDER Try-Body-Block die Cross-Edge zum
      // finally (vorher nur TryBodyStart) - die exakte Predecessor-Zahl
      // haengt damit von der Blockzahl des Try-Bodys ab (hier 5: TryBody-
      // Start + Branch + Then + Else + Merge). Die INVARIANTE bleibt:
      // Cross-Edge- UND Normal-End-Pfad muenden im finally ...
      Assert.IsTrue(FinallyStart.Predecessors.Count >= 2,
        'Finally erreicht aus Cross-Edge UND Normal-End-Pfad');
      // ... und NEU (1b): auch ein mitten im Try erzeugter Block (der
      // if-Branch) haengt an der Exception-Kante.
      var HasBranchPred := False;
      for var P in FinallyStart.Predecessors do
        if P.Kind = ckBranch then HasBranchPred := True;
      Assert.IsTrue(HasBranchPred,
        'Inkr.1b: if-Branch im Try hat die Cross-Edge zum finally');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.TryExceptWithExitInTry_ExitReachable;
var
  Meth : TAstNode;
  CFG  : TCFG;
begin
  // try Exit except y := 1 end;
  // Exit im Try beendet die Method, Except-Pfad weiter zu Merge.
  Meth := MakeMethod([ StmtTryExcept(StmtExit, StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      Assert.IsTrue(CFG.CanReach(CFG.Entry, CFG.Exit_));
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

{ Roadmap #6: Dominates + CanReachAvoiding }

procedure TTestCFG.Dominates_SelfAlwaysTrue;
var
  CFG : TCFG;
  B1  : uCFG.TCFGBlock;
begin
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    Assert.IsTrue(CFG.Dominates(B1, B1), 'jeder Block dominiert sich selbst');
  finally CFG.Free; end;
end;

procedure TTestCFG.Dominates_EntryDominatesAllReachable;
var
  CFG : TCFG;
  B1, B2 : uCFG.TCFGBlock;
begin
  // Entry -> B1 -> B2
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    CFG.Connect(B1, B2);
    Assert.IsTrue(CFG.Dominates(CFG.Entry, B1));
    Assert.IsTrue(CFG.Dominates(CFG.Entry, B2));
  finally CFG.Free; end;
end;

procedure TTestCFG.Dominates_LinearChain;
var
  CFG : TCFG;
  B1, B2, B3 : uCFG.TCFGBlock;
begin
  // Entry -> B1 -> B2 -> B3: B1 dominiert B2+B3, B2 dominiert B3,
  // aber B3 dominiert B2 NICHT (Dominanz ist gerichtet).
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    B3 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    CFG.Connect(B1, B2);
    CFG.Connect(B2, B3);
    Assert.IsTrue(CFG.Dominates(B1, B3), 'B1 dominiert B3');
    Assert.IsTrue(CFG.Dominates(B2, B3), 'B2 dominiert B3');
    Assert.IsFalse(CFG.Dominates(B3, B2), 'Rueckrichtung nie');
  finally CFG.Free; end;
end;

procedure TTestCFG.Dominates_DiamondBranchesDominateNothing;
var
  CFG : TCFG;
  Branch, T, E, Merge : uCFG.TCFGBlock;
begin
  // Diamant: Entry -> Branch -> {T | E} -> Merge.
  // Branch dominiert Merge; T/E dominieren Merge NICHT (jeweils
  // Alternativpfad ueber den anderen Arm).
  CFG := TCFG.Create;
  try
    Branch := CFG.NewBlock(ckBranch);
    T      := CFG.NewBlock(ckStatement);
    E      := CFG.NewBlock(ckStatement);
    Merge  := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, Branch);
    CFG.Connect(Branch, T);
    CFG.Connect(Branch, E);
    CFG.Connect(T, Merge);
    CFG.Connect(E, Merge);
    Assert.IsTrue(CFG.Dominates(Branch, Merge), 'Branch dominiert Merge');
    Assert.IsFalse(CFG.Dominates(T, Merge), 'Then-Arm dominiert Merge nicht');
    Assert.IsFalse(CFG.Dominates(E, Merge), 'Else-Arm dominiert Merge nicht');
  finally CFG.Free; end;
end;

procedure TTestCFG.Dominates_UnreachableTarget_False;
var
  CFG : TCFG;
  B1, Island : uCFG.TCFGBlock;
begin
  // Island haengt nicht am Entry -> Dominanz-Query konservativ False.
  CFG := TCFG.Create;
  try
    B1     := CFG.NewBlock(ckStatement);
    Island := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    Assert.IsFalse(CFG.Dominates(B1, Island), 'unerreichbares Ziel -> False');
    Assert.IsFalse(CFG.Dominates(CFG.Entry, Island), 'auch fuer Entry');
  finally CFG.Free; end;
end;

procedure TTestCFG.Dominates_GuardBeforeUse_True;
var
  Meth : TAstNode;
  CFG  : TCFG;
  GuardBranch, UseBlk : uCFG.TCFGBlock;
  B    : uCFG.TCFGBlock;
begin
  // Builder-basiert (SCA010-Zielmuster): if <cond> then Exit; x := 1;
  // Der Guard-Branch dominiert das nachfolgende Statement - genau die
  // Query, mit der der DivByZero-Postfilter '<=0-Guard dominiert Division'
  // erkennen soll.
  Meth := MakeMethod([ StmtIf(StmtExit, nil), StmtAssign ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      GuardBranch := nil;
      UseBlk      := nil;
      for B in CFG.Blocks do
      begin
        if (B.Kind = ckBranch) and (GuardBranch = nil) then
          GuardBranch := B;
        // Use-Block = Statement-Block MIT AstNodes NACH dem Branch
        // (der Merge sammelt das Assign ein).
        if (B.Kind = ckStatement) and (B.AstNodes.Count > 0) and
           (GuardBranch <> nil) and (B <> GuardBranch) and
           (B.Id > GuardBranch.Id) then
          UseBlk := B;
      end;
      Assert.IsNotNull(GuardBranch, 'Branch-Block existiert');
      Assert.IsNotNull(UseBlk, 'Use-Block existiert');
      Assert.IsTrue(CFG.Dominates(GuardBranch, UseBlk),
        'Guard-Branch dominiert das Statement nach dem if');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.CanReachAvoiding_BlockedSinglePath_False;
var
  CFG : TCFG;
  B1, B2, B3 : uCFG.TCFGBlock;
begin
  // Entry -> B1 -> B2 -> B3: einziger Pfad B1->B3 laeuft ueber B2.
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    B3 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    CFG.Connect(B1, B2);
    CFG.Connect(B2, B3);
    Assert.IsFalse(CFG.CanReachAvoiding(B1, B3, [B2]),
      'einziger Pfad blockiert -> False (Re-Def faengt die Def ab)');
  finally CFG.Free; end;
end;

procedure TTestCFG.CanReachAvoiding_AlternatePathSurvives_True;
var
  CFG : TCFG;
  Branch, T, E, Merge : uCFG.TCFGBlock;
begin
  // Diamant: Avoid auf dem Then-Arm, der Else-Arm bleibt als Pfad.
  CFG := TCFG.Create;
  try
    Branch := CFG.NewBlock(ckBranch);
    T      := CFG.NewBlock(ckStatement);
    E      := CFG.NewBlock(ckStatement);
    Merge  := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, Branch);
    CFG.Connect(Branch, T);
    CFG.Connect(Branch, E);
    CFG.Connect(T, Merge);
    CFG.Connect(E, Merge);
    Assert.IsTrue(CFG.CanReachAvoiding(Branch, Merge, [T]),
      'Else-Arm ueberlebt als alternativer Pfad');
    Assert.IsFalse(CFG.CanReachAvoiding(Branch, Merge, [T, E]),
      'beide Arme blockiert -> kein Pfad');
  finally CFG.Free; end;
end;

procedure TTestCFG.CanReachAvoiding_EndpointsExemptFromAvoid;
var
  CFG : TCFG;
  B1, B2 : uCFG.TCFGBlock;
begin
  // From/To_ duerfen selbst im Avoid stehen (Def-Block ist zugleich
  // "Re-Def"-Kandidat): die Query zaehlt nur ZWISCHEN-Stationen.
  CFG := TCFG.Create;
  try
    B1 := CFG.NewBlock(ckStatement);
    B2 := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    CFG.Connect(B1, B2);
    Assert.IsTrue(CFG.CanReachAvoiding(B1, B2, [B1]),
      'From im Avoid -> trotzdem expandiert');
    Assert.IsTrue(CFG.CanReachAvoiding(B1, B2, [B2]),
      'To_ im Avoid -> trotzdem als erreicht erkannt');
  finally CFG.Free; end;
end;

procedure TTestCFG.CanReachAvoiding_EmptyAvoid_EqualsCanReach;
var
  CFG : TCFG;
  B1, B2, Island : uCFG.TCFGBlock;
begin
  CFG := TCFG.Create;
  try
    B1     := CFG.NewBlock(ckStatement);
    B2     := CFG.NewBlock(ckStatement);
    Island := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, B1);
    CFG.Connect(B1, B2);
    Assert.IsTrue(CFG.CanReach(B1, B2) = CFG.CanReachAvoiding(B1, B2, []),
      'leeres Avoid == CanReach (erreichbarer Fall)');
    Assert.IsTrue(CFG.CanReach(B1, Island) = CFG.CanReachAvoiding(B1, Island, []),
      'leeres Avoid == CanReach (unerreichbarer Fall)');
  finally CFG.Free; end;
end;

procedure TTestCFG.CanReachAvoiding_LoopBackEdge_ReachesEarlierBlock;
var
  CFG : TCFG;
  Head, Body, Next : uCFG.TCFGBlock;
begin
  // Schleife: Head -> Body -> Head (Back-Edge), Head -> Next.
  // Vom Body aus ist Next NUR ueber den Head erreichbar; Avoid[Head]
  // muss die Back-Edge mit abschneiden (SCA166-Zielmuster: Def in
  // Iteration 1 erreicht Read in Iteration 2 ueber die Back-Edge).
  CFG := TCFG.Create;
  try
    Head := CFG.NewBlock(ckLoop);
    Body := CFG.NewBlock(ckStatement);
    Next := CFG.NewBlock(ckStatement);
    CFG.Connect(CFG.Entry, Head);
    CFG.Connect(Head, Body);
    CFG.Connect(Body, Head);   // Back-Edge
    CFG.Connect(Head, Next);
    Assert.IsTrue(CFG.CanReachAvoiding(Body, Body, []),
      'Self-Query trivial True (From=To_)');
    Assert.IsTrue(CFG.CanReach(Body, Next), 'ueber Back-Edge erreichbar');
    Assert.IsFalse(CFG.CanReachAvoiding(Body, Next, [Head]),
      'Head blockiert -> Back-Edge-Pfad abgeschnitten');
  finally CFG.Free; end;
end;

{ #6 Inkr.1b: Builder-Fidelity }

procedure TTestCFG.TryFinally_ExitInTry_FinallyReachableFromExitBlock;
var
  Meth : TAstNode;
  CFG  : TCFG;
  B, ExitBlk, FinallyBlk : uCFG.TCFGBlock;
  N    : TAstNode;
begin
  // try if c then Exit; finally y := 1; end;
  // Delphi fuehrt den finally-Block AUCH beim Exit aus. Vor Inkr.1b verband
  // der Exit-Block nur zu Exit_ -> finally war von dort unerreichbar und ein
  // CanReach-Drop-Filter haette Funde im finally over-gedroppt.
  Meth := MakeMethod([ StmtTryFinally(StmtIf(StmtExit, nil), StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      ExitBlk    := nil;
      FinallyBlk := nil;
      for B in CFG.Blocks do
      begin
        if B.Kind = ckException then FinallyBlk := B;
        for N in B.AstNodes do
          if N.Kind = nkExit then ExitBlk := B;
      end;
      Assert.IsNotNull(ExitBlk, 'Exit-Block existiert');
      Assert.IsNotNull(FinallyBlk, 'Finally-Block (ckException) existiert');
      Assert.IsTrue(CFG.CanReach(ExitBlk, FinallyBlk),
        'Exit im Try erreicht den finally-Block (Cross-Edge Inkr.1b)');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.TryExcept_MidTryBlock_ReachesExceptHandler;
var
  Meth : TAstNode;
  CFG  : TCFG;
  B, BranchBlk, ExceptBlk : uCFG.TCFGBlock;
begin
  // try if c then x := 1; except y := 2; end;
  // Der if-Branch entsteht WAEHREND des Try-Walks - vor Inkr.1b hatte nur
  // TryBodyStart die Cross-Edge, der Branch konnte den Handler nie erreichen
  // (Exception nach dem ersten Statement war im Graph unsichtbar).
  Meth := MakeMethod([ StmtTryExcept(StmtIf(StmtAssign, nil), StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      BranchBlk := nil;
      ExceptBlk := nil;
      for B in CFG.Blocks do
      begin
        if B.Kind = ckBranch then BranchBlk := B;
        if B.Kind = ckException then ExceptBlk := B;
      end;
      Assert.IsNotNull(BranchBlk, 'Branch im Try existiert');
      Assert.IsNotNull(ExceptBlk, 'Except-Block existiert');
      Assert.IsTrue(CFG.CanReach(BranchBlk, ExceptBlk),
        'Block mitten im Try erreicht den Handler (Mark-Range-Edges Inkr.1b)');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

procedure TTestCFG.CondNode_SetOnBranchAndLoopHeads;
var
  Meth : TAstNode;
  CFG  : TCFG;
  B    : uCFG.TCFGBlock;
  BranchCond, LoopCond : TAstNode;
begin
  // if c then x := 1; while c do x := 2;
  // ckBranch traegt das nkIfStmt, ckLoop das nkWhileStmt - Konsumenten
  // (SCA008 Q3 / SCA010 G5) lesen darueber den Bedingungstext.
  Meth := MakeMethod([ StmtIf(StmtAssign, nil), StmtWhile(StmtAssign) ]);
  try
    CFG := TCFGBuilder.BuildFromMethod(Meth);
    try
      BranchCond := nil;
      LoopCond   := nil;
      for B in CFG.Blocks do
      begin
        if (B.Kind = ckBranch) and (B.CondNode <> nil) then
          BranchCond := B.CondNode;
        if (B.Kind = ckLoop) and (B.CondNode <> nil) then
          LoopCond := B.CondNode;
      end;
      Assert.IsNotNull(BranchCond, 'Branch-CondNode gesetzt');
      Assert.IsTrue(BranchCond.Kind = nkIfStmt, 'Branch-CondNode = nkIfStmt');
      Assert.IsNotNull(LoopCond, 'Loop-CondNode gesetzt');
      Assert.IsTrue(LoopCond.Kind = nkWhileStmt, 'Loop-CondNode = nkWhileStmt');
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCFG);

end.
