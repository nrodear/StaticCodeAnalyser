unit uUnusedLocal;

// Detector: lokale `var X: T;` die im Methoden-Body nie referenziert wird.
//
// Pendant zur Delphi-Compiler-Warnung H2164. Der SCA-Detector hat zwei
// Vorteile gegenueber dem Compiler:
//   * funktioniert ohne Build (CI / Pre-Commit-Pfade)
//   * im Grid / Hint-Panel mit Quick-Fix-Vorschlag
//   * via `// noinspection UnusedLocalVar` unterdrueckbar
//
// Erkennung:
//   * MethodNode.FindAll(nkLocalVar) → Liste der Var-Deklarationen
//   * Pro LocalVar: zaehle Vorkommen im Body (nkCall/nkAssign/nkIfStmt etc.)
//   * Skip-Regeln:
//     - Inline-`for var i := ...` (haeufig nur als Loop-Index genutzt, der
//       Loop-Header selbst zaehlt als Referenz - sicherheitshalber skippen)
//     - Name beginnt mit `_` (Konvention fuer "intentionally unused")
//     - Method-Body ist asm-Block (nicht durch unseren Parser zerlegt)
//
// Severity: lsHint (kein Bug, nur Cleanup).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnusedLocalDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

const
  EMIT_SEVERITY = lsHint;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z','a'..'z','0'..'9','_']);
end;

// Wortgrenzen-Suche case-insensitive. Liefert True wenn NeedleLow als
// ganzes Wort in HayLow vorkommt.
function ContainsWord(const HayLow, NeedleLow: string): Boolean;
var
  P, NL, HL : Integer;
  Before, After : Char;
begin
  Result := False;
  NL := Length(NeedleLow);
  HL := Length(HayLow);
  if (NL = 0) or (HL < NL) then Exit;
  P := 1;
  repeat
    P := Pos(NeedleLow, HayLow, P);
    if P = 0 then Exit;
    Before := #0;
    if P > 1 then Before := HayLow[P - 1];
    After := #0;
    if P + NL - 1 < HL then After := HayLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then
      Exit(True);
    P := P + NL;
  until False;
end;

// Iterativer Walk durch alle Descendants - sammelt Name+TypeRef pro Knoten.
// Iterativ, damit tiefe ASTs (z.B. nach Parser-Fix fuer inline-record) kein
// Stack-Overflow ausloesen.
procedure CollectAllTokens(Root: TAstNode; SB: TStringBuilder);
var
  Stack : TStack<TAstNode>;
  Cur : TAstNode;
  i : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Name    <> '' then SB.Append(' ').Append(Cur.Name);
      if Cur.TypeRef <> '' then SB.Append(' ').Append(Cur.TypeRef);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TUnusedLocalDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  LocalVars : TList<TAstNode>;
  LV : TAstNode;
  Name, LowName : string;
  BodySB : TStringBuilder;
  BodyLow : string;
  RefCount : Integer;
  F : TLeakFinding;
begin
  LocalVars := MethodNode.FindAll(nkLocalVar);
  BodySB := TStringBuilder.Create;
  try
    if LocalVars.Count = 0 then Exit;

    // Body-Tokens einmalig einsammeln + lowercase
    CollectAllTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);

    for LV in LocalVars do
    begin
      Name := Trim(LV.Name);
      if Name = '' then Continue;
      if Name.StartsWith('_') then Continue;     // Convention: ignored
      LowName := LowerCase(Name);

      // Mindestens ein Vorkommen MUSS die var-Deklaration sein. Wir wollen
      // Referenzen >= 2 (Deklaration + Nutzung). Wortgrenze stellt sicher
      // dass 'foo' nicht in 'fooBar' matcht.
      RefCount := 0;
      var P := 1;
      while True do
      begin
        P := Pos(LowName, BodyLow, P);
        if P = 0 then Break;
        var Before : Char := #0;
        if P > 1 then Before := BodyLow[P - 1];
        var After  : Char := #0;
        if P + Length(LowName) - 1 < Length(BodyLow) then
          After := BodyLow[P + Length(LowName)];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
          Inc(RefCount);
        P := P + Length(LowName);
      end;

      if RefCount <= 1 then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(LV.Line);
        F.MissingVar := Format(
          'Unused local variable: %s (declared but never read or written)',
          [Name]);
        F.Severity   := EMIT_SEVERITY;
        F.Kind       := fkUnusedLocalVar;
        Results.Add(F);
      end;
    end;
  finally
    BodySB.Free;
    LocalVars.Free;
  end;
end;

class procedure TUnusedLocalDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M : TAstNode;
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
