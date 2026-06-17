unit uExceptInDestructor;

// Detektor: Destructor enthaelt `raise` ausserhalb eines schuetzenden
// try/except.
//
// Pattern (Bug, Sonar-50 #23):
//   destructor TFoo.Destroy;
//   begin
//     FList.Free;
//     if Bad then
//       raise EInvalidOp.Create('bad');   // <-- Crash beim Aufraeumen,
//                                          //     uebergeordneter Cleanup
//                                          //     verloren
//     inherited;
//   end;
//
// Korrekt:
//   destructor TFoo.Destroy;
//   begin
//     try
//       FList.Free;
//       if Bad then raise EInvalidOp.Create('bad');
//     except
//       Log('cleanup failed');
//       // raise weglassen oder bewusst durchreichen
//     end;
//     inherited;
//   end;
//
// Folge: Exception aus einem Destructor reisst die gerade laufende
// Cleanup-Sequenz ab; alle nachfolgenden FreeAndNil-Statements + das
// inherited Destroy bleiben uebersprungen -> Leak / inkonsistenter State.
//
// Erkennung (AST):
//   * nkMethod mit TypeRef startend mit `destructor` und KEIN `;class`
//     (Class-Destruktoren haben eigene Semantik).
//   * Rekursiver Walk: jeder nkRaise OHNE Vorfahr nkExceptBlock/nkOnHandler
//     -> Finding.
//
// Bewusst nicht geflaggt:
//   * Class-Destruktoren (TypeRef ';class') - laufen einmal pro Klasse,
//     anderes Risikoprofil.
//   * Forward-Decls ohne Body.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TExceptInDestructorDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BooleanParam, GroupedDeclaration, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function IsInstanceDestructor(MethodNode: TAstNode): Boolean;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  if Pos(';class', TR) > 0 then Exit(False);
  Result := TR.StartsWith('destructor');
end;

procedure CollectUnprotectedRaises(Node: TAstNode; InHandler: Boolean;
  Found: TList<TAstNode>);
// InHandler=True bedeutet: ein hier liegender raise ist durch
// einen umgebenden Handler protected und wird NICHT geflaggt.
//
// AST-Layout (uParser2 ParseTryStmt):
//   nkTryExcept
//   ├── (try-body statements, raises HIER sind durch das except gefangen)
//   └── nkExceptBlock
//       └── (handler statements, raises hier sind UN-gefangen
//            (re-raise propagiert raus))
//
// Wir markieren also try-body-Kinder von nkTryExcept als protected,
// aber NICHT die nkExceptBlock-Kinder.
var
  Child          : TAstNode;
  NextInHandler  : Boolean;
  ChildInHandler : Boolean;
  HasExcept      : Boolean;
begin
  NextInHandler := InHandler
    or (Node.Kind = nkExceptBlock)
    or (Node.Kind = nkOnHandler);

  if (Node.Kind = nkRaise) and not InHandler then
    Found.Add(Node);

  HasExcept := False;
  if Node.Kind = nkTryExcept then
    for Child in Node.Children do
      if Child.Kind = nkExceptBlock then
      begin
        HasExcept := True;
        Break;
      end;

  for Child in Node.Children do
  begin
    if (Node.Kind = nkTryExcept) and HasExcept and
       (Child.Kind <> nkExceptBlock) then
      ChildInHandler := True   // raise im try-body durch except gefangen
    else
      ChildInHandler := NextInHandler;
    CollectUnprotectedRaises(Child, ChildInHandler, Found);
  end;
end;

class procedure TExceptInDestructorDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  Raises  : TList<TAstNode>;
  M, R    : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      if not IsInstanceDestructor(M) then Continue;
      Raises := TList<TAstNode>.Create;
      try
        CollectUnprotectedRaises(M, False, Raises);
        for R in Raises do
          Results.Add(TLeakFinding.New(FileName, M.Name, R.Line,
            'Raise inside destructor without try/except - cleanup is ' +
            'aborted, inherited Destroy not called',
            fkExceptInDestructor));
      finally
        Raises.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
