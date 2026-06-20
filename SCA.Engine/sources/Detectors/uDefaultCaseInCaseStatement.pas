unit uDefaultCaseInCaseStatement;

// Detektor: case-Statement ohne else-Branch.
//
// Pattern:
//   case Status of
//     stNew    : DoNew;
//     stActive : DoActive;
//   end;
//   // BUG wenn Status z.B. stCancelled annimmt - keine Handler-Aktion,
//   // keine Fehlermeldung, schwer zu finden.
//
// Erkennung (AST):
//   * nkCaseStmt walken.
//   * Children sind nkCaseArm; das else-Arm hat Name='else' (siehe
//     uParser2 ~Z.1418).
//   * Wenn KEIN Child mit Name='else' existiert -> Finding.
//
// FP-Tradeoff:
//   * Wir flaggen ALLE else-losen case-Statements, ohne Symbol-Table-
//     Check ob das case-Expr eine Enum ist die alle Werte abdeckt.
//     Damit faengt MVP auch Integer-/String-case-Statements wo der
//     User bewusst nur einen Subset behandelt - der explizite `else
//     ;` (no-op) ist die saubere Form ("alle anderen Werte: nichts
//     tun, dokumentiert").
//   * Severity Hint (statt Warning), damit das in der Default-Profile
//     nicht zu laut wird.
//
// Severity: lsHint, Type: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDefaultCaseInCaseStatementDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TDefaultCaseInCaseStatementDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Cases   : TList<TAstNode>;
  C, Arm  : TAstNode;
  HasElse : Boolean;
  F       : TLeakFinding;
begin
  Cases := UnitNode.FindAll(nkCaseStmt);
  try
    for C in Cases do
    begin
      HasElse := False;
      for Arm in C.Children do
        if (Arm.Kind = nkCaseArm) and SameText(Arm.Name, 'else') then
        begin
          HasElse := True;
          Break;
        end;
      if HasElse then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar := 'case statement without else - unhandled values fall ' +
                      'through silently. Add `else ;` (intentional no-op) or ' +
                      'a default handler.';
      F.SetKind(fkDefaultCaseInCaseStatement);
      Results.Add(F);
    end;
  finally
    Cases.Free;
  end;
end;

end.
