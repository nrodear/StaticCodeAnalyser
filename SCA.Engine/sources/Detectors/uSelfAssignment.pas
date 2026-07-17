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

function IsWordCh(const C: Char): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or
            ((C >= 'A') and (C <= 'Z')) or
            ((C >= '0') and (C <= '9')) or
            (C = '_');
end;

function Normalize(const S: string): string;
// Whitespace raus + lowercase, damit `Obj . Field` und `Obj.Field` gleich
// sind. ABER (Core-Audit 2026-07-17, SCA047): eine echte Wortgrenze - ein
// Space ZWISCHEN ZWEI Bezeichner-Zeichen, z.B. das Space in `not SaxMode` -
// MUSS als EIN Space erhalten bleiben. Sonst kollabiert
// `NotSaxMode := not SaxMode;` zu `notsaxmode` = `notsaxmode` und der Detektor
// meldet eine falsche Selbstzuweisung (betrifft auch and/or/div/mod/in/as/
// shl/shr/xor an Wortgrenzen). Der Parser (JoinTokInto) setzt Spaces ohnehin
// nur genau an solchen Wortgrenzen; an `.`/`[`/`(` faellt das Space weg, womit
// die Dot-Aequivalenz (`Obj . Field` = `Obj.Field`) erhalten bleibt.
var
  i   : Integer;
  C   : Char;
  Nxt : Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    C := S[i];
    if C > ' ' then
    begin
      Result := Result + LowerCase(C);
      Inc(i);
    end
    else
    begin
      // Whitespace-Lauf ueberspringen; nur wenn er zwei Ident-Zeichen trennt,
      // ein einzelnes Space als Wortgrenze setzen.
      Nxt := i;
      while (Nxt <= Length(S)) and (S[Nxt] <= ' ') do
        Inc(Nxt);
      if (Result <> '') and (Nxt <= Length(S)) and
         IsWordCh(Result[Length(Result)]) and IsWordCh(S[Nxt]) then
        Result := Result + ' ';
      i := Nxt;
    end;
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
