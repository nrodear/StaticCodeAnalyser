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
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class procedure CheckBlock(BlockNode: TAstNode;
      const MethodName, FileName: string;
      Results: TObjectList<TLeakFinding>); static;
  end;

implementation

class procedure TDeadCodeDetector.CheckBlock(BlockNode: TAstNode;
  const MethodName, FileName: string; Results: TObjectList<TLeakFinding>);
var
  i        : Integer;
  Child    : TAstNode;
  F        : TLeakFinding;
begin
  i := 0;
  while i < BlockNode.Children.Count do
  begin
    Child := BlockNode.Children[i];

    // Rekursiv in verschachtelte Bloecke und Kontrollstrukturen absteigen
    if Child.Kind in [nkBlock,
                      nkIfStmt, nkElseBranch,
                      nkCaseStmt, nkCaseArm,
                      nkForStmt, nkWhileStmt, nkRepeatStmt,
                      nkTryExcept, nkTryFinally,
                      nkExceptBlock, nkFinallyBlock,
                      nkOnHandler] then
      CheckBlock(Child, MethodName, FileName, Results);

    // Unbedingter Terminator als DIREKTES Kind dieses Blocks?
    // nkBreak/nkContinue nur in Loop-Bodies, nkExit/nkRaise immer.
    var IsTerminator := False;
    var TermName := '';
    case Child.Kind of
      nkExit:     begin IsTerminator := True; TermName := 'Exit';     end;
      nkRaise:    begin IsTerminator := True; TermName := 'raise';    end;
      nkBreak:    begin IsTerminator := True; TermName := 'Break';    end;
      nkContinue: begin IsTerminator := True; TermName := 'Continue'; end;
    end;

    if IsTerminator then
    begin
      // Gibt es noch weitere direkte Geschwister danach?
      if i + 1 < BlockNode.Children.Count then
      begin
        var Nxt := BlockNode.Children[i + 1];
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
        F.Severity   := lsWarning;
        F.Kind       := fkDeadCode;
        Results.Add(F);
        Break; // Pro Block nur einmal melden
      end;
    end;

    Inc(i);
  end;
end;

class procedure TDeadCodeDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Blocks : TList<TAstNode>;
  B      : TAstNode;
begin
  Blocks := MethodNode.FindAll(nkBlock);
  try
    for B in Blocks do
      CheckBlock(B, MethodNode.Name, FileName, Results);
  finally
    Blocks.Free;
  end;
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
