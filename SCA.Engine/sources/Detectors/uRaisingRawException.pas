unit uRaisingRawException;

// Detektor: `raise Exception.Create(...)` ohne spezifische Subklasse.
//
// Pattern (Code-Smell):
//   raise Exception.Create('something went wrong');
//
// Korrekt:
//   raise EArgumentOutOfRangeException.Create('value: ' + IntToStr(x));
//   raise EFileNotFoundException.Create(Filename);
//   raise EMyDomainError.Create(...);
//
// Warum: Die RTL-Basisklasse `Exception` ist semantisch genauso aussage-
// kraeftig wie ein Stringliteral "Error" - sie sagt nichts darueber, was
// schief gelaufen ist. Aufrufer koennen nicht selektiv mit
// `on E: ESpecificError do ...` reagieren und sind gezwungen, die
// gesamte Exception-Hierarchie zu fangen (`on E: Exception do ...`),
// was wiederum den ExceptionPattern-Detector triggert.
//
// Erkennung (AST-basiert):
//   * Walker iteriert nkRaise-Knoten
//   * nkRaise.Name enthaelt den geraiseten Ausdruck als String
//   * Match wenn Ausdruck mit 'Exception.Create' beginnt (case-insensitive)
//     oder gleich 'Exception' ist (raise Exception ohne Create)
//
// Bewusst NICHT Finding:
//   * `raise EFoo.Create(...)` - spezifische Subklasse, korrekt.
//   * `raise;` ohne Argument - bare re-raise, korrekt.
//   * `raise E` mit einer Variable - haendelt der ReRaiseException-Detector.
//
// Sonar-Pendant: RaisingRawExceptionCheck
// https://github.com/integrated-application-development/sonar-delphi/blob/
//   master/delphi-checks/src/main/java/au/com/integradev/delphi/checks/
//   RaisingRawExceptionCheck.java

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TRaisingRawExceptionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, GroupedDeclaration, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// True wenn der raise-Ausdruck genau die RTL-Klasse `Exception` instanziiert
// (case-insensitive, mit optionalen Leerzeichen).
function RaisesGenericException(const Expr: string): Boolean;
var
  Trimmed, Lower : string;
begin
  Trimmed := Trim(Expr);
  if Trimmed = '' then Exit(False);
  Lower := LowerCase(Trimmed);
  // Match 'exception.create(...)' am Anfang ODER bare 'exception' (selten,
  // aber syntaktisch zulaessig: 'raise Exception;' erzeugt nichts Brauchbares).
  Result := (Lower = 'exception') or
            (Pos('exception.create', Lower) = 1);
end;

procedure WalkAndCheck(Node, CurrentMethod: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Hardening v4: iterative DFS - siehe Audit_jvcl_segfault.
type TFrame = record N, M: TAstNode; end;
var
  Stack : TList<TFrame>;
  Cur, F : TFrame;
  i      : Integer;
  Find   : TLeakFinding;
  MethName : string;
  NextMeth : TAstNode;
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
      if (Cur.N.Kind = nkRaise) and RaisesGenericException(Cur.N.Name) then
      begin
        if Assigned(Cur.M) then MethName := Cur.M.Name else MethName := '';
        Find             := TLeakFinding.Create;
        Find.FileName    := FileName;
        Find.MethodName  := MethName;
        Find.LineNumber  := IntToStr(Cur.N.Line);
        Find.MissingVar  :=
          'Raising bare "Exception" - use a specific subclass (e.g. EArgumentException)';
        Find.SetKind(fkRaisingRawException);
        Results.Add(Find);
      end;
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

class procedure TRaisingRawExceptionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, nil, FileName, Results);
end;

end.
