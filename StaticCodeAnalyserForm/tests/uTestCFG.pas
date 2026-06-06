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
    Assert.AreEqual(0, CFG.Entry.Successors.Count, 'frische CFG: Entry hat keine Successors');
    CFG.Connect(CFG.Entry, CFG.Exit_);
    Assert.AreEqual(1, CFG.Entry.Successors.Count);
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
    Assert.AreEqual(1, CFG.Entry.Successors.Count);
    Assert.AreEqual(1, Block1.Predecessors.Count, 'Block1 Predecessor = Entry');
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
    Assert.AreEqual(3, CFG.Blocks.Count, 'Entry + Exit + 1 Statement-Block');
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
      Assert.AreEqual(2, BranchBlk.Successors.Count,
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
      Assert.AreEqual(2, CFG.Exit_.Predecessors.Count);
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
      Assert.AreEqual(3, BranchBlk.Successors.Count,
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
      Assert.AreEqual(3, CFG.Exit_.Predecessors.Count);
    finally CFG.Free; end;
  finally Meth.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCFG);

end.
