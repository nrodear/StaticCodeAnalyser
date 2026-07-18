unit uDeadCode;

// Detektor fuer toten Code (Sonar-Regel #10).
//
// Erkennt Anweisungen in einem begin..end-Block, die nach einem
// unbedingten Kontrollfluss-Transfer (Exit, raise) stehen und
// daher niemals ausgefuehrt werden.
//
// Beispiel:
//   begin
//     Exit;
//     DoSomething;   <- toter Code – wird nie erreicht
//   end;
//
// Kein Befund fuer:
//   if Condition then
//     Exit;
//   DoSomething;     <- korrekt, da Exit im if-Zweig bedingt ist

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDeadCodeDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; const ADirLines: TArray<Integer>;
      const ALabelLines: TArray<Integer>);
    class procedure CheckBlock(BlockNode: TAstNode;
      const MethodName, FileName: string;
      Results: TObjectList<TLeakFinding>;
      const ADirLines: TArray<Integer>;
      const ALabelLines: TArray<Integer>); static;
  end;

implementation

// noinspection-file CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function DirLineBetween(const Lines: TArray<Integer>; A, B: Integer): Boolean;
// Welle 3: True wenn eine {$IFDEF}-Direktiven-Zeile strikt zwischen A und B liegt.
// Dann stehen Terminator (A) und Folgeanweisung (B) in verschiedenen bedingten
// Kompilierungs-Zweigen -> die Folgeanweisung ist NICHT unbedingt tot (FP).
var d: Integer;
begin
  for d in Lines do
    if (d > A) and (d < B) then Exit(True);
  Result := False;
end;

function LineInArray(const Lines: TArray<Integer>; L: Integer): Boolean;
// SCA011-Goto-Guard: True wenn L eine der Label-Target-Zeilen ist. Eine
// Anweisung auf einer solchen Zeile ist per 'goto lbl' erreichbar -> nie
// unbedingt tot (FP-Klasse 'goto-label-target').
var v: Integer;
begin
  for v in Lines do
    if v = L then Exit(True);
  Result := False;
end;

class procedure TDeadCodeDetector.CheckBlock(BlockNode: TAstNode;
  const MethodName, FileName: string; Results: TObjectList<TLeakFinding>;
  const ADirLines: TArray<Integer>; const ALabelLines: TArray<Integer>);
// Iterativ via Work-Stack - analog zu uAstNode.CollectAll. Vorher
// rekursiver Descent (Detectors/uDeadCode.pas alte Form) konnte bei
// pathologisch tiefen ASTs den Aufruf-Stack sprengen.
var
  WorkStack    : TStack<TAstNode>;
  DepthStack   : TStack<Integer>;
  Current      : TAstNode;
  CurDepth     : Integer;
  ChildDepth   : Integer;
  i            : Integer;
  Child, Nxt   : TAstNode;
  IsTerminator : Boolean;
  TermName     : string;
  F            : TLeakFinding;
begin
  // DepthStack laeuft im Gleichschritt mit WorkStack und traegt die
  // Loop-Verschachtelungstiefe des jeweiligen Knotens mit (0 = ausserhalb
  // jeder Schleife). Break/Continue beziehen sich immer auf die innerste
  // umschliessende Schleife und sind nur in deren Rumpf gueltig.
  WorkStack  := TStack<TAstNode>.Create;
  DepthStack := TStack<Integer>.Create;
  try
    WorkStack.Push(BlockNode);
    DepthStack.Push(0);
    while WorkStack.Count > 0 do
    begin
      Current  := WorkStack.Pop;
      CurDepth := DepthStack.Pop;
      i := 0;
      while i < Current.Children.Count do
      begin
        Child := Current.Children[i];

        // Verschachtelte Bloecke nicht rekursiv, sondern auf den Stack.
        // nkFor/nkWhile/nkRepeat erhoehen die Loop-Tiefe fuer alle
        // Nachkommen; jeder Push nimmt seine Tiefe auf den DepthStack mit.
        if Child.Kind in [nkBlock,
                          nkIfStmt, nkElseBranch,
                          nkCaseStmt, nkCaseArm,
                          nkForStmt, nkWhileStmt, nkRepeatStmt,
                          nkTryExcept, nkTryFinally,
                          nkExceptBlock, nkFinallyBlock,
                          nkOnHandler] then
        begin
          ChildDepth := CurDepth;
          if Child.Kind in [nkForStmt, nkWhileStmt, nkRepeatStmt] then
            Inc(ChildDepth);
          WorkStack.Push(Child);
          DepthStack.Push(ChildDepth);
        end;

        // Unbedingter Terminator als DIREKTES Kind dieses Blocks?
        // nkExit/nkRaise sind immer Terminatoren. nkBreak/nkContinue nur,
        // wenn wir tatsaechlich im Rumpf einer Schleife stehen (CurDepth>0).
        // FP-Guard (Real-World-FP-Audit 2026-07-10,
        // 'continue-as-local-variable'): 'continue := true;' bzw.
        // 'break(...)' ausserhalb jeder Schleife ist eine lokale Variable/
        // Routine, die der Parser als nkContinue/nkBreak fehlerkennt - kein
        // toter Code. Ein echtes Break/Continue ausserhalb einer Schleife
        // waere zudem ein Compilerfehler, kann also nie ein True Positive
        // sein; das Unterdruecken hier ist TP-sicher.
        IsTerminator := False;
        TermName := '';
        case Child.Kind of
          nkExit:     begin IsTerminator := True; TermName := 'Exit';  end;
          nkRaise:    begin IsTerminator := True; TermName := 'raise'; end;
          nkBreak:    if CurDepth > 0 then
                      begin IsTerminator := True; TermName := 'Break';    end;
          nkContinue: if CurDepth > 0 then
                      begin IsTerminator := True; TermName := 'Continue'; end;
        end;

        if IsTerminator then
        begin
          // Gibt es noch weitere direkte Geschwister danach?
          if i + 1 < Current.Children.Count then
          begin
            Nxt := Current.Children[i + 1];
            // Nicht-sequentielle Geschwister sind kein toter Code:
            //   - nkElseBranch     : alternativer if-Zweig
            //   - nkExceptBlock    : Exception-Handler (nur bei Exception)
            //   - nkFinallyBlock   : Cleanup (immer, aber nicht sequentiell)
            //   - nkOnHandler      : einzelner on-Zweig im except
            if Nxt.Kind in [nkElseBranch, nkExceptBlock,
                            nkFinallyBlock, nkOnHandler] then
            begin
              Inc(i); Continue;
            end;

            // FP-Guard (Real-World-FP-Audit 2026-07-10, 'raise-at-clause'):
            // 'raise E.Create(m) at ReturnAddress;' parst als nkRaise + separater
            // Folgeknoten fuer die 'at <addr>'-Klausel auf DERSELBEN Quellzeile.
            // Das ist kein toter Code, sondern Teil desselben raise-Statements.
            // NUR fuer nkRaise + gleiche Zeile skippen - 'Exit; DoStuff;' (Exit,
            // echter toter Code auf gleicher Zeile) bleibt bewusst ein Fund.
            if (Child.Kind = nkRaise) and (Nxt.Line > 0)
               and (Nxt.Line <= Child.Line) then
            begin
              Inc(i); Continue;
            end;

            // Welle 3 (Core-Detektoren-Architektur): liegt eine {$IFDEF}-
            // Direktiven-Grenze zwischen Terminator und Folgeanweisung, stehen
            // beide in verschiedenen bedingten Kompilierungs-Zweigen -> die
            // Folgeanweisung ist NICHT unbedingt tot (preprocessor-branch-FP).
            if DirLineBetween(ADirLines, Child.Line, Nxt.Line) then
            begin
              Inc(i); Continue;
            end;

            // FP-Guard (Welle 1 5%-FP-Konzept 2026-07-18, 'goto-label-target'):
            // Steht die Folgeanweisung auf der Zeile eines Label-Targets
            // ('lbl: stmt;'), ist sie per 'goto lbl' erreichbar -> kein toter
            // Code. FastCode/mORMot/BrainMM-Hotpaths nutzen das massiv
            // (exit; Ret0: Result := False;). Die Label-Zeilen kommen als
            // nkLabelMark-Marker aus dem Parser (uParser2 ParseCallOrAssign).
            if LineInArray(ALabelLines, Nxt.Line) then
            begin
              Inc(i); Continue;
            end;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := MethodName;
            F.LineNumber := IntToStr(Nxt.Line);
            F.MissingVar := 'Dead code after ' + TermName;
            F.SetKind(fkDeadCode);
            Results.Add(F);
            Break; // Pro Block nur einmal melden
          end;
        end;

        Inc(i);
      end;
    end;
  finally
    DepthStack.Free;
    WorkStack.Free;
  end;
end;

class procedure TDeadCodeDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  const ADirLines: TArray<Integer>; const ALabelLines: TArray<Integer>);
var
  i : Integer;
begin
  // NUR direkte nkBlock-Kinder dieser Methode verarbeiten. CheckBlock
  // selbst recurses durch alle nested Bloecke (inkl. nkForStmt-/nkWhile-
  // Bodies). Wenn wir hier FindAll(nkBlock) nutzen wuerden, bekaemen wir
  // alle nested Bloecke - die werden dann pro Block einmal besucht UND
  // zusaetzlich via CheckBlock-Recursion vom Parent aus -> doppelte
  // Findings (z.B. 'for begin Break; DoOther; end' meldet Dead-Code
  // doppelt: einmal beim direkten Visit des inner-blocks, einmal bei
  // der Recursion vom outer-block durch nkForStmt).
  for i := 0 to MethodNode.Children.Count - 1 do
    if MethodNode.Children[i].Kind = nkBlock then
      CheckBlock(MethodNode.Children[i], MethodNode.Name, FileName, Results,
                 ADirLines, ALabelLines);
end;

class procedure TDeadCodeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods    : TList<TAstNode>;
  M          : TAstNode;
  CondR      : TList<TAstNode>;
  DirLines   : TArray<Integer>;
  LblN       : TList<TAstNode>;
  LabelLines : TArray<Integer>;
  R          : TAstNode;
  n          : Integer;
begin
  // Welle 3: {$IFDEF}-Direktiven-Zeilen aus den nkConditionalRange-Markern
  // sammeln (Start=Node.Line, Ende=TypeRef). Preprocessor-branch-Guard fuer
  // 'Code nach Exit/Raise steht in einem anderen bedingten Zweig'.
  CondR := UnitNode.FindAll(nkConditionalRange);
  try
    n := 0;
    SetLength(DirLines, CondR.Count * 2);
    for R in CondR do
    begin
      DirLines[n] := R.Line; Inc(n);
      DirLines[n] := StrToIntDef(R.TypeRef, R.Line); Inc(n);
    end;
  finally
    CondR.Free;
  end;

  // SCA011-Goto-Guard: Quellzeilen von Label-Targets aus den nkLabelMark-
  // Markern sammeln (analog DirLines). Anweisungen auf diesen Zeilen sind per
  // 'goto lbl' erreichbar -> kein toter Code.
  LblN := UnitNode.FindAll(nkLabelMark);
  try
    SetLength(LabelLines, LblN.Count);
    n := 0;
    for R in LblN do
    begin
      LabelLines[n] := R.Line; Inc(n);
    end;
  finally
    LblN.Free;
  end;

  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results, DirLines, LabelLines);
  finally
    Methods.Free;
  end;
end;

end.
