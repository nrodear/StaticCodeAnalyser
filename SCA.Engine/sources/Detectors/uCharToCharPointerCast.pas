unit uCharToCharPointerCast;

// Detektor: `PChar(<Char>)` / `PWideChar(<Char>)` / `PAnsiChar(<Char>)`
// Cast - Char-Wert wird als Pointer reinterpretiert.
//
// Pattern (Bug, undefined behavior):
//   var c: Char;
//   var p: PChar;
//   begin
//     c := 'A';
//     p := PChar(c);          // <-- BAD: p zeigt auf Adresse $00000041
//     ShowMessage(p);         //     vermutlich Access-Violation
//   end;
//
//   p := PChar('A');          // <-- BAD: identisch zum Variablen-Cast
//
// Korrekt:
//   p := PChar(string(c));    // expliziter String-Wrap
//   p := PChar('A' + #0);     // null-terminierter 1-Zeichen-String
//
// Warum:
//   * `PChar(stringExpr)` ist die uebliche Form - Pointer auf Char-Buffer
//     einer Pascal-String, garantiert null-terminiert.
//   * `PChar(charExpr)` reinterpretiert den 16-bit-Char-Wert als Pointer.
//     Die "Adresse" ist also der Codepoint des Zeichens (z.B. $41 fuer 'A').
//     Jeder Deref liest aus zufaelligem Process-Memory.
//
// Erkennung (AST-basiert, heuristisch):
//   * Walker iteriert nkCall-Knoten
//   * Match wenn Call-Name mit `PChar(`, `PWideChar(`, `PAnsiChar(` startet
//   * Argument-Heuristik (innerhalb der Klammern):
//     - 1-Zeichen-Literal: `'X'` (3 Zeichen Quotes inklusive)
//     - Char-Ordinal: `#<digits>` (z.B. `#65`, `#$41`)
//     - `Chr(...)`-Call: liefert Char
//   * String-Literale (`'AB'`, `'hello'`) sind als String getypt -> skip.
//   * Identifier-Argumente (`PChar(someVar)`) - unbekannter Typ ohne
//     Resolver - skip (false-negative bewusst).
//
// Sonar-Pendant: CharacterToCharacterPointerCastCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   CharacterToCharacterPointerCastCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TCharToCharPointerCastDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, MagicNumber, MultipleExit, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  CAST_PREFIXES: array of string = [
    'pchar(', 'pwidechar(', 'pansichar('
  ];

// Detektiert ob der Call-Name mit einem der PChar-Cast-Praefixe beginnt.
// Liefert den Cast-Typ-Namen oder leer.
function DetectPCharCast(const CallName: string): string;
var
  Lower : string;
  P     : string;
begin
  Result := '';
  Lower := LowerCase(TrimLeft(CallName));
  for P in CAST_PREFIXES do
    if (Length(Lower) >= Length(P)) and (Copy(Lower, 1, Length(P)) = P) then
    begin
      Result := Copy(P, 1, Length(P) - 1);
      Exit;
    end;
end;

// Extrahiert den Argument-Text aus `<Cast>(<arg>)`. Geht von einem Single-
// Argument-Cast aus (komma-getrennte Args wuerden hier zusammengeworfen,
// aber TypeCasts mit > 1 Argument gibt es nicht).
function ExtractCastArg(const CallName: string): string;
var
  P, L : Integer;
begin
  Result := '';
  P := Pos('(', CallName);
  if P <= 0 then Exit;
  L := Length(CallName);
  // Trailing ');' / ')' wegschneiden.
  while (L > 0) and ((CallName[L] = ';') or (CallName[L] = ' ')) do Dec(L);
  if (L > 0) and (CallName[L] = ')') then Dec(L);
  Result := Trim(Copy(CallName, P + 1, L - P));
end;

// True wenn Arg ein Single-Char-Literal ist: `'X'` (3 Zeichen, Quotes drumherum).
// Doppelte Anfuehrungszeichen `''''` (= einzelnes Apostroph) sind 4 Zeichen.
function IsSingleCharLiteral(const Arg: string): Boolean;
begin
  Result := False;
  // Format 'X' (3 Zeichen)
  if (Length(Arg) = 3) and (Arg[1] = '''') and (Arg[3] = '''') and
     (Arg[2] <> '''') then
    Exit(True);
  // Format '''' (4 Zeichen) = escaped apostrophe
  if Arg = '''''''' then Exit(True);
end;

// True wenn Arg ein Char-Ordinal-Literal `#<digits>` oder `#$<hex>` ist.
function IsCharOrdinal(const Arg: string): Boolean;
var
  i : Integer;
  C : Char;
begin
  Result := False;
  if Length(Arg) < 2 then Exit;
  if Arg[1] <> '#' then Exit;
  // Rest muss Digits oder $<hex> sein.
  i := 2;
  if Arg[i] = '$' then Inc(i);
  if i > Length(Arg) then Exit;
  while i <= Length(Arg) do
  begin
    C := Arg[i];
    if not (((C >= '0') and (C <= '9')) or
            ((C >= 'A') and (C <= 'F')) or
            ((C >= 'a') and (C <= 'f'))) then
      Exit;
    Inc(i);
  end;
  Result := True;
end;

// True wenn Arg ein `Chr(...)`-Call ist (case-insensitive).
function IsChrCall(const Arg: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(Arg);
  Result := (Length(Lower) >= 5) and (Copy(Lower, 1, 4) = 'chr(') and
            (Lower[Length(Lower)] = ')');
end;

function ArgLooksLikeChar(const Arg: string): Boolean;
begin
  Result := IsSingleCharLiteral(Arg) or
            IsCharOrdinal(Arg) or
            IsChrCall(Arg);
end;

// Pruefen ob `Text` (Call-Name oder Assign-TypeRef) einen Char->PChar-Cast
// enthaelt; bei Treffer Befund anlegen. Wird sowohl fuer nkCall (bare call,
// z.B. SomeProc(PChar('A'))) als auch fuer nkAssign.TypeRef (typischer
// Fall: p := PChar('A')) aufgerufen - der Parser packt die RHS einer
// Zuweisung in TypeRef statt einen separaten nkCall-Knoten anzulegen.
procedure CheckCastText(const Text: string; Node, CurrentMethod: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  MethName : string;
  CastType : string;
  Arg      : string;
begin
  CastType := DetectPCharCast(Text);
  if CastType = '' then Exit;
  Arg := ExtractCastArg(Text);
  if not ArgLooksLikeChar(Arg) then Exit;
  if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
  else MethName := '';
  Results.Add(TLeakFinding.New(FileName, MethName, Node.Line,
    Format('%s(Char) reinterprets codepoint as pointer - undefined behavior',
      [CastType]),
    fkCharToCharPointerCast));
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Hardening v4: iterative DFS mit Frame-Tracking. Verhindert
// STACK_OVERFLOW bei tief verschachteltem AST (siehe Audit_jvcl_segfault).
type
  TFrame = record
    N : TAstNode;
    M : TAstNode;   // CurrentMethod fuer diesen Knoten
  end;
var
  Stack : TList<TFrame>;
  Cur, F : TFrame;
  i      : Integer;
begin
  if Node = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F.N := Node; F.M := CurrentMethod;
    Stack.Add(F);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      case Cur.N.Kind of
        nkCall:
          CheckCastText(Cur.N.Name, Cur.N, Cur.M, FileName, Results);
        nkAssign:
          CheckCastText(Cur.N.TypeRef, Cur.N, Cur.M, FileName, Results);
      end;
      // Sub-Method-Boundary: nkMethod-Knoten startet eigenen Method-Scope
      var NextMeth : TAstNode;
      if Cur.N.Kind = nkMethod then NextMeth := Cur.N else NextMeth := Cur.M;
      for i := Cur.N.Children.Count - 1 downto 0 do
      begin
        F.N := Cur.N.Children[i]; F.M := NextMeth;
        Stack.Add(F);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TCharToCharPointerCastDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
