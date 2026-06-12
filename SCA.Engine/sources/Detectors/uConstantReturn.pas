unit uConstantReturn;

// Detektor: Function weist `Result` mehrfach denselben Literal-Wert zu.
//
// Pattern (Code Smell, Sonar-50 #43):
//   function GetTimeout: Integer;
//   begin
//     if SlowMode then
//       Result := 30
//     else
//       Result := 30;             // <-- alle Pfade -> immer 30
//   end;
//
// Korrekt:
//   const DEFAULT_TIMEOUT = 30;
//   ...
//   function GetTimeout: Integer;
//   begin
//     Result := DEFAULT_TIMEOUT;  // oder: einfach die Konstante direkt nutzen
//   end;
//
// Folge: zwei oder mehr `Result := ...` mit IDENTISCHEM Literal sind
// entweder ein Refactoring-Rest (eines wurde nie angepasst) oder dead
// branching (das `if` hat keinen Effekt). Beides ist ein Smell.
//
// Erkennung (AST):
//   * nkMethod der Function ist (TypeRef enthaelt ':').
//   * Sammle ALLE nkAssign mit LHS = `result` oder `<FnName>`.
//   * Mindestens 2 solche Assigns vorhanden.
//   * Die RHS-Werte (Trimmed Child-Name des nkAssign-Subtree) sind ALLE
//     identisch UND sehen aus wie Literale (Zahl, String-Literal,
//     True/False/nil).
//   * -> Finding am Method-Header.
//
// Limitierungen:
//   * Mit Variablen-Referenzen statt Literalen: nicht erfasst (waere
//     ggf. legitim, z.B. `Result := DEFAULT_TIMEOUT;` zweimal).
//   * Nur die nkAssign-Children werden geprueft - komplexere RHS-Sub-
//     trees mit gleichem strukturellem Wert (`Result := 30 + 0` vs
//     `Result := 30`) werden NICHT als identisch erkannt.
//
// Schweregrad: lsHint - Refactoring-Empfehlung.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TConstantReturnDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file LongMethod, NestedTry, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

function UnqualifiedName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

function IsFunctionMethod(const TypeRef: string): Boolean;
// Parser legt MethKind + optional Returntyp + Direktiven in TypeRef ab:
//   procedure         -> 'procedure'
//   function: Integer -> 'function:Integer'
//   function: T; virtual -> 'function:T;virtual'
// Wir wollen alle Varianten matchen die mit 'function' beginnen.
begin
  Result := StartsText('function', Trim(TypeRef));
end;

function IsResultLhs(const LhsLow, FnNameLow: string): Boolean;
begin
  Result := (LhsLow = 'result') or (LhsLow = FnNameLow);
end;

function LooksLikeLiteral(const S: string): Boolean;
// Schmale Heuristik: Zahl, String-Literal, True/False/nil.
var
  T : string;
  Low : string;
  i : Integer;
  AllDigits : Boolean;
begin
  T := Trim(S);
  if T = '' then Exit(False);
  Low := LowerCase(T);
  if (Low = 'true') or (Low = 'false') or (Low = 'nil') then Exit(True);
  // String-Literal: beginnt + endet mit ''.
  if (T[1] = '''') and (T[Length(T)] = '''') then Exit(True);
  // Numerisches Literal (optional Vorzeichen + Ziffern, evtl. Punkt).
  AllDigits := True;
  for i := 1 to Length(T) do
    if not CharInSet(T[i], ['0'..'9', '-', '+', '.', '$', 'a'..'f', 'A'..'F']) then
    begin
      AllDigits := False;
      Break;
    end;
  Result := AllDigits;
end;

function ExtractRhs(N: TAstNode): string;
// Parser legt RHS-Text in nkAssign.TypeRef ab (uParser2.pas Z. 1618:
// "Node.TypeRef := FullRHS"). Children sind in der Regel leer.
// Defensiv: erstes Child als Fallback fuer aeltere AST-Formen.
begin
  if N.TypeRef <> '' then
    Result := Trim(N.TypeRef)
  else if N.Children.Count > 0 then
    Result := Trim(N.Children[0].Name)
  else
    Result := '';
end;

class procedure TConstantReturnDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods   : TList<TAstNode>;
  M         : TAstNode;
  Assigns   : TList<TAstNode>;
  N         : TAstNode;
  FnNameLow : string;
  LhsLow    : string;
  Rhs       : string;
  RhsSet    : TList<string>;
  Same      : Boolean;
  S         : string;
  F         : TLeakFinding;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not IsFunctionMethod(M.TypeRef) then Continue;
      FnNameLow := LowerCase(UnqualifiedName(M.Name));

      RhsSet := TList<string>.Create;
      Assigns := M.FindAll(nkAssign);
      try
        for N in Assigns do
        begin
          LhsLow := LowerCase(Trim(N.Name));
          if not IsResultLhs(LhsLow, FnNameLow) then Continue;
          Rhs := ExtractRhs(N);
          if not LooksLikeLiteral(Rhs) then
          begin
            // Wenn eine RHS NICHT-literal ist, koennen wir nicht
            // entscheiden -> Method skippen.
            RhsSet.Clear;
            Break;
          end;
          RhsSet.Add(Rhs);
        end;
        if RhsSet.Count < 2 then Continue;
        // Pruefen ob alle gleich.
        Same := True;
        for S in RhsSet do
          if S <> RhsSet[0] then
          begin
            Same := False;
            Break;
          end;
        if not Same then Continue;

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := M.Name;
        F.LineNumber := IntToStr(M.Line);
        F.MissingVar := Format(
          'Function %s always returns %s on every code path - use a named constant',
          [UnqualifiedName(M.Name), RhsSet[0]]);
        F.SetKind(fkConstantReturn);
        Results.Add(F);
      finally
        Assigns.Free;
        RhsSet.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
