unit uSqlDangerousStatement;

// Detektor: UPDATE-/DELETE-/TRUNCATE-Statement OHNE WHERE-Klausel.
//
// Production-Disaster-Pattern: wenn eine WHERE-Klausel fehlt, betrifft
// das Statement ALLE Zeilen der Tabelle:
//   UPDATE customers SET locked=1;     // sperrt JEDEN Kunden
//   DELETE FROM orders;                // loescht ALLE Bestellungen
//   TRUNCATE TABLE log;                // ohne Where unzulaessig (Per Definition)
//
// Erkennung:
//   * AST-basiert (sieht auch Statement in nkAssign / nkCall analog
//     uSQLInjection)
//   * SQL-Text in String-Literal: 'UPDATE ', 'DELETE FROM ', 'TRUNCATE '
//   * WHERE-Klausel: case-insensitive ' WHERE ' im selben String
//   * Konservativ: nur direkte Stringliterale, keine Konkat-Ketten
//     (die werden bereits von uSQLInjection mit anderem Bias erfasst).
//
// Severity: lsError (Production-Disaster).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TSqlDangerousStatementDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Sucht im flach-getokenten RHS/Call-Name nach einem gefaehrlichen
    // SQL-Statement und liefert den Action-Verb-Token zurueck.
    class function FindDangerousVerb(const Low: string;
      out Verb: string): Boolean; static;
  end;

implementation

const
  EMIT_SEVERITY = lsError;

class function TSqlDangerousStatementDetector.FindDangerousVerb(
  const Low: string; out Verb: string): Boolean;
const
  VERBS : array[0..3] of string = (
    '''update ', '''delete from ', '''delete ', '''truncate '
  );
var
  V : string;
  P, EndPos : Integer;
  Fragment : string;
begin
  Result := False;
  Verb   := '';
  for V in VERBS do
  begin
    P := Pos(V, Low);
    if P <= 0 then Continue;
    // Statement-Ende: naechstes nicht-escaped Apostroph nach P+1, oder
    // String-Ende. Wir nehmen alles bis zum naechsten ;-Token-Trenner.
    EndPos := Pos(''';', Low, P + Length(V));
    if EndPos <= 0 then EndPos := Length(Low);
    Fragment := Copy(Low, P, EndPos - P + 1);

    // Pruefen ob WHERE vorkommt (Fragment ist bereits lowercase, siehe Caller).
    if Pos(' where ', Fragment) > 0 then Continue;
    // TRUNCATE ist immer gefaehrlich (kein WHERE moeglich).
    // UPDATE/DELETE FROM/DELETE: WHERE fehlt -> Treffer.
    Verb := Trim(V);
    // Apostroph-Praefix abschneiden fuer den User-Output
    if (Length(Verb) > 0) and (Verb[1] = '''') then
      Verb := Copy(Verb, 2, MaxInt);
    Verb := UpperCase(Verb);
    Exit(True);
  end;
end;

class procedure TSqlDangerousStatementDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure Report(const Verb, Context: string; Line: Integer);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Format(
      'Dangerous SQL: %s without WHERE - affects ALL rows. Context: %s',
      [Verb, Context]);
    F.SetKind(fkSqlDangerousStatement);
    Results.Add(F);
  end;

var
  Assigns, Calls : TList<TAstNode>;
  N : TAstNode;
  Low, Verb : string;
begin
  // nkAssign: SQL.Text := 'UPDATE customers SET locked=1';
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      Low := LowerCase(N.TypeRef);
      if FindDangerousVerb(Low, Verb) then
        Report(Verb, N.Name, N.Line);
    end;
  finally
    Assigns.Free;
  end;

  // nkCall: ExecSQL('DELETE FROM logs');
  Calls := MethodNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      Low := LowerCase(N.Name);
      if FindDangerousVerb(Low, Verb) then
        Report(Verb, N.Name, N.Line);
    end;
  finally
    Calls.Free;
  end;
end;

class procedure TSqlDangerousStatementDetector.AnalyzeUnit(UnitNode: TAstNode;
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
