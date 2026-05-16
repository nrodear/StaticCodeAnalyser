unit uNestedRoutines;

// Detektor fuer geschachtelte Routinen (nested procedures/functions
// innerhalb einer anderen Methode).
//
// SonarDelphi-Aequivalent: Aehnlich zu communitydelphi:NestedRoutines /
// AvoidNestedRoutines (je nach Fork-Version). Lokale geschachtelte
// Routinen sind in Delphi syntaktisch erlaubt, machen aber Refactorings
// schwierig (nicht testbar in Isolation, schwer wiederverwendbar) und
// blaehen Methoden auf.
//
// Erkennung: AST-Walk. Pro nkMethod-Knoten den Subtree besuchen; wenn
// im Subtree ein weiterer nkMethod-Knoten gefunden wird, ist dieser
// geschachtelt -> Treffer auf der Zeile des inneren Knotens.
//
// Anonyme Methoden (anonymous methods / lambdas via `procedure(...)
// begin ... end`) sind in modernem Delphi ueblich und werden hier NICHT
// gemeldet - sie haben in der Regel keinen Namen (Node.Name = '').
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TNestedRoutinesDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  EMIT_SEVERITY = lsHint;

procedure WalkForNestedMethods(Node: TAstNode; InsideMethod: Boolean;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Child : TAstNode;
  F     : TLeakFinding;
  Nested: Boolean;
begin
  if Node = nil then Exit;
  if (Node.Kind = nkMethod) and InsideMethod and (Trim(Node.Name) <> '') then
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := Node.Name;
    F.LineNumber := IntToStr(Node.Line);
    F.MissingVar := Format(
      'Nested routine `%s` - extract to unit-level to enable testing ' +
      'and reuse.', [Node.Name]);
    F.SetKind(fkNestedRoutine);
    Results.Add(F);
  end;
  Nested := InsideMethod or (Node.Kind = nkMethod);
  for Child in Node.Children do
    WalkForNestedMethods(Child, Nested, FileName, Results);
end;

class procedure TNestedRoutinesDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkForNestedMethods(UnitNode, False, FileName, Results);
end;

end.
