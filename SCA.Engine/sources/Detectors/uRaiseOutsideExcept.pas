unit uRaiseOutsideExcept;

// Detektor: nacktes `raise;` ausserhalb eines except-/on-Handlers.
//
// Pattern (Bug, Sonar-50 #15):
//   procedure Foo;
//   begin
//     if x < 0 then
//       raise;                     // <-- AV: keine aktuelle Exception
//   end;
//
// Korrekt:
//   procedure Foo;
//   begin
//     if x < 0 then
//       raise EArgumentException.Create('x negative');
//   end;
//
//   // oder, wenn die Absicht "re-raise" war:
//   procedure Bar;
//   begin
//     try
//       DoStuff;
//     except
//       Log('failed');
//       raise;                     // <-- OK: aktuelle Exception weiterleiten
//     end;
//   end;
//
// Folge: bare `raise;` ohne aktive Exception loest eine Access Violation
// im RTL aus (System._Raise sucht ein NIL-Exception-Objekt). Der Caller
// bekommt also eine AV statt der gewollten Exception - der Stack-Trace
// fuehrt zur falschen Stelle und das echte Problem bleibt unklar.
//
// Erkennung (AST):
//   Parser legt `raise;` als nkRaise mit Name='raise' ab; `raise <expr>;`
//   ueberschreibt Name mit der geparsten Expression. Also: nkRaise mit
//   Name='raise' = bare raise.
//
// Kontext-Filter: bare raise INNERHALB nkExceptBlock oder nkOnHandler
// ist korrekt (re-raise). Wir traversieren das Method-AST rekursiv und
// fuehren ein "InHandler"-Flag mit. Nur wenn das Flag bei einem nkRaise
// mit Name='raise' False ist, geben wir einen Befund aus.
//
// Bewusste Limitierung:
//   * `try ... except try ... finally raise; end end;` - bare raise im
//     finally INNERHALB eines except-Handlers wird als sicher gewertet
//     (InHandler=True), obwohl die genaue Semantik (re-raise der
//     ausseren Exception) edge-case-abhaengig ist. Niedrige FP-Quote
//     wichtiger als perfekte Praezision.
//
// Sonar-Pendant: java:S00112 (Java) / RSPEC-2221 (general).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TRaiseOutsideExceptDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

procedure WalkForBareRaise(N: TAstNode; const FileName, MethodName: string;
  Results: TObjectList<TLeakFinding>; InHandler: Boolean);
// Hardening v4: iterative DFS - siehe Audit_jvcl_segfault.
type TFrame = record Nd: TAstNode; InH: Boolean; end;
var
  Stack : TList<TFrame>;
  Cur, F2 : TFrame;
  i      : Integer;
  NextInHandler : Boolean;
  F      : TLeakFinding;
begin
  if N = nil then Exit;
  Stack := TList<TFrame>.Create;
  try
    F2.Nd := N; F2.InH := InHandler;
    Stack.Add(F2);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      // Children inherit the InHandler-flag updated if current is a handler
      NextInHandler := Cur.InH or (Cur.Nd.Kind = nkExceptBlock) or
                                  (Cur.Nd.Kind = nkOnHandler);
      if (Cur.Nd.Kind = nkRaise) and SameText(Cur.Nd.Name, 'raise')
         and not Cur.InH then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodName;
        F.LineNumber := IntToStr(Cur.Nd.Line);
        F.MissingVar :=
          'Bare `raise;` outside an except/on handler raises NIL - Access Violation';
        F.SetKind(fkRaiseOutsideExcept);
        Results.Add(F);
      end;
      for i := Cur.Nd.Children.Count - 1 downto 0 do
      begin
        F2.Nd := Cur.Nd.Children[i]; F2.InH := NextInHandler;
        Stack.Add(F2);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class procedure TRaiseOutsideExceptDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkForBareRaise(MethodNode, FileName, MethodNode.Name, Results, False);
end;

class procedure TRaiseOutsideExceptDetector.AnalyzeUnit(UnitNode: TAstNode;
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
