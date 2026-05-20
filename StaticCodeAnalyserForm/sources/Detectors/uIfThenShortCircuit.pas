unit uIfThenShortCircuit;

// Detektor: `IfThen(cond, A(), B())` - sieht aus wie if-then-else, aber
// die "Arme" sind FUNCTION ARGUMENTS und werden BEIDE evaluiert,
// unabhaengig von cond.
//
// Pattern (Bug / Performance / Side-Effects):
//   x := Math.IfThen(IsCacheHit, FetchFromCache, FetchFromDb);
//   //                          ^^^^^^^^^^^^^^  ^^^^^^^^^^^^
//   //                          beide Calls laufen IMMER!
//
//   x := IfThen(WantSafeMode, RiskyOperation, SafeOperation);
//   //                        ^^^^^^^^^^^^^^  RiskyOp laeuft AUCH wenn
//   //                                        WantSafeMode True ist!
//
// Korrekt: klassisches if-then-else mit Short-Circuit-Semantik.
//   if IsCacheHit then
//     x := FetchFromCache
//   else
//     x := FetchFromDb;
//
// Warum: Sowohl `Math.IfThen` (Integer/Double) als auch `StrUtils.IfThen`
// (String) sind normale Funktionen mit drei Argumenten. Pascal-Calling-
// Conventions evaluieren alle Argumente VOR dem Call. Die Funktion erhaelt
// nur die fertigen Werte - sie kann den nicht-gewaehlten Pfad nicht mehr
// "ueberspringen". Bei Funktionen mit Side-Effects (DB-Read, File-IO,
// State-Mutation) oder schwerer Performance fuehrt das zu Bugs.
//
// Erkennung (AST-basiert):
//   * Walker iteriert nkCall-Knoten
//   * Match wenn der Call-Name dem Pattern `IfThen(...)` entspricht
//     (auch qualifiziert: `Math.IfThen`, `StrUtils.IfThen`).
//   * Innerhalb der Argument-Liste: pruefe ob nested `(...)` vorkommt,
//     d.h. einer der Arme ist ein Funktions-/Method-Call.
//   * String-Literale werden vor der Klammern-Zaehlung entfernt -
//     `IfThen(c, 'a(b)', 'x')` ist kein Funktions-Call.
//
// Sonar-Pendant: IfThenShortCircuitCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   IfThenShortCircuitCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TIfThenShortCircuitDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// True wenn CallName ein IfThen-Call ist (bare `IfThen(` oder qualifiziert
// `Math.IfThen(` / `StrUtils.IfThen(` / `System.Math.IfThen(` ...).
function IsIfThenCall(const CallName: string): Boolean;
var
  Lower : string;
begin
  Lower := LowerCase(TrimLeft(CallName));
  Result := (Pos('ifthen(',         Lower) = 1) or
            (Pos('math.ifthen(',    Lower) > 0) or
            (Pos('strutils.ifthen(', Lower) > 0);
  // Defensive: `xifthen(` wuerde matchen via `ifthen(` Substring-Pos=2+,
  // aber das schliessen wir aus (Pos = 1 only fuer den bare-Case).
  if not Result then Exit;
  // Pruefe dass keine Identifier-Zeichen vor 'ifthen(' stehen wenn der
  // Match nicht am Anfang ist.
  if Pos('ifthen(', Lower) = 1 then Exit(True);
  // Qualifiziert: muss '.ifthen(' sein, kein 'xifthen('.
  Result := (Pos('.ifthen(', Lower) > 0);
end;

// Extrahiert den Args-Teil zwischen aeusserer '(' und schliessender ')'.
// Geht von balancierten Parens aus.
function ExtractOuterArgs(const CallName: string): string;
var
  Open, Close, Depth, i : Integer;
begin
  Result := '';
  Open := Pos('(', CallName);
  if Open <= 0 then Exit;
  Depth := 0;
  Close := 0;
  for i := Open to Length(CallName) do
  begin
    case CallName[i] of
      '(': Inc(Depth);
      ')': begin
             Dec(Depth);
             if Depth = 0 then
             begin
               Close := i;
               Break;
             end;
           end;
    end;
  end;
  if Close <= Open then Exit;
  Result := Copy(CallName, Open + 1, Close - Open - 1);
end;

// True wenn der Args-String (ausserhalb von String-Literalen) eine
// '(' enthaelt - Hinweis auf einen verschachtelten Funktionsaufruf.
function ArgsContainNestedCall(const Args: string): Boolean;
var
  Cleaned : string;
  i       : Integer;
begin
  Result  := False;
  Cleaned := TDetectorUtils.StripStringLiterals(Args);
  for i := 1 to Length(Cleaned) do
    if Cleaned[i] = '(' then Exit(True);
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  i        : Integer;
  F        : TLeakFinding;
  MethName : string;
  Args     : string;
  NextMeth : TAstNode;
begin
  if Node = nil then Exit;
  if Node.Kind = nkCall then
  begin
    if IsIfThenCall(Node.Name) then
    begin
      Args := ExtractOuterArgs(Node.Name);
      if ArgsContainNestedCall(Args) then
      begin
        if Assigned(CurrentMethod) then MethName := CurrentMethod.Name
        else MethName := '';
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethName;
        F.LineNumber := IntToStr(Node.Line);
        F.MissingVar :=
          'IfThen() always evaluates both branches - use if/then/else for side-effecting calls';
        F.SetKind(fkIfThenShortCircuit);
        Results.Add(F);
      end;
    end;
  end;
  if Node.Kind = nkMethod then NextMeth := Node else NextMeth := CurrentMethod;
  for i := 0 to Node.Children.Count - 1 do
    WalkAndCheck(Node.Children[i], NextMeth, FileName, Results);
end;

class procedure TIfThenShortCircuitDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
