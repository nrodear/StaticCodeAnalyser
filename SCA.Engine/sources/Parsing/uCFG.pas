unit uCFG;

// A.4.1 Control-Flow-Graph (CFG) - Datenstruktur-Skelett.
// Siehe Konzept_A4_CFG.md (lokal) fuer Plan.
//
// Phasen-Stand:
//   A.4.1 Datenstruktur + leerer Builder    <- DIESE PHASE
//   A.4.2 Builder fuer lineare Statements
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

class function TCFGBuilder.BuildFromMethod(MethNode: TAstNode): TCFG;
begin
  // A.4.1 Stub: trivial-CFG mit Entry -> Exit, kein Statement-Walk.
  // A.4.2 wird hier den linearen Walk dazu nehmen.
  Result := TCFG.Create;
  Result.Connect(Result.Entry, Result.Exit_);
end;

end.
