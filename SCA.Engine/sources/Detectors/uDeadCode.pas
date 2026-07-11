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
      Results: TObjectList<TLeakFinding>);
    class procedure CheckBlock(BlockNode: TAstNode;
      const MethodName, FileName: string;
      Results: TObjectList<TLeakFinding>); static;
  end;

implementation

// noinspection-file CyclomaticComplexity, DeepNesting, GroupedDeclaration, LongMethod, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

class procedure TDeadCodeDetector.CheckBlock(BlockNode: TAstNode;
  const MethodName, FileName: string; Results: TObjectList<TLeakFinding>);
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
  const FileName: string; Results: TObjectList<TLeakFinding>);
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
      CheckBlock(MethodNode.Children[i], MethodNode.Name, FileName, Results);
end;

class procedure TDeadCodeDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
