unit uCFG;

// Control-Flow-Graph (CFG) fuer SCA134 UseAfterFree (Konzept_A4_CFG.md).
//
// Phasen-Stand:
//   A.4.1 Datenstruktur + leerer Builder    -- DONE
//   A.4.2 Builder fuer lineare Statements    <- DIESE PHASE
//   A.4.3 Branching (nkIfStmt, nkCaseStmt)
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
  TCFGNodeKind = (
    nkEntry,         // virtueller Method-Start (kein Statement)
    nkExit,          // virtueller Method-End (kein Statement)
    nkStatement,     // linearer Statement-Block (1..N AST-Knoten)
    nkBranch,        // if/case-Auswahl-Knoten (mehrere Successors)
    nkLoop,          // while/for/repeat (hat Back-Edge auf sich selbst)
    nkException      // try/except/finally (cross-edges fuer Exception-Pfade)
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
  FEntry  := NewBlock(nkEntry);
  FExit   := NewBlock(nkExit);
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

// A.4.2 Builder fuer lineare Statements + Control-Transfer.
//
// Behandelt in dieser Phase:
//   * nkAssign, nkCall          -> Sammeln in aktuellem nkStatement-Block
//   * nkExit                    -> Block -> Exit_, kein Tail
//   * nkBreak, nkContinue       -> Block -> nil  (Loop-Aufloesung in A.4.4)
//   * nkRaise                   -> Block -> Exit_ (Exception-Pfade in A.4.5)
//   * nkBlock (begin..end)      -> rekursiv abarbeiten (= inline kein neuer Block)
//
// Branches/Loops/Try werden in nachfolgenden Phasen ergaenzt:
//   nkIfStmt/nkCaseStmt        -> A.4.3
//   nkWhileStmt/nkForStmt/nkRepeatStmt -> A.4.4
//   nkTryExcept/nkTryFinally   -> A.4.5
// In A.4.2 werden sie als opaker Statement im aktuellen Block notiert
// (AstNodes.Add), aber NICHT in ihre Sub-Bloecke aufgeloest.

type
  // Walker-State: aktueller "Tail"-Block in den nachfolgende Statements
  // fallen wuerden. nil bedeutet "unerreichbar" (nach Exit/Raise/...).
  TWalkResult = TCFGBlock;

class function TCFGBuilder.BuildFromMethod(MethNode: TAstNode): TCFG;

  function FindMethodBody(M: TAstNode): TAstNode;
  // Sucht den nkBlock-Body-Knoten unter der Method. Toleriert das
  // Pattern Parser produziert sowohl direkten nkBlock-Child als auch
  // den FALL dass der Body eine Liste von Statements direkt unter
  // dem nkMethod-Knoten liegt (Pascal-typisch fuer Single-Stmt Body).
  var
    Child : TAstNode;
  begin
    Result := nil;
    if M = nil then Exit;
    for Child in M.Children do
      if Child.Kind = nkBlock then Exit(Child);
  end;

  function WalkStatements(const Stmts: TList<TAstNode>;
                          CFG: TCFG; Current: TCFGBlock): TCFGBlock;
  // Iteriert ueber die Statements einer Sequenz (Method-Body oder
  // begin..end-Inhalt). Returnt den letzten erreichbaren Block oder
  // nil wenn die Sequenz durch Exit/Raise/Break/Continue unerreichbar
  // wird. Current = Block in den das erste Statement faellt.
  var
    S          : TAstNode;
    StmtBlock  : TCFGBlock;
    SubBlock   : TAstNode;
  begin
    Result := Current;
    if Stmts = nil then Exit;
    StmtBlock := Current;

    for S in Stmts do
    begin
      if S = nil then Continue;
      if StmtBlock = nil then
      begin
        // Sequenz war schon unterbrochen (Exit/Raise). Keine weitere
        // Verarbeitung - nachfolgender Code waere toter Code, den ein
        // separater DeadCode-Detektor flaggt.
        Exit(nil);
      end;

      case S.Kind of
        nkAssign, nkCall:
          begin
            StmtBlock.AstNodes.Add(S);
            if StmtBlock.Line = 0 then StmtBlock.Line := S.Line;
          end;

        nkExit:
          begin
            StmtBlock.AstNodes.Add(S);
            if StmtBlock.Line = 0 then StmtBlock.Line := S.Line;
            CFG.Connect(StmtBlock, CFG.Exit_);
            StmtBlock := nil;  // Sequenz hier zu Ende
          end;

        nkRaise:
          begin
            // Raise verlaesst die Method (sofern kein umschliessendes
            // try/except - das wird in A.4.5 modelliert). Bis dahin
            // konservativ als Direkt-Exit.
            StmtBlock.AstNodes.Add(S);
            if StmtBlock.Line = 0 then StmtBlock.Line := S.Line;
            CFG.Connect(StmtBlock, CFG.Exit_);
            StmtBlock := nil;
          end;

        nkBreak, nkContinue:
          begin
            // Break/Continue gehoeren in einen Loop-Kontext (A.4.4).
            // In A.4.2 schreiben wir sie ins aktuelle Block-AST damit
            // die Information nicht verloren geht, aber den Sequenz-
            // Fluss markieren wir als "hier vorerst zu Ende" - der
            // Loop-Builder verkabelt sie in A.4.4 mit dem korrekten
            // Loop-Header bzw. Loop-Exit.
            StmtBlock.AstNodes.Add(S);
            if StmtBlock.Line = 0 then StmtBlock.Line := S.Line;
            StmtBlock := nil;
          end;

        nkBlock:
          // Begin..end: Children sind die Statements der Sequenz.
          // Wir bleiben im selben CFG-Block (= inline-Ausweitung statt
          // neuer Block) - das passt zur Semantik dass begin..end
          // keinen Control-Flow erzeugt, nur Gruppierung.
          StmtBlock := WalkStatements(S.Children, CFG, StmtBlock);

        nkIfStmt, nkCaseStmt,
        nkForStmt, nkWhileStmt, nkRepeatStmt,
        nkTryExcept, nkTryFinally:
          begin
            // Phase A.4.2 modelliert komplexe Statements noch nicht in
            // Sub-Blocks. Sie werden als opaker Statement im aktuellen
            // Block notiert; spaetere Phasen ueberschreiben diesen
            // Branch durch korrekte CFG-Verzweigung.
            // Wichtig: wir untersuchen rekursiv NICHT die Sub-Children,
            // sonst wuerde z.B. ein Exit innerhalb des Loops faelschlich
            // den OUTER Tail abbrechen.
            StmtBlock.AstNodes.Add(S);
            if StmtBlock.Line = 0 then StmtBlock.Line := S.Line;
            // ABER: damit nkExit innerhalb einer Branch noch im Outer
            // Reachability-Graphen mitwirkt, scannen wir die direkten
            // Children (1 Ebene tief) auf control-transfers.
            for SubBlock in S.Children do
              if SubBlock.Kind = nkExit then
                CFG.Connect(StmtBlock, CFG.Exit_);
          end;
      else
        // Unbekannter / nicht-Control-Flow-Knoten: silently ignorieren.
        // Beispiele: nkLocalVar (Variable-Declaration), nkInherited
        // (nimmt keinen Control-Flow-Slot).
      end;
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
    // Leerer / fehlender Body -> Entry direkt nach Exit_.
    Result.Connect(Result.Entry, Result.Exit_);
    Exit;
  end;

  // Erster Statement-Block. Entry -> StartBlock.
  var StartBlock := Result.NewBlock(nkStatement);
  Result.Connect(Result.Entry, StartBlock);
  Tail := WalkStatements(Body.Children, Result, StartBlock);
  // Wenn der Sequenz-Tail nicht durch Exit/Raise abgebrochen wurde,
  // fluesst er natuerlich in den End-Block.
  if Tail <> nil then
    Result.Connect(Tail, Result.Exit_);
end;

end.
