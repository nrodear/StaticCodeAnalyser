unit uCFG;

// Control-Flow-Graph (CFG) fuer SCA134 UseAfterFree (Konzept_A4_CFG.md).
//
// Phasen-Stand:
//   A.4.1 Datenstruktur + leerer Builder              -- DONE
//   A.4.2 Builder fuer lineare Statements             -- DONE
//   A.4.3 Branching (nkIfStmt, nkCaseStmt)            <- DIESE PHASE
//   A.4.4 Loops (nkWhileStmt, nkForStmt, nkRepeatStmt)
//   A.4.5 Exception-Pfade (nkTryExcept, nkTryFinally)
//   A.4.6 SCA134-Integration
//
// Lifecycle: TCFG besitzt ihre TCFGBlock-Instanzen via FBlocks
// (TObjectList<TCFGBlock>, OwnsObjects=True). Aufrufer ruft nur
// TCFG.Free, nicht die einzelnen Blocks.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode;

type
  // CFG-Node-Kinds. 'ck'-Prefix vermeidet Kollision mit TNodeKind aus
  // uAstNode (das auch nkExit fuer das exit-Statement enthaelt) - sonst
  // wuerde Pascal in WalkStatements bei `S.Kind = nkExit` (S = TAstNode)
  // den lokalen TCFGNodeKind aufloesen und E2010 werfen.
  TCFGNodeKind = (
    ckEntry,         // virtueller Method-Start (kein Statement)
    ckExit,          // virtueller Method-End (kein Statement)
    ckStatement,     // linearer Statement-Block (1..N AST-Knoten)
    ckBranch,        // if/case-Auswahl-Knoten (mehrere Successors)
    ckLoop,          // while/for/repeat (hat Back-Edge auf sich selbst)
    ckException      // try/except/finally (cross-edges fuer Exception-Pfade)
  );

  TCFGBlock = class
  public
    Id           : Integer;
    Kind         : TCFGNodeKind;
    AstNodes     : TList<TAstNode>;       // Statements im Block (nicht-besitzend)
    Successors   : TList<TCFGBlock>;      // 1..N Nachfolger (nicht-besitzend)
    Predecessors : TList<TCFGBlock>;      // Reverse-Edges (nicht-besitzend)
    Line         : Integer;
    constructor Create(AId: Integer; AKind: TCFGNodeKind);
    destructor Destroy; override;
  end;

  TCFG = class
  private
    FBlocks  : TObjectList<TCFGBlock>;
    FEntry   : TCFGBlock;
    FExit    : TCFGBlock;
    FNextId  : Integer;
  public
    constructor Create;
    destructor Destroy; override;

    // Erzeugt einen neuen Block, fuegt ihn FBlocks hinzu (Ownership).
    // Caller sollte das Result nur referenzieren, nicht Free-en.
    function NewBlock(AKind: TCFGNodeKind): TCFGBlock;

    // Verknuepft From -> To_ (bidirektional: Successor + Predecessor).
    // Doppel-Connect wird silent ignoriert.
    procedure Connect(From, To_: TCFGBlock);

    // Reachability via Forward-DFS. O(V+E) - Method-typische CFGs
    // sind < 100 Blocks, daher unbedenklich.
    function CanReach(From, To_: TCFGBlock): Boolean;

    property Entry: TCFGBlock read FEntry;
    property Exit_: TCFGBlock read FExit;
    property Blocks: TObjectList<TCFGBlock> read FBlocks;
  end;

  // Builder-Stub. Phase A.4.2+ fuellt BuildFromMethod aus.
  TCFGBuilder = class
  public
    // Baut CFG aus einem nkMethod-AST-Knoten. Phase A.4.1 returnt
    // CFG mit nur Entry und Exit_ verbunden (kein Statement-Walk).
    // Caller besitzt das Result, muss Free aufrufen.
    class function BuildFromMethod(MethNode: TAstNode): TCFG; static;
  end;

implementation

{ TCFGBlock }

constructor TCFGBlock.Create(AId: Integer; AKind: TCFGNodeKind);
begin
  inherited Create;
  Id           := AId;
  Kind         := AKind;
  AstNodes     := TList<TAstNode>.Create;
  Successors   := TList<TCFGBlock>.Create;
  Predecessors := TList<TCFGBlock>.Create;
  Line         := 0;
end;

destructor TCFGBlock.Destroy;
begin
  AstNodes.Free;
  Successors.Free;
  Predecessors.Free;
  inherited;
end;

{ TCFG }

constructor TCFG.Create;
begin
  inherited;
  FBlocks := TObjectList<TCFGBlock>.Create(True);  // OwnsObjects
  FNextId := 0;
  FEntry  := NewBlock(ckEntry);
  FExit   := NewBlock(ckExit);
end;

destructor TCFG.Destroy;
begin
  FBlocks.Free;  // OwnsObjects=True -> Blocks werden mit freigegeben
  inherited;
end;

function TCFG.NewBlock(AKind: TCFGNodeKind): TCFGBlock;
begin
  Result := TCFGBlock.Create(FNextId, AKind);
  Inc(FNextId);
  FBlocks.Add(Result);
end;

procedure TCFG.Connect(From, To_: TCFGBlock);
begin
  if (From = nil) or (To_ = nil) then Exit;
  if From.Successors.IndexOf(To_) >= 0 then Exit;  // Doppel-Connect skip
  From.Successors.Add(To_);
  To_.Predecessors.Add(From);
end;

function TCFG.CanReach(From, To_: TCFGBlock): Boolean;
var
  Visited : TList<TCFGBlock>;
  Stack   : TStack<TCFGBlock>;
  Current : TCFGBlock;
  Succ    : TCFGBlock;
begin
  if (From = nil) or (To_ = nil) then Exit(False);
  if From = To_ then Exit(True);
  Visited := TList<TCFGBlock>.Create;
  Stack   := TStack<TCFGBlock>.Create;
  try
    Stack.Push(From);
    while Stack.Count > 0 do
    begin
      Current := Stack.Pop;
      if Visited.IndexOf(Current) >= 0 then Continue;
      Visited.Add(Current);
      for Succ in Current.Successors do
      begin
        if Succ = To_ then Exit(True);
        if Visited.IndexOf(Succ) < 0 then Stack.Push(Succ);
      end;
    end;
    Result := False;
  finally
    Stack.Free;
    Visited.Free;
  end;
end;

{ TCFGBuilder }

// A.4.2+A.4.3 Builder fuer lineare Statements + Control-Transfer + Branching.
//
// Behandelt:
//   * nkAssign, nkCall          -> Sammeln in aktuellem ckStatement-Block
//   * nkExit                    -> Block -> Exit_, kein Tail
//   * nkBreak, nkContinue       -> Block -> nil  (Loop-Aufloesung in A.4.4)
//   * nkRaise                   -> Block -> Exit_ (Exception-Pfade in A.4.5)
//   * nkBlock (begin..end)      -> rekursiv abarbeiten (= inline)
//   * nkIfStmt                  -> BranchBlk + Then/Else-Pfade + Merge   (A.4.3)
//   * nkCaseStmt                -> BranchBlk + N Arm-Pfade + Merge       (A.4.3)
//
// Loops/Try noch opak (siehe Sub-Branch unten):
//   nkWhileStmt/nkForStmt/nkRepeatStmt -> A.4.4
//   nkTryExcept/nkTryFinally           -> A.4.5

class function TCFGBuilder.BuildFromMethod(MethNode: TAstNode): TCFG;

  function FindMethodBody(M: TAstNode): TAstNode;
  // Sucht den nkBlock-Body-Knoten unter der Method.
  var
    Child : TAstNode;
  begin
    Result := nil;
    if M = nil then Exit;
    for Child in M.Children do
      if Child.Kind = nkBlock then Exit(Child);
  end;

  // Forward-Deklaration weil ProcessOneStatement WalkStatements ruft
  // (nkBlock) und WalkStatements wiederum ProcessOneStatement.
  function WalkStatements(const Stmts: TList<TAstNode>;
                          CFG: TCFG; Current: TCFGBlock): TCFGBlock; forward;

  function ProcessOneStatement(S: TAstNode; CFG: TCFG;
                               Current: TCFGBlock): TCFGBlock;
  // Verarbeitet EIN AST-Statement. Returnt den neuen Tail-Block oder
  // nil wenn das Statement die Sequenz beendet (Exit/Raise/Break/Continue).
  var
    SubCh        : TAstNode;
    ThenChild    : TAstNode;
    ElseChild    : TAstNode;
    BranchBlk    : TCFGBlock;
    ThenStart    : TCFGBlock;
    ElseStart    : TCFGBlock;
    ThenTail     : TCFGBlock;
    ElseTail     : TCFGBlock;
    ArmStart     : TCFGBlock;
    ArmTail      : TCFGBlock;
    Merge        : TCFGBlock;
    HasElseArm   : Boolean;
    AnyArmTail   : Boolean;
  begin
    Result := Current;
    if (S = nil) or (Current = nil) then Exit;

    case S.Kind of
      nkAssign, nkCall:
        begin
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
        end;

      nkExit:
        begin
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
          CFG.Connect(Current, CFG.Exit_);
          Result := nil;
        end;

      nkRaise:
        begin
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
          CFG.Connect(Current, CFG.Exit_);
          Result := nil;
        end;

      nkBreak, nkContinue:
        begin
          // A.4.4 verkabelt mit Loop-Header/-Exit. Bis dahin: Sequenz endet.
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
          Result := nil;
        end;

      nkBlock:
        // begin..end inline: kein neuer CFG-Block, Children walken.
        Result := WalkStatements(S.Children, CFG, Current);

      nkIfStmt:
        begin
          // Branch-Header im aktuellen Block notieren (Bedingung via TypeRef).
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;

          // Then-Body = erstes Child das KEIN nkElseBranch ist.
          // Else-Body = Single-Child von nkElseBranch (falls vorhanden).
          ThenChild := nil;
          ElseChild := nil;
          for SubCh in S.Children do
          begin
            if SubCh.Kind = nkElseBranch then
            begin
              if SubCh.Children.Count > 0 then
                ElseChild := SubCh.Children[0];
            end
            else if ThenChild = nil then
              ThenChild := SubCh;
          end;

          BranchBlk := CFG.NewBlock(ckBranch);
          BranchBlk.Line := S.Line;
          CFG.Connect(Current, BranchBlk);

          // Then-Pfad
          ThenStart := CFG.NewBlock(ckStatement);
          CFG.Connect(BranchBlk, ThenStart);
          if ThenChild <> nil then
            ThenTail := ProcessOneStatement(ThenChild, CFG, ThenStart)
          else
            ThenTail := ThenStart;

          // Else-Pfad ODER Fall-through wenn kein else vorhanden.
          if ElseChild <> nil then
          begin
            ElseStart := CFG.NewBlock(ckStatement);
            CFG.Connect(BranchBlk, ElseStart);
            ElseTail := ProcessOneStatement(ElseChild, CFG, ElseStart);
          end
          else
          begin
            // Ohne else fluesst der Branch direkt weiter zum Merge.
            ElseTail := BranchBlk;
          end;

          // Merge-Block sammelt die Pfade die nicht durch Exit/Raise
          // terminiert sind.
          Merge := CFG.NewBlock(ckStatement);
          if ThenTail <> nil then CFG.Connect(ThenTail, Merge);
          if ElseTail <> nil then CFG.Connect(ElseTail, Merge);
          // Wenn beide Tails nil sind (both branches Exit/Raise), wird
          // Merge unerreichbar - das ist semantisch korrekt (Code nach
          // dem if waere dead). Result = Merge ist aber weiterhin der
          // erwartete Sequenz-Tail; einen TOTEN Merge erkennt SCA134
          // ueber Predecessors.Count = 0 wenn noetig.
          Result := Merge;
          if (ThenTail = nil) and (ElseTail = nil) then
            Result := nil;  // beide Pfade beendet -> Sequenz hier auch
        end;

      nkCaseStmt:
        begin
          // case <expr> of arm1: ...; arm2: ...; else ... end;
          // Parser-Struktur: Children = N x nkCaseArm, wobei der letzte
          // ggf. Name='else' hat. Jedes Arm hat als Children die
          // Statements des Arm-Bodys.
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;

          BranchBlk := CFG.NewBlock(ckBranch);
          BranchBlk.Line := S.Line;
          CFG.Connect(Current, BranchBlk);
          Merge := CFG.NewBlock(ckStatement);

          HasElseArm := False;
          AnyArmTail := False;
          for SubCh in S.Children do
          begin
            if SubCh.Kind <> nkCaseArm then Continue;
            if SameText(SubCh.Name, 'else') then HasElseArm := True;
            ArmStart := CFG.NewBlock(ckStatement);
            CFG.Connect(BranchBlk, ArmStart);
            // Arm-Body als Sequenz walken (Arm.Children).
            ArmTail := WalkStatements(SubCh.Children, CFG, ArmStart);
            if ArmTail <> nil then
            begin
              CFG.Connect(ArmTail, Merge);
              AnyArmTail := True;
            end;
          end;

          // Ohne else-Arm gibt es einen Default-Fallthrough (kein Arm
          // greift) - das ist semantisch das gleiche wie "if kein
          // Arm matched, geht's einfach weiter". Branch -> Merge.
          if not HasElseArm then
          begin
            CFG.Connect(BranchBlk, Merge);
            AnyArmTail := True;
          end;

          if AnyArmTail then
            Result := Merge
          else
            Result := nil;  // alle Arme beendet
        end;

      nkForStmt, nkWhileStmt, nkRepeatStmt,
      nkTryExcept, nkTryFinally:
        begin
          // Loops + Exception-Pfade in A.4.4/A.4.5. Bis dahin: opaker
          // Statement im aktuellen Block, 1-Ebenen-Tiefe-Scan auf
          // nested nkExit damit Reachability OUTER-Exit findet.
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
          for SubCh in S.Children do
            if SubCh.Kind = nkExit then
              CFG.Connect(Current, CFG.Exit_);
        end;
    else
      // nkLocalVar / nkInherited / etc.: kein Control-Flow.
    end;
  end;

  function WalkStatements(const Stmts: TList<TAstNode>;
                          CFG: TCFG; Current: TCFGBlock): TCFGBlock;
  // Iteriert ueber eine Sequenz und ruft ProcessOneStatement pro Element.
  // Returnt den letzten erreichbaren Block oder nil bei Sequenz-Abbruch.
  var
    S         : TAstNode;
    StmtBlock : TCFGBlock;
  begin
    Result := Current;
    if Stmts = nil then Exit;
    StmtBlock := Current;
    for S in Stmts do
    begin
      if S = nil then Continue;
      if StmtBlock = nil then Exit(nil);
      StmtBlock := ProcessOneStatement(S, CFG, StmtBlock);
    end;
    Result := StmtBlock;
  end;

var
  Body : TAstNode;
  Tail : TCFGBlock;
begin
  Result := TCFG.Create;
  if MethNode = nil then
  begin
    Result.Connect(Result.Entry, Result.Exit_);
    Exit;
  end;

  Body := FindMethodBody(MethNode);
  if (Body = nil) or (Body.Children = nil) or (Body.Children.Count = 0) then
  begin
    Result.Connect(Result.Entry, Result.Exit_);
    Exit;
  end;

  // Entry -> StartBlock -> ... -> Exit_
  var StartBlock := Result.NewBlock(ckStatement);
  Result.Connect(Result.Entry, StartBlock);
  Tail := WalkStatements(Body.Children, Result, StartBlock);
  if Tail <> nil then
    Result.Connect(Tail, Result.Exit_);
end;

end.
