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
// SQL-Shape-Validierung (FP-Schutz gegen englische Meldungstexte):
//   * UPDATE-Match braucht zusaetzlich ' set ' im Fragment - sonst ist
//     der String ein Error-Message-Literal wie 'Update failed for X'
//     und kein SQL-Statement.
//   * Bare 'DELETE ' (ohne FROM) wird gar nicht erst gematcht - echtes
//     SQL-DELETE hat per Syntax IMMER FROM, sodass ein Match ohne FROM
//     immer englischer Text waere ('Delete failed', 'Cannot delete').
//   * TRUNCATE bleibt liberal - in Delphi-Quellen praktisch nie als
//     englisches Verb verwendet, der DB-Schaden waere maximal.
//
// Severity: lsError (Production-Disaster).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

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
  // Bare 'delete ' (ohne FROM) bewusst NICHT in der Liste - echtes SQL-DELETE
  // hat per Syntax immer FROM; ein Match ohne FROM waere garantiert englischer
  // Text ('Delete failed', 'Cannot delete record', ...).
  VERBS : array[0..2] of string = (
    '''update ', '''delete from ', '''truncate '
  );
var
  Merged : string;
  V : string;
  P, EndPos : Integer;
  Fragment : string;
begin
  // Pascal-'+'-Konkatenations-Ketten zu einem virtuellen Literal falten,
  // BEVOR wir nach ' where ' suchen. Sonst fallen Faelle wie
  //   'UPDATE x SET y=? ' + 'WHERE id=?'
  // faelschlich durch (zwischen `?` und `WHERE` sitzt `'+'` statt Space).
  Merged := TDetectorUtils.MergeAdjacentStringLiterals(Low);

  // FP-Schutz: wenn der String-Literal-Inhalt selbst Pascal-Code-Pattern
  // ':=' enthaelt, ist es ein Quickfix-Template das Pascal-Quelltext zitiert
  // ('qry.SQL.Text := ''UPDATE ...''';), kein echtes SQL-Statement.
  // SQL kennt ':=' praktisch nie (':' = Named-Param, '=' = Vergleich;
  // ':=' nur in exotischen Trigger-Bodies, in Delphi-Query-Strings nie).
  if Pos(':=', Merged) > 0 then Exit(False);

  Result := False;
  Verb   := '';
  for V in VERBS do
  begin
    P := Pos(V, Merged);
    if P <= 0 then Continue;
    // Statement-Ende: naechstes nicht-escaped Apostroph nach P+1, oder
    // String-Ende. Wir nehmen alles bis zum naechsten ;-Token-Trenner.
    EndPos := Pos(''';', Merged, P + Length(V));
    if EndPos <= 0 then EndPos := Length(Merged);
    Fragment := Copy(Merged, P, EndPos - P + 1);

    // SQL-Shape-Validierung: UPDATE braucht ' set ' im Fragment, sonst ist
    // es ein englisches Error-Message-Literal ('Update failed for X') und
    // kein SQL-Statement. DELETE FROM und TRUNCATE sind in Pascal-Literalen
    // spezifisch genug, dass keine zusaetzliche Pruefung noetig ist.
    if (V = '''update ') and (Pos(' set ', Fragment) = 0) then Continue;

    // Pruefen ob WHERE vorkommt (Fragment ist bereits lowercase, siehe Caller).
    if Pos(' where ', Fragment) > 0 then Continue;
    // TRUNCATE ist immer gefaehrlich (kein WHERE moeglich).
    // UPDATE/DELETE FROM: WHERE fehlt -> Treffer.
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
