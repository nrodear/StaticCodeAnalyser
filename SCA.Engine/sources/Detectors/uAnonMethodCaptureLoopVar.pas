unit uAnonMethodCaptureLoopVar;

// Detektor: Anonyme Methode in for-Loop captured Loop-Variable per
// Reference -> alle Closures sehen am Ende denselben Wert.
//
// Pattern (Concurrency-Bug):
//   for i := 0 to 9 do
//     TThread.CreateAnonymousThread(procedure
//     begin
//       WriteLn(i);   // alle 10 Threads schreiben am Ende '10'
//     end).Start;
//
// Erkennung (AST + Text-Heuristik):
//   * Walk nkForStmt.
//   * Loop-Var aus ForNode.TypeRef extrahieren - erstes Identifier-
//     Token vor `:=` oder `in`. Inline-`var x := ...` Form auch
//     supported via nkLocalVar-Child.
//   * Im For-Subtree alle nkCall und nkAssign descendants.
//   * Pro Knoten Name/TypeRef scannen:
//       - `\bprocedure\b` (anonymous-method Start-Keyword, das in der
//         Code-Expression auftaucht z.B. `(procedure begin ... end)`)
//       - PLUS `\b<LoopVar>\b` (Loop-Var-Referenz im selben Knoten-
//         Text).
//   * Wenn beide -> Finding.
//
// FP-Tradeoff:
//   * `procedure` als Identifier (unwahrscheinlich) wuerde matchen.
//   * Lokale Variable mit selbem Namen wie Loop-Var in der Closure
//     wuerde matchen - der User braeuchte einen anderen Namen oder
//     `// noinspection AnonMethodCaptureLoopVar`.
//   * `for i in Coll do ... procedure(...) (i)` wo i ein NEUES Capture
//     ist (per-Iteration eigenes i) wuerde geflaggt - das ist seit
//     Delphi-?? laut Doku same-semantik. Akzeptabler FP.
//
// Severity: lsError, Type: ftBug.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAnonMethodCaptureLoopVarDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function ExtractLoopVar(ForNode: TAstNode): string; static;
  end;

implementation

uses
  System.RegularExpressions;

class function TAnonMethodCaptureLoopVarDetector.ExtractLoopVar(
  ForNode: TAstNode): string;
// Priorisierung:
//   1. nkLocalVar als Direct-Child (inline-var-Form `for var x := ...`)
//   2. TypeRef-Text vor `:=` oder ` in ` parsen
var
  Ch  : TAstNode;
  H   : string;
  P   : Integer;
  i   : Integer;
  C   : Char;
  Acc : string;
begin
  Result := '';
  // Inline-var-Form
  for Ch in ForNode.Children do
    if Ch.Kind = nkLocalVar then Exit(Ch.Name);
  // Klassische Form: erstes Identifier-Token in TypeRef.
  H := Trim(ForNode.TypeRef);
  if H = '' then Exit;
  // Erste Whitespace-getrennte Token-Sequenz vor ':=' / ' in '.
  for i := 1 to Length(H) do
  begin
    C := H[i];
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Acc := Acc + C
    else
      Break;
  end;
  Result := Acc;
end;

class procedure TAnonMethodCaptureLoopVarDetector.AnalyzeUnit(
  UnitNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
const
  // uParser2 konkateniert Tokens in ParsePrimary ohne Whitespace -
  // aus `procedure begin ... end` wird im Call-Expression-String
  // `procedurebegin...end`. Daher KEIN `\b` nach 'procedure'/'function'
  // sondern Lookahead auf das was anonymous-method-Marker einleitet:
  //   procedure(...)    procedurebegin    procedure:RetType
  //   function(...)     functionbegin     function:RetType
  ANON_RE = '\b(procedure|function)(begin|function|\(|:)';
var
  Fors    : TList<TAstNode>;
  Calls   : TList<TAstNode>;
  Assigns : TList<TAstNode>;
  ForNode : TAstNode;
  N       : TAstNode;
  LoopVar : string;
  VarRE   : TRegEx;
  Reported: TDictionary<Integer, Boolean>;
  F       : TLeakFinding;

  procedure CheckNode(N: TAstNode; const Expr: string);
  begin
    if Expr = '' then Exit;
    if Reported.ContainsKey(N.Line) then Exit;
    if not TRegEx.IsMatch(Expr, ANON_RE, [roIgnoreCase]) then Exit;
    if not VarRE.IsMatch(Expr) then Exit;
    Reported.AddOrSetValue(N.Line, True);
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(N.Line);
    F.MissingVar := 'Anonymous method inside `for ' + LoopVar + ' := ...` ' +
                    'references the loop variable "' + LoopVar + '" - the ' +
                    'closure captures it BY REFERENCE, so all instances see ' +
                    'the same final value. Copy to a local before the anon ' +
                    'method: `var L := ' + LoopVar + '; ...use L...`';
    F.SetKind(fkAnonMethodCaptureLoopVar);
    Results.Add(F);
  end;

begin
  Fors := UnitNode.FindAll(nkForStmt);
  try
    for ForNode in Fors do
    begin
      LoopVar := ExtractLoopVar(ForNode);
      if LoopVar = '' then Continue;
      VarRE := TRegEx.Create('\b' + LoopVar + '\b', [roIgnoreCase]);
      Reported := TDictionary<Integer, Boolean>.Create;
      try
        Calls := ForNode.FindAll(nkCall);
        try
          for N in Calls do CheckNode(N, N.Name);
        finally
          Calls.Free;
        end;
        Assigns := ForNode.FindAll(nkAssign);
        try
          for N in Assigns do CheckNode(N, N.TypeRef);
        finally
          Assigns.Free;
        end;
      finally
        Reported.Free;
      end;
    end;
  finally
    Fors.Free;
  end;
end;

end.
