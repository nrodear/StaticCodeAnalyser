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

uses
  uAstSpans;   // CollectWithMethodScope (Voll-Review 2026-09-12)

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

procedure WalkAndCheck(Node: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
// Seit Voll-Review 2026-09-12 ueber den zentralen Scope-Walk
// (TAstSpans.CollectWithMethodScope) - Mechanik, Besuchsreihenfolge
// und Hardening v4 (iterative DFS, Audit_jvcl_segfault) identisch
// zur frueheren lokalen Kopie.
var
  P        : TNodeScopePair;
  MethName : string;
begin
  for P in TAstSpans.CollectWithMethodScope(Node, [nkRaise]) do
    if RaisesGenericException(P.Node.Name) then
    begin
      if Assigned(P.Method) then MethName := P.Method.Name
      else MethName := '';
      Results.Add(TLeakFinding.New(FileName, MethName, P.Node.Line,
        'Raising bare "Exception" - use a specific subclass (e.g. EArgumentException)',
        fkRaisingRawException));
    end;
end;

class procedure TRaisingRawExceptionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
begin
  WalkAndCheck(UnitNode, FileName, Results);
end;

end.
