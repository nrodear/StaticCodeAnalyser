unit uSelfAssignment;

// Detektor: `x := x;` - LHS textuell identisch zur RHS.
//
// In ~95 % aller Faelle ein Copy-Paste-Bug. Die seltenen legitimen
// Faelle sind:
//   * Property-Setter mit Side-Effects (z.B. `Visible := Visible;`
//     erzwingt Repaint in einer Buggy-VCL-Komponente)
//   * Compiler-Hint-Suppression (`Result := Result;` in pseudoabstrakten
//     Methoden, um "Result kann undefiniert sein" zu schweigen)
//
// Beide Faelle koennen mit `// noinspection` direkt vor der Zeile
// unterdrueckt werden.
//
// Erkennung: nkAssign mit `Trim(LowerCase(Name)) = Trim(LowerCase(TypeRef))`.
// Der Parser legt LHS in Name, RHS-Tokens als flachen String in TypeRef
// ab (uParser2.ParseCallOrAssign).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TSelfAssignmentDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CanBeStrictPrivate, GroupedDeclaration, StringConcatInLoop, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  EMIT_SEVERITY = lsWarning;

function Normalize(const S: string): string;
// Whitespace komplett raus + lowercase, damit `Obj . Field` und
// `Obj.Field` gleich sind.
var
  i : Integer;
  C : Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if C > ' ' then
      Result := Result + LowerCase(C);
  end;
end;

class procedure TSelfAssignmentDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Assigns : TList<TAstNode>;
  N       : TAstNode;
  Lhs, Rhs: string;
begin
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      Lhs := Normalize(N.Name);
      Rhs := Normalize(N.TypeRef);
      if (Lhs = '') or (Rhs = '') then Continue;
      if Lhs <> Rhs then Continue;

      Results.Add(TLeakFinding.New(FileName, MethodNode.Name, N.Line,
        Format('Self-assignment: %s := %s (no-op or copy-paste)',
          [N.Name, N.TypeRef]),
        fkSelfAssignment));
    end;
  finally
    Assigns.Free;
  end;
end;

class procedure TSelfAssignmentDetector.AnalyzeUnit(UnitNode: TAstNode;
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
