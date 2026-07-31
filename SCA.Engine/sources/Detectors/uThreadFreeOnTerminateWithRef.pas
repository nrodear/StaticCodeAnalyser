unit uThreadFreeOnTerminateWithRef;

// Detektor: TThread mit FreeOnTerminate=True + spaeterer Zugriff durch
// den Caller -> Access-Violation (Thread kann jederzeit beendet sein).
//
// Pattern (Concurrency-Crash):
//   T := TMyThread.Create(True);
//   T.FreeOnTerminate := True;
//   T.Start;
//   T.Resume;          // BUG: T koennte schon freigegeben sein
//   T.WaitFor;         // BUG: T koennte schon freigegeben sein
//   if T.Finished ...  // BUG: T koennte schon freigegeben sein
//
// Korrekt:
//   T := TMyThread.Create(True);
//   T.FreeOnTerminate := True;
//   T.Start;
//   T := nil;          // sofort weg, kein weiterer Zugriff
//   // ODER: kein FreeOnTerminate, manuell verwalten.
//
// Erkennung (per-Method-Scope-Walk):
//   * Pass 1: Walk nkAssign, finde `<var>.FreeOnTerminate := True`
//     Variante. Sammle Var-Namen mit Zeile.
//   * Pass 2: Walk nkAssign + nkCall, finde subsequent (Line > Pass-1-
//     Line) `<var>.<anything>`-Zugriffe. Pro Match ein Finding.
//
// FP-Tradeoff:
//   * Cross-Method-Reference (`T` aus Field gehalten + spaeter Access)
//     wird nicht erkannt - per-Method-Scope.
//   * Var = nil zwischen FreeOnTerminate und Access wird NICHT als
//     Sicherheits-Massnahme erkannt - FP wenn User das macht.
//     Suppression-Marker als Escape.
//   * FreeOnTerminate := False (explizit) wird NICHT geflagt.
//   * Branch-Exklusivitaet (Gate 2026-07-31): FoT-Zuweisung im then-Zweig
//     und Zugriff im else-Zweig DESSELBEN if wird NICHT geflagt - die
//     Pfade schliessen sich aus (Indy-Scheduler-Muster).
//
// Severity: lsError, Type: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TThreadFreeOnTerminateWithRefDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Liefert den Var-Namen wenn LHS `<var>.FreeOnTerminate` ist,
    // sonst leerstring. Case-insensitive.
    class function MatchFreeOnTerminateLHS(const LHS: string): string; static;
    // True wenn RHS (TypeRef) `True` ist (case-insensitive, getrimmt).
    class function IsTrueLiteral(const RHS: string): Boolean; static;
    // True wenn Expr `<var>.<sub>` Pattern enthaelt UND sub NICHT auf
    // der Lifecycle-Whitelist {Start, Resume, Execute} steht. Diese
    // Calls sind in dieser Reihenfolge erwartet (FoT vor Start ist
    // die Standard-Delphi-Idiom).
    class function HasDangerousMemberAccess(const Expr, VarName: string): Boolean; static;
    // True wenn Expr ein Aktivierungs-Call `<var>.Start` / `<var>.Resume`
    // ist - der Punkt ab dem der Thread LEBT (und sich selbst zerstoeren
    // kann). Resume ist der pre-XE2-Start.
    class function IsActivationCall(const Expr, VarName: string): Boolean; static;
    // FP-Gate 2026-07-31: True wenn FoTNode und AccessNode in den beiden
    // ZWEIGEN desselben if stehen (then vs. else) - dann laufen sie nie
    // gemeinsam. Analog zu uNilDeref.IsInExclusiveBranch (bewusst lokal
    // nachgebaut statt importiert - uNilDeref ist eine fremde Detektor-Unit).
    class function IsInExclusiveBranch(MethodNode, FoTNode,
      AccessNode: TAstNode): Boolean; static;
  end;

implementation

// SQLInjection: die Fix-Message wird via String-Concat ('Call on "' + ... )
// gebaut und vom SQL-Concat-Detektor faelschlich gematcht - Self-Scan-
// Artefakt im Detektor-Quellcode, kein Bug.
// noinspection-file SQLInjection

uses
  System.RegularExpressions;

class function TThreadFreeOnTerminateWithRefDetector.MatchFreeOnTerminateLHS(
  const LHS: string): string;
var
  M : TMatch;
begin
  Result := '';
  M := TRegEx.Match(LHS, '^([A-Za-z_]\w*)\.FreeOnTerminate$', [roIgnoreCase]);
  if M.Success then Result := M.Groups[1].Value;
end;

class function TThreadFreeOnTerminateWithRefDetector.IsTrueLiteral(
  const RHS: string): Boolean;
begin
  Result := SameText(Trim(RHS), 'True');
end;

class function TThreadFreeOnTerminateWithRefDetector.HasDangerousMemberAccess(
  const Expr, VarName: string): Boolean;
// True wenn `<VarName>.<ident>` im Expr vorkommt UND ident NICHT auf
// der Lifecycle-Whitelist {Start, Execute} steht. Start ist der ERWARTETE
// Init-Call nach FoT, Execute ist der Inner-Thread-Body. Resume ist
// deprecated und nach FoT genauso gefaehrlich wie ein generischer
// Member-Access -> NICHT auf der Whitelist.
const
  // 'resume' jetzt auf der Whitelist: pre-XE2 ist Resume DER Start-Call,
  // kein gefaehrlicher Post-Mortem-Zugriff (Real-World-FP 2026-06-21).
  WHITELIST : array[0..2] of string = ('start', 'execute', 'resume');
var
  Pat   : string;
  M     : TMatch;
  Sub   : string;
  Allow : string;
  IsAllowed : Boolean;
begin
  Result := False;
  Pat := '\b' + VarName + '\s*\.\s*(\w+)';
  for M in TRegEx.Matches(Expr, Pat, [roIgnoreCase]) do
  begin
    Sub := LowerCase(M.Groups[1].Value);
    IsAllowed := False;
    for Allow in WHITELIST do
      if Sub = Allow then begin IsAllowed := True; Break; end;
    if not IsAllowed then Exit(True);
  end;
end;

class function TThreadFreeOnTerminateWithRefDetector.IsActivationCall(
  const Expr, VarName: string): Boolean;
var
  M : TMatch;
  Sub : string;
begin
  Result := False;
  M := TRegEx.Match(Expr, '\b' + VarName + '\s*\.\s*(\w+)', [roIgnoreCase]);
  if not M.Success then Exit;
  Sub := LowerCase(M.Groups[1].Value);
  Result := (Sub = 'start') or (Sub = 'resume');
end;

function NodeContainsRef(Root, Target: TAstNode): Boolean;
// Subtree-Containment per OBJEKT-Identitaet (TAstNode hat keinen Parent-
// Pointer). Iterative DFS. Lokale Kopie des Musters aus uNilDeref - geteilte
// Units bleiben unangetastet.
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := False;
  if (Root = nil) or (Target = nil) then Exit;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if Cur = Target then Exit(True);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class function TThreadFreeOnTerminateWithRefDetector.IsInExclusiveBranch(
  MethodNode, FoTNode, AccessNode: TAstNode): Boolean;
// FP-Gate (Real-World-Audit 2026-07-31, FP-Klasse 'mutually-exclusive-
// branches'): steht `<T>.FreeOnTerminate := True` im then-Zweig eines if und
// der geflaggte Zugriff im zugehoerigen else-Zweig (oder umgekehrt), koennen
// beide auf keiner realen Ausfuehrung gemeinsam laufen - der Ownership-
// Transfer erreicht den Zugriff nie. Vorbild-FPs: Indy
// IdSchedulerOfThreadDefault/IdSchedulerOfThreadPool ('if IsCurrentThread(L)
// then L.FreeOnTerminate := True else begin L.WaitFor; L.Free; end').
// AST-verifiziert: ParseIfStmt legt then-Statements als Descendants des
// nkIfStmt ab, else-Statements unter ein nkElseBranch-Direktkind. Rein
// strukturell und monoton: ohne trennendes if/else bleibt jeder Fund.
var
  Ifs   : TList<TAstNode>;
  IfN   : TAstNode;
  ElseN : TAstNode;
  FInElse, AInElse, FInThen, AInThen : Boolean;
begin
  Result := False;
  if (MethodNode = nil) or (FoTNode = nil) or (AccessNode = nil) then Exit;
  Ifs := MethodNode.FindAllRef(nkIfStmt);
  if Ifs = nil then Exit;
  for IfN in Ifs do
  begin
    ElseN := IfN.FindFirstChild(nkElseBranch);
    if ElseN = nil then Continue;           // ohne else keine Schwester-Zweige
    // then-Zweig = im if-Subtree, aber NICHT im else-Subtree.
    FInElse := NodeContainsRef(ElseN, FoTNode);
    AInElse := NodeContainsRef(ElseN, AccessNode);
    FInThen := NodeContainsRef(IfN, FoTNode) and not FInElse;
    AInThen := NodeContainsRef(IfN, AccessNode) and not AInElse;
    if (FInThen and AInElse) or (FInElse and AInThen) then
      Exit(True);
  end;
end;

class procedure TThreadFreeOnTerminateWithRefDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Assigns, Calls : TList<TAstNode>;
  M, N    : TAstNode;
  // Var-Name -> Line der FreeOnTerminate-Zuweisung
  FoTLine : TDictionary<string, Integer>;
  // Var-Name -> Knoten der FreeOnTerminate-Zuweisung (Branch-Exklusivitaets-
  // Gate 2026-07-31 braucht den Knoten, nicht nur die Zeile)
  FoTNode : TDictionary<string, TAstNode>;
  FoTN    : TAstNode;
  // Var-Name -> Line des Start/Resume-Calls (Thread wird ab hier "lebendig")
  ActLine : TDictionary<string, Integer>;
  VarName : string;
  Pair    : TPair<string, Integer>;
  GateLine: Integer;
  F       : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      FoTLine := TDictionary<string, Integer>.Create;
      FoTNode := TDictionary<string, TAstNode>.Create;
      ActLine := TDictionary<string, Integer>.Create;
      try
        // Pass 1: FreeOnTerminate := True finden.
        Assigns := M.FindAll(nkAssign);
        try
          for N in Assigns do
          begin
            VarName := MatchFreeOnTerminateLHS(N.Name);
            if VarName = '' then Continue;
            if not IsTrueLiteral(N.TypeRef) then Continue;
            FoTLine.AddOrSetValue(LowerCase(VarName), N.Line);
            // Knoten parallel merken (Branch-Exklusivitaets-Gate 2026-07-31).
            FoTNode.AddOrSetValue(LowerCase(VarName), N);
          end;
        finally
          Assigns.Free;
        end;
        if FoTLine.Count = 0 then Continue;

        // Pass 1b: Aktivierungs-Call (Start/Resume) pro Var finden -
        // FRUEHESTE Zeile. Erst NACH dem Start ist ein Zugriff gefaehrlich;
        // Config-Assignments + Reads VOR dem Start sind harmlos (Thread
        // laeuft noch nicht). Real-World-FP 2026-06-21.
        Calls := M.FindAll(nkCall);
        try
          for N in Calls do
            for Pair in FoTLine do
              if IsActivationCall(N.Name, Pair.Key) then
                if (not ActLine.ContainsKey(Pair.Key))
                   or (N.Line < ActLine[Pair.Key]) then
                  ActLine.AddOrSetValue(Pair.Key, N.Line);
        finally
          Calls.Free;
        end;

        // Pass 2: subsequent Access auf VarName NACH dem Start.
        // Ohne Start im selben Method-Scope: kein Finding (per-Method-FN).
        for Pair in FoTLine do
        begin
          if not ActLine.TryGetValue(Pair.Key, GateLine) then Continue;
          if not FoTNode.TryGetValue(Pair.Key, FoTN) then FoTN := nil;
          Assigns := M.FindAll(nkAssign);
          try
            for N in Assigns do
            begin
              if N.Line <= GateLine then Continue;
              // Nur RHS-Reads (N.TypeRef) flaggen - LHS-Property-Assignments
              // (`<var>.Name := x`) sind Config, kein gefaehrlicher Read.
              if HasDangerousMemberAccess(N.TypeRef, Pair.Key) then
              begin
                // FP-Gate 2026-07-31 (mutually-exclusive-branches): FoT-
                // Zuweisung und Zugriff in then- bzw. else-Zweig desselben
                // if -> nie gemeinsam ausgefuehrt. Erst NACH dem Access-Match
                // pruefen (nur fuer echte Kandidaten, Hot-Path-schonend).
                if IsInExclusiveBranch(M, FoTN, N) then Continue;
                F            := TLeakFinding.Create;
                F.FileName   := FileName;
                F.MethodName := M.Name;
                F.LineNumber := IntToStr(N.Line);
                F.MissingVar := 'Access on "' + Pair.Key + '" after ' +
                                'FreeOnTerminate:=True (set at line ' +
                                IntToStr(Pair.Value) + ') - the thread may ' +
                                'have already self-destructed. Set the ' +
                                'reference to nil right after Start.';
                F.SetKind(fkThreadFreeOnTerminateWithRef);
                Results.Add(F);
              end;
            end;
          finally
            Assigns.Free;
          end;
          Calls := M.FindAll(nkCall);
          try
            for N in Calls do
            begin
              if N.Line <= GateLine then Continue;
              if HasDangerousMemberAccess(N.Name, Pair.Key) then
              begin
                // FP-Gate 2026-07-31 (mutually-exclusive-branches), s.o.
                if IsInExclusiveBranch(M, FoTN, N) then Continue;
                F            := TLeakFinding.Create;
                F.FileName   := FileName;
                F.MethodName := M.Name;
                F.LineNumber := IntToStr(N.Line);
                F.MissingVar := 'Call on "' + Pair.Key + '" after ' +
                                'FreeOnTerminate:=True (set at line ' +
                                IntToStr(Pair.Value) + ') - thread may have ' +
                                'self-destructed.';
                F.SetKind(fkThreadFreeOnTerminateWithRef);
                Results.Add(F);
              end;
            end;
          finally
            Calls.Free;
          end;
        end;
      finally
        FoTLine.Free;
        FoTNode.Free;
        ActLine.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
