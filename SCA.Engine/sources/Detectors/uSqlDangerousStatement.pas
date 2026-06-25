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

// noinspection-file BeginEndRequired, CanBeClassMethod, CommentedOutCode, ConsecutiveSection, GroupedDeclaration, SqlDangerousStatement, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.
// SqlDangerousStatement: dieser Detektor enthaelt seine eigenen SQL-Pattern-
// Strings ('grant all' / ' to public') als Such-Needles - Self-Match, kein Bug.

const
  EMIT_SEVERITY = lsError;

class function TSqlDangerousStatementDetector.FindDangerousVerb(
  const Low: string; out Verb: string): Boolean;
const
  // Bare 'delete ' (ohne FROM) bewusst NICHT in der Liste - echtes SQL-DELETE
  // hat per Syntax immer FROM; ein Match ohne FROM waere garantiert englischer
  // Text ('Delete failed', 'Cannot delete record', ...).
  // 2026-06-18 erweitert (Audit_ErrorDetectors E-Kurzliste):
  //   * 'drop table '/'drop view '/'drop index '/'drop database ' -
  //     Production-Disaster, kein WHERE moeglich. Diese Statements
  //     loeschen das Objekt komplett. Action-Verb-Match reicht; das
  //     "wo where?" ist hier "Statement existiert ueberhaupt = bug".
  //   * 'alter table ' mit ' drop column ' - destruktive Schema-Aenderung,
  //     mehrstufige Pattern-Pruefung im Fragment.
  //   * 'grant all ' mit ' to public' - Privilege-Eskalation,
  //     mehrstufige Pruefung im Fragment.
  VERBS : array[0..6] of string = (
    '''update ', '''delete from ', '''truncate ',
    '''drop table ', '''drop view ', '''drop index ', '''drop database '
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
  if Pos(':=', Merged) > 0 then Exit(False);

  Result := False;
  Verb   := '';

  // ALTER TABLE ... DROP COLUMN (destruktive Schema-Aenderung). Liegt
  // ausserhalb der einfachen Verb-Schleife weil zwei Tokens validiert
  // werden muessen (alter + drop column).
  if (Pos('''alter table ', Merged) > 0) and
     (Pos(' drop column ', Merged) > 0) and
     (Pos(' if exists',   Merged) = 0) then
  begin
    Verb := 'ALTER TABLE DROP COLUMN';
    Exit(True);
  end;

  // GRANT ALL ... TO PUBLIC (Privilege-Eskalation). PUBLIC = jeder
  // angemeldete User, ALL = alle Berechtigungen. Real-Word-Sicherheitsbug.
  if (Pos('''grant all', Merged) > 0) and
     (Pos(' to public', Merged) > 0) then
  begin
    Verb := 'GRANT ALL TO PUBLIC';
    Exit(True);
  end;

  for V in VERBS do
  begin
    P := Pos(V, Merged);
    if P <= 0 then Continue;
    EndPos := Pos(''';', Merged, P + Length(V));
    if EndPos <= 0 then EndPos := Length(Merged);
    Fragment := Copy(Merged, P, EndPos - P + 1);

    // SQL-Shape-Validierung: UPDATE braucht ' set ' im Fragment, sonst ist
    // es ein englisches Error-Message-Literal.
    if (V = '''update ') and (Pos(' set ', Fragment) = 0) then Continue;

    // DROP * mit IF EXISTS ist die "sichere" Variante - kein Hard-Error
    // wenn das Objekt nicht da ist. Wir wollen trotzdem warnen (DROP
    // bleibt destruktiv), aber im Output unterscheiden waere
    // user-freundlich. Pragma: aktuell trotzdem flaggen, IF EXISTS-
    // Hinweis-Differenzierung waere Folge-Iteration.

    // UPDATE/DELETE FROM: WHERE fehlt -> Treffer. DROP-Statements und
    // TRUNCATE: kein WHERE moeglich, immer Treffer.
    if (V = '''update ') or (V = '''delete from ') then
      if Pos(' where ', Fragment) > 0 then Continue;

    Verb := Trim(V);
    if (Length(Verb) > 0) and (Verb[1] = '''') then
      Verb := Copy(Verb, 2, MaxInt);
    Verb := UpperCase(Verb);
    Exit(True);
  end;
end;

class procedure TSqlDangerousStatementDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure Report(const Verb, Context: string; Line: Integer);
  var
    Msg : string;
  begin
    // Action-spezifische Begruendung damit die Findings konkret sind.
    // DROP/TRUNCATE/GRANT haben kein WHERE-Konzept; UPDATE/DELETE schon.
    if (Verb = 'TRUNCATE') or Verb.StartsWith('DROP ') then
      Msg := Format('Dangerous SQL: %s drops/clears the entire object. Context: %s',
        [Verb, Context])
    else if Verb = 'GRANT ALL TO PUBLIC' then
      Msg := Format('Privilege escalation: GRANT ALL TO PUBLIC opens access ' +
                    'to every authenticated user. Context: %s', [Context])
    else if Verb = 'ALTER TABLE DROP COLUMN' then
      Msg := Format('Destructive schema change: ALTER TABLE DROP COLUMN ' +
                    'loses column data permanently. Context: %s', [Context])
    else
      Msg := Format(
        'Dangerous SQL: %s without WHERE - affects ALL rows. Context: %s',
        [Verb, Context]);
    Results.Add(TLeakFinding.New(FileName, MethodNode.Name, Line,
      Msg, fkSqlDangerousStatement));
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
