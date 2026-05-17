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

class procedure TDeadCodeDetector.CheckBlock(BlockNode: TAstNode;
  const MethodName, FileName: string; Results: TObjectList<TLeakFinding>);
// Iterativ via Work-Stack - analog zu uAstNode.CollectAll. Vorher
// rekursiver Descent (Detectors/uDeadCode.pas alte Form) konnte bei
// pathologisch tiefen ASTs den Aufruf-Stack sprengen.
var
  WorkStack    : TStack<TAstNode>;
  Current      : TAstNode;
  i            : Integer;
  Child, Nxt   : TAstNode;
  IsTerminator : Boolean;
  TermName     : string;
  F            : TLeakFinding;
begin
  WorkStack := TStack<TAstNode>.Create;
  try
    WorkStack.Push(BlockNode);
    while WorkStack.Count > 0 do
    begin
      Current := WorkStack.Pop;
      i := 0;
      while i < Current.Children.Count do
      begin
        Child := Current.Children[i];

        // Verschachtelte Bloecke nicht rekursiv, sondern auf den Stack
        if Child.Kind in [nkBlock,
                          nkIfStmt, nkElseBranch,
                          nkCaseStmt, nkCaseArm,
                          nkForStmt, nkWhileStmt, nkRepeatStmt,
                          nkTryExcept, nkTryFinally,
                          nkExceptBlock, nkFinallyBlock,
                          nkOnHandler] then
          WorkStack.Push(Child);

        // Unbedingter Terminator als DIREKTES Kind dieses Blocks?
        // nkBreak/nkContinue nur in Loop-Bodies, nkExit/nkRaise immer.
        IsTerminator := False;
        TermName := '';
        case Child.Kind of
          nkExit:     begin IsTerminator := True; TermName := 'Exit';     end;
          nkRaise:    begin IsTerminator := True; TermName := 'raise';    end;
          nkBreak:    begin IsTerminator := True; TermName := 'Break';    end;
          nkContinue: begin IsTerminator := True; TermName := 'Continue'; end;
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
