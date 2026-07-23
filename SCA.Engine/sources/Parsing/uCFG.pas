unit uCFG;

// Control-Flow-Graph (CFG) - Shared Service fuer flussbasierte Detektoren.
// Historie: gebaut fuer SCA134 UseAfterFree (Konzept_A4_CFG.md); seit
// Roadmap #6 (Konzept_EngineArchitektur_FpReduktion) mit Dominates- und
// Reaching-Defs-Queries (CanReachAvoiding) fuer SCA008/166/010/011.
//
// Phasen-Stand:
//   A.4.1 Datenstruktur + leerer Builder              -- DONE
//   A.4.2 Builder fuer lineare Statements             -- DONE
//   A.4.3 Branching (nkIfStmt, nkCaseStmt)            -- DONE
//   A.4.4 Loops (while/for/repeat) + Break/Continue   -- DONE
//   A.4.5 Exception-Pfade (nkTryExcept, nkTryFinally) <- DIESE PHASE
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
    // #6 Inkr.1b: bei ckBranch/ckLoop der ausloesende AST-Knoten (nkIfStmt/
    // nkCaseStmt/nkWhileStmt/nkForStmt/nkRepeatStmt, nicht-besitzend, nil bei
    // Entry/Exit/Statement-Bloecken). Konsumenten (SCA008 Q3, SCA010 G5)
    // lesen darueber den Bedingungstext (TypeRef) fuer Guard-/Negations-
    // Korrelation - Line-Matching waere bei mehreren ifs pro Zeile ambig.
    CondNode     : TAstNode;
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

    // Roadmap #6 (Konzept_EngineArchitektur_FpReduktion): Reaching-Defs in
    // Query-Form. Existiert ein Pfad From -> To_, der KEINEN Avoid-Block als
    // Zwischenstation passiert? Endpunkte sind vom Avoid ausgenommen (From
    // darf selbst in Avoid liegen, To_ zaehlt als erreicht bevor Avoid
    // greift) - genau die Def-Use-Frage: "erreicht die Def in From den Use
    // in To_, ohne dass eine der Re-Defs in Avoid dazwischenliegt?".
    // Intra-Block-Reihenfolge (Def und Use im SELBEN Block) muss der
    // Konsument ueber die AstNodes-Reihenfolge des Blocks klaeren.
    function CanReachAvoiding(From, To_: TCFGBlock;
      const Avoid: array of TCFGBlock): Boolean;

    // Roadmap #6: Dominanz-Query ohne Dominator-Baum (Anti-Goldplating,
    // Konzept-Vorgabe). A dominiert B gdw. JEDER Pfad Entry -> B durch A
    // fuehrt. Implementierung: DFS von Entry, der A nie betritt - wird B
    // trotzdem erreicht, dominiert A nicht. Konventionen: Dominates(A,A) =
    // True; ist B von Entry aus gar nicht erreichbar, liefert die Query
    // False (konservativ: Postfilter droppen dann NICHT). O(V+E) pro Query.
    function Dominates(A, B: TCFGBlock): Boolean;

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

// noinspection-file BeginEndRequired, CanBeClassMethod, CanBeStrictPrivate, CaseStatementSize, ClassPerFile, CommentedOutCode, ConsecutiveSection, FreeWithoutNil, NestedRoutine, NilComparison, PublicField, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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
  CondNode     := nil;
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
begin
  // Delegiert an die Avoid-Variante mit leerem Avoid-Set - eine
  // DFS-Implementierung fuer beide Queries (#6: vorher TList.IndexOf-
  // Visited = O(V^2), jetzt Id-indiziertes Visited-Array = O(V+E);
  // Block.Id ist per NewBlock sequentiell 0..FNextId-1).
  Result := CanReachAvoiding(From, To_, []);
end;

function TCFG.CanReachAvoiding(From, To_: TCFGBlock;
  const Avoid: array of TCFGBlock): Boolean;
var
  Visited : TArray<Boolean>;   // Index = Block.Id; True = besucht ODER gemieden
  Stack   : TStack<TCFGBlock>;
  Current : TCFGBlock;
  Succ    : TCFGBlock;
  i       : Integer;
begin
  if (From = nil) or (To_ = nil) then Exit(False);
  if From = To_ then Exit(True);
  SetLength(Visited, FNextId);   // initialisiert False (managed Array)
  // Avoid-Blocks als "besucht" vormerken -> DFS betritt sie nie. From wird
  // ohnehin nur expandiert (nie gegen Avoid geprueft), To_ wird VOR dem
  // Visited-Check erkannt -> Endpunkte sind wie dokumentiert ausgenommen.
  for i := Low(Avoid) to High(Avoid) do
    if Avoid[i] <> nil then
      Visited[Avoid[i].Id] := True;
  Stack := TStack<TCFGBlock>.Create;
  try
    Stack.Push(From);
    Visited[From.Id] := True;
    while Stack.Count > 0 do
    begin
      Current := Stack.Pop;
      for Succ in Current.Successors do
      begin
        if Succ = To_ then Exit(True);
        if not Visited[Succ.Id] then
        begin
          Visited[Succ.Id] := True;
          Stack.Push(Succ);
        end;
      end;
    end;
    Result := False;
  finally
    Stack.Free;
  end;
end;

function TCFG.Dominates(A, B: TCFGBlock): Boolean;
begin
  if (A = nil) or (B = nil) then Exit(False);
  if A = B then Exit(True);
  // Dominanz ist nur fuer erreichbare Blocks definiert; unerreichbares B
  // -> False (konservativ, Postfilter droppt dann nicht).
  if not CanReach(FEntry, B) then Exit(False);
  // Entry dominiert jeden erreichbaren Block (A=Entry ist oben nicht per
  // CanReachAvoiding abbildbar, weil From vom Avoid ausgenommen ist).
  if A = FEntry then Exit(True);
  // B erreichbar, aber jeder Pfad laeuft durch A? Dann ist Entry -> B
  // OHNE A unmoeglich.
  Result := not CanReachAvoiding(FEntry, B, [A]);
end;

{ TCFGBuilder }

// A.4.2-A.4.4 Builder fuer lineare Statements + Control-Transfer + Branching + Loops.
//
// Behandelt:
//   * nkAssign, nkCall          -> Sammeln in aktuellem ckStatement-Block
//   * nkExit                    -> Block -> Exit_, kein Tail
//   * nkRaise                   -> Block -> Exit_ (Exception-Pfade in A.4.5)
//   * nkBreak                   -> Block -> LoopExit-Stack-Top, Tail=nil  (A.4.4)
//   * nkContinue                -> Block -> LoopHead-Stack-Top, Tail=nil  (A.4.4)
//   * nkBlock (begin..end)      -> rekursiv abarbeiten (= inline)
//   * nkIfStmt                  -> BranchBlk + Then/Else-Pfade + Merge    (A.4.3)
//   * nkCaseStmt                -> BranchBlk + N Arm-Pfade + Merge        (A.4.3)
//   * nkWhileStmt, nkForStmt    -> LoopHead + BodyStart + Back-Edge + NextBlock (A.4.4)
//   * nkRepeatStmt              -> Body + UntilHead + Back-Edge + NextBlock     (A.4.4)
//
// Exception-Pfade noch opak:
//   nkTryExcept/nkTryFinally    -> A.4.5

class function TCFGBuilder.BuildFromMethod(MethNode: TAstNode): TCFG;
type
  TLoopFrame = record
    LoopHead : TCFGBlock;  // Ziel fuer Continue
    LoopExit : TCFGBlock;  // Ziel fuer Break
  end;
var
  // Stack der aktuell offenen Loops. Bei verschachtelten Loops greift
  // Break/Continue nach Pascal-Konvention auf die INNERSTE Schleife =
  // Peek (Top of Stack).
  LoopStack : TStack<TLoopFrame>;

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

      nkBreak:
        begin
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
          // Break springt aus der INNERSTEN Schleife zum LoopExit
          // (NextBlock nach dem Loop). Ohne Loop-Kontext (Parser-Fehler)
          // bleibt das ein no-op Tail=nil, robust.
          if LoopStack.Count > 0 then
            CFG.Connect(Current, LoopStack.Peek.LoopExit);
          Result := nil;
        end;

      nkContinue:
        begin
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;
          // Continue springt zum LoopHead (Cond-Check-Punkt).
          if LoopStack.Count > 0 then
            CFG.Connect(Current, LoopStack.Peek.LoopHead);
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
          BranchBlk.CondNode := S;   // #6 1b: Bedingung fuer Guard-Queries
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
          BranchBlk.CondNode := S;   // #6 1b: case-Selector fuer Guard-Queries
          CFG.Connect(Current, BranchBlk);
          // KRITISCH: distinkte inline-Variable CaseMerge statt der
          // function-level 'Merge'. WalkStatements(SubCh.Children) im
          // Arm kann ein nested nkIfStmt enthalten dessen rekursive
          // ProcessOneStatement den function-level Merge ueberschreibt -
          // nachfolgende Arme wuerden dann gegen den falschen Merge
          // connecten. Selber Bug wie nkTryExcept (audit-fix).
          var CaseMerge := CFG.NewBlock(ckStatement);

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
              CFG.Connect(ArmTail, CaseMerge);
              AnyArmTail := True;
            end;
          end;

          // Ohne else-Arm gibt es einen Default-Fallthrough (kein Arm
          // greift) - das ist semantisch das gleiche wie "if kein
          // Arm matched, geht's einfach weiter". Branch -> Merge.
          if not HasElseArm then
          begin
            CFG.Connect(BranchBlk, CaseMerge);
            AnyArmTail := True;
          end;

          if AnyArmTail then
            Result := CaseMerge
          else
            Result := nil;  // alle Arme beendet
        end;

      nkWhileStmt, nkForStmt:
        begin
          // while/for haben Cond-Check VOR dem Body (Pre-Test-Loop):
          //   Current -> LoopHead    (Cond evaluiert)
          //   LoopHead -> BodyStart  (Cond=true)
          //   BodyTail -> LoopHead   (Back-Edge fuer Iteration)
          //   LoopHead -> NextBlock  (Cond=false, Loop-Exit)
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;

          var LoopHead := CFG.NewBlock(ckLoop);
          LoopHead.Line := S.Line;
          LoopHead.CondNode := S;   // #6 1b: Schleifenkopf fuer Guard-Queries
          var NextBlk  := CFG.NewBlock(ckStatement);
          CFG.Connect(Current, LoopHead);

          var BodyStart := CFG.NewBlock(ckStatement);
          CFG.Connect(LoopHead, BodyStart);
          CFG.Connect(LoopHead, NextBlk);   // Cond=false sofort weiter

          // Loop-Body finden: erstes Child das KEIN nkLocalVar ist
          // (Inline-var-Loopvar bei 'for var x := ...' wuerde sonst
          // als Body interpretiert).
          var BodyChild : TAstNode := nil;
          for SubCh in S.Children do
            if SubCh.Kind <> nkLocalVar then
            begin
              BodyChild := SubCh;
              Break;
            end;

          // LoopStack pushen damit Break/Continue im Body greifen
          var Frame: TLoopFrame;
          Frame.LoopHead := LoopHead;
          Frame.LoopExit := NextBlk;
          LoopStack.Push(Frame);
          try
            var BodyTail : TCFGBlock := BodyStart;
            if BodyChild <> nil then
              BodyTail := ProcessOneStatement(BodyChild, CFG, BodyStart);
            // Back-Edge zum LoopHead wenn Body nicht durch
            // Exit/Raise/Break/Continue terminiert wurde.
            if BodyTail <> nil then
              CFG.Connect(BodyTail, LoopHead);
          finally
            LoopStack.Pop;
          end;

          Result := NextBlk;
        end;

      nkRepeatStmt:
        begin
          // repeat..until: Body laeuft VOR der Bedingung (Post-Test-Loop).
          //   Current -> BodyStart
          //   ... (Body als Sequenz aus S.Children)
          //   BodyTail -> UntilHead (Cond evaluiert)
          //   UntilHead -> BodyStart  (Cond=false, naechste Iteration)
          //   UntilHead -> NextBlock  (Cond=true, Loop-Exit)
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;

          var BodyStart := CFG.NewBlock(ckStatement);
          BodyStart.Line := S.Line;
          var UntilHead := CFG.NewBlock(ckLoop);
          UntilHead.CondNode := S;   // #6 1b: until-Bedingung fuer Guard-Queries
          var NextBlk   := CFG.NewBlock(ckStatement);
          CFG.Connect(Current, BodyStart);

          // Continue zielt auf UntilHead (Cond-Check), Break auf NextBlk.
          var Frame: TLoopFrame;
          Frame.LoopHead := UntilHead;
          Frame.LoopExit := NextBlk;
          LoopStack.Push(Frame);
          try
            // Body als Sequenz aus den Children walken
            var BodyTail := WalkStatements(S.Children, CFG, BodyStart);
            if BodyTail <> nil then
              CFG.Connect(BodyTail, UntilHead);
          finally
            LoopStack.Pop;
          end;

          CFG.Connect(UntilHead, BodyStart);  // Cond=false -> Iteration
          CFG.Connect(UntilHead, NextBlk);    // Cond=true -> Exit
          Result := NextBlk;
        end;

      nkTryExcept:
        begin
          //   try { TryBody } except { ExceptBody } end;
          //
          // Modell:
          //   Current -> TryBodyStart
          //   TryBodyStart -> ExceptStart  (Cross-Edge: Exception passiert)
          //   TryBodyTail  -> Merge        (normaler Flow durch den try)
          //   ExceptTail   -> Merge        (Handler beendet, weiter)
          //   Result = Merge
          //
          // Seit #6 Inkr.1b: Cross-Edge von JEDEM TryBody-Block (Mark-Range
          // nach dem Walk, s.u.) - "jedes Statement im Try kann throwen".
          // Der explizite Start-Edge bleibt fuer den Fall leerer Try-Bodies.
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;

          // KRITISCH: distinkte inline-Variable TryMerge statt der
          // function-level 'Merge' aus Line 233. WalkStatements ruft
          // recursive ProcessOneStatement; wenn TryStmts ein nkIfStmt
          // oder nkCaseStmt enthaelt, ueberschreibt deren `Merge := ...`
          // den function-level Merge - die nkTryExcept-Branch wuerde
          // dann auf den falschen Merge-Block connecten. Reproduziert
          // im Audit als FP in doublecmd base64func.pas (try/if/else).
          var TryBodyStart := CFG.NewBlock(ckStatement);
          var ExceptStart  := CFG.NewBlock(ckException);
          var TryMerge     := CFG.NewBlock(ckStatement);
          ExceptStart.Line := S.Line;
          CFG.Connect(Current, TryBodyStart);
          CFG.Connect(TryBodyStart, ExceptStart);

          // TryBody = Children OHNE den nkExceptBlock am Ende.
          // ExceptBlock = ein Child mit Kind=nkExceptBlock.
          var ExceptNode : TAstNode := nil;
          var TryStmts := TList<TAstNode>.Create;
          try
            for SubCh in S.Children do
            begin
              if SubCh.Kind = nkExceptBlock then
                ExceptNode := SubCh
              else
                TryStmts.Add(SubCh);
            end;

            // #6 Inkr.1b: JEDER Block des Try-Koerpers bekommt die Exception-
            // Cross-Edge zum Handler (vorher nur TryBodyStart -> ExceptStart).
            // Grund (Leser-Audit 2026-07-23): eine Exception kann nach JEDEM
            // Statement im Try fliegen; ohne die Kanten waere z.B. eine
            // nil-Zuweisung mitten im Try aus Sicht von CanReach nie im
            // Handler sichtbar -> ein CanReach-Drop-Filter (SCA008 Q1) wuerde
            // echte Funde over-droppen. Mark-Range: NewBlock haengt sequen-
            // tiell an FBlocks, also sind GENAU die waehrend des Try-Walks
            // erzeugten Bloecke (inkl. nested Strukturen - auch deren
            // Exceptions propagieren hierher) die Indizes [TryMark, Count).
            // Rein Kanten-ADDITIV -> Reachability kann nur zunehmen ->
            // SCA134-A/B kann nur ADDs zeigen (vorher zu unrecht gedroppte
            // Funde), nie neue Drops.
            var TryMark := CFG.Blocks.Count;
            var TryBodyTail := WalkStatements(TryStmts, CFG, TryBodyStart);
            if TryBodyTail <> nil then
              CFG.Connect(TryBodyTail, TryMerge);
            for var bi := TryMark to CFG.Blocks.Count - 1 do
              CFG.Connect(CFG.Blocks[bi], ExceptStart);

            // Except-Body walken (alle Children inkl. on-Handler).
            var ExceptTail : TCFGBlock := ExceptStart;
            if ExceptNode <> nil then
              ExceptTail := WalkStatements(ExceptNode.Children, CFG, ExceptStart);
            if ExceptTail <> nil then
              CFG.Connect(ExceptTail, TryMerge);
          finally
            TryStmts.Free;
          end;

          Result := TryMerge;
        end;

      nkTryFinally:
        begin
          //   try { TryBody } finally { FinallyBody } end;
          //
          // Modell (Finally LAEUFT IMMER, sowohl normal-end als auch
          // Exception):
          //   Current      -> TryBodyStart
          //   TryBodyStart -> FinallyStart  (Cross-Edge: Exception waehrend Try)
          //   TryBodyTail  -> FinallyStart  (normaler Try-End)
          //   FinallyTail  -> NextBlock     (Continuation)
          //   Result = NextBlock
          //
          // Bei Re-Raise nach Finally (Exception propagiert) waere konservativ
          // FinallyTail->Exit_; weglassen aktuell, das ist eine Ueber-
          // Konservativitaet die SCA134 unnoetige TPs erzeugen koennte.
          Current.AstNodes.Add(S);
          if Current.Line = 0 then Current.Line := S.Line;

          var TryBodyStart := CFG.NewBlock(ckStatement);
          var FinallyStart := CFG.NewBlock(ckException);
          var NextBlk      := CFG.NewBlock(ckStatement);
          FinallyStart.Line := S.Line;
          CFG.Connect(Current, TryBodyStart);
          CFG.Connect(TryBodyStart, FinallyStart);   // Exception-Pfad

          // Children = TryBody-Stmts ... + nkFinallyBlock am Ende.
          var FinallyNode : TAstNode := nil;
          var TryStmts := TList<TAstNode>.Create;
          try
            for SubCh in S.Children do
            begin
              if SubCh.Kind = nkFinallyBlock then
                FinallyNode := SubCh
              else
                TryStmts.Add(SubCh);
            end;

            // #6 Inkr.1b: analog nkTryExcept - JEDER Try-Koerper-Block
            // bekommt die Cross-Edge zum Finally (Exception ODER Exit/raise/
            // Break/Continue mitten im Try laufen in Delphi IMMER durch den
            // finally-Block; vorher verband nkExit direkt zu Exit_ und der
            // finally war von dort unerreichbar -> Over-Drop-Risiko fuer
            // CanReach-Filter bei Use-im-finally). Kanten-additiv, s.o.
            var TryMark := CFG.Blocks.Count;
            var TryBodyTail := WalkStatements(TryStmts, CFG, TryBodyStart);
            if TryBodyTail <> nil then
              CFG.Connect(TryBodyTail, FinallyStart);
            for var bi := TryMark to CFG.Blocks.Count - 1 do
              CFG.Connect(CFG.Blocks[bi], FinallyStart);

            var FinallyTail : TCFGBlock := FinallyStart;
            if FinallyNode <> nil then
              FinallyTail := WalkStatements(FinallyNode.Children, CFG, FinallyStart);
            if FinallyTail <> nil then
              CFG.Connect(FinallyTail, NextBlk);
          finally
            TryStmts.Free;
          end;

          Result := NextBlk;
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

  LoopStack := TStack<TLoopFrame>.Create;
  try
    var StartBlock := Result.NewBlock(ckStatement);
    Result.Connect(Result.Entry, StartBlock);
    Tail := WalkStatements(Body.Children, Result, StartBlock);
    if Tail <> nil then
      Result.Connect(Tail, Result.Exit_);
  finally
    LoopStack.Free;
  end;
end;

end.
