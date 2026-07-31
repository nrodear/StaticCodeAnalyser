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
// FP-Gates (2026-07-31, 30%-Real-World-Audit sca-rw-after119, 18/18 FP):
//   * sql-template: das Literal ist ein Feature-TEMPLATE mit Platzhalter an
//     der Objekt-Position ('DELETE FROM %s' / 'TRUNCATE %s' / 'DROP DATABASE
//     %s' der HeidiSQL-Provider) - kein ausfuehrbares Statement, sondern ein
//     Baustein den der Aufrufer erst fuellt (IsPlaceholderObject).
//   * sql-builder-fragment: Zuweisung an Result/lokale Builder-Variable
//     (KEIN Exec-Sink wie SQL.Text/CommandText) mit Nicht-Literal-Konkat -
//     das Statement ist unvollstaendig, WHERE/Filter kommen vom Aufrufer
//     (MVCFramework CreateDeleteAllSQL/CreateUpdateSQL).
//   * later-where-append: im selben Rumpf wird an dasselbe Ziel spaeter eine
//     WHERE-Klausel ankonkateniert (Result := Result + ' where ...') - das
//     Mutationsfenster des Literal-Scans war zu kurz (HasLaterWhereAppend).
//
// ZUSATZHUERDE fuer die beiden Nicht-Exec-Gates (2026-07-31 Nachtrag,
// Drop-Sampling after119->after120, 3 belegte TP-VERLUSTE im Error-Tier):
// die Praemisse "Platzhalter an der Objekt-Position = Baustein" stimmt nur
// fuer Bausteine, die JEMAND ANDERS erst zusammensetzt. Bei Format-
// ausfuehrenden DB-APIs sind Format-String und Argumente EIN Aufruf, der
// das Statement SOFORT ausfuehrt:
//   mormot.orm.sqlite3.pas:2269  result := ExecuteFmt('UPDATE % SET %=%',
//                                  [props.SqlTableName, SetFieldName, SetValue])
//                                (Quellkommentar: "update ALL with no inline")
//   mormot.orm.sql.pas:1601      result := ExecuteInlined(
//                                  'update % set %=:(%):', [...], false) <> nil
//   mormot.orm.sql.pas:2448      result := ExecuteDirect('drop table %',
//                                  [fTableName], [], false) <> nil
// Das bisherige IsExecSinkTarget sieht davon nichts: es prueft nur den
// ZUWEISUNGS-ZIELNAMEN, und der ist hier 'result' - die Ausfuehrung steckt
// im RHS. HasExecSinkCall schliesst diese Luecke und prueft zusaetzlich den
// RHS-AUFRUFNAMEN (Exec/ExecSQL/Execute*/EngineExecute/...). Wenn der Aufruf
// selbst ausfuehrt, ist der Format-String kein Baustein mehr und die beiden
// Nicht-Exec-Gates (sql-template, sql-builder-fragment) bleiben AUS.
//
// ZURUECKGESTELLT (2026-07-31, Pre-Build-Review-Fund 'Severity-Abstufung
// ADDIERT im Warning-/Note-Tier'): eine Abstufung DROP -> lsWarning bzw.
// Test-/Fixture-Pfad -> lsHint war Teil dieses Inkrements und wurde
// ERSATZLOS wieder entfernt. Grund: das Korpus-Gate dieses Inkrements hat
// die harte Invariante 'pro Regel und Tier nur Entfernungen'. Eine
// Abstufung laesst SCA058 im Error-Tier verlieren und gleichzeitig im
// warning-/note-Tier GEWINNEN (SARIF-Level kommt pro Result direkt aus
// TLeakFinding.Severity) - das ist formal ein ADD und macht die Bewegungen
// nicht mehr eindeutig gegen die drei FP-Gates attribuierbar. Zweiteffekt:
// Konsumenten mit DetectorMinSeverity <> lsHint haetten die abgestuften
// Funde ganz verloren. Die Abstufung kommt als EIGENES, angekuendigtes
// Inkrement zurueck (dann mit passend gesetzter Gate-Erwartung); bis dahin
// gilt: entweder der Fall wird als FP unterdrueckt oder er bleibt exakt wie
// bisher im Error-Tier.
//
// Severity: lsError (Production-Disaster) - einheitlich, keine Abstufung.

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
    // SQL-Statement und liefert den Action-Verb-Token zurueck. AfterVerb
    // liefert den Rest des gemergten Literal-Fragments HINTER dem Verb
    // (die Objekt-Position) - Basis fuer das Template-Gate.
    class function FindDangerousVerb(const Low: string;
      out Verb, AfterVerb: string): Boolean; static;
    // Real-World-FP-Audit 2026-07-10: True wenn im literal-freien Code-Teil
    // des Fragments ein WHERE-injizierender Funktions-Aufruf per '+'-Konkat
    // angehaengt wird (CreateSQLWhereByRQL(), SqlFromWhere(),
    // GetWhereClause()). Nur fuer UPDATE/DELETE ausgewertet.
    class function HasDynamicWhereCall(const Frag: string): Boolean; static;
    // FP-Gate (2026-07-31, FP-Klasse 'sql-template'): an der Objekt-Position
    // hinter dem Verb steht ein Format-/Parameter-Platzhalter ('%s', '%d',
    // ':tbl'). Dann ist das Literal ein Baustein-Template und kein
    // ausfuehrbares Statement (HeidiSQL dbstructures* qEmptyTable /
    // qDatabaseDrop). AfterVerb ist bereits lowercased.
    class function IsPlaceholderObject(const AfterVerb: string): Boolean; static;
    // FP-Gate (2026-07-31, FP-Klasse 'sql-builder-fragment'): True wenn das
    // Zuweisungs-ZIEL eine SQL-Exec-Senke ist (SQL.Text/CommandText/lSQL/
    // Statement/Query...). Nur bei NICHT-Senken greifen die Builder-Gates -
    // ein Statement das direkt in eine Exec-Property geschrieben wird, wird
    // auch ausgefuehrt und bleibt unveraendert meldepflichtig.
    class function IsExecSinkTarget(const TargetLow: string): Boolean; static;
    // ZUSATZHUERDE zu IsExecSinkTarget (2026-07-31 Nachtrag, 3 belegte
    // TP-Verluste in mORMot2): True wenn im RHS ein AUFRUF steht, dessen
    // Callee-Name die Exec-Familie trifft (Exec/ExecSQL/Execute/ExecuteFmt/
    // ExecuteInlined/ExecuteDirect/EngineExecute/InternalExecute). Dann wird
    // das Statement SOFORT ausgefuehrt - egal wie das Zuweisungsziel heisst -
    // und ist damit kein Baustein. RhsLow muss bereits lowercased sein.
    class function HasExecSinkCall(const RhsLow: string): Boolean; static;
    // True wenn S ein '+' AUSSERHALB von Stringliteralen enthaelt, dessen
    // eine Seite KEIN Literal ist (also echte Konkatenation mit Bezeichner/
    // Aufruf). 'a'+'b' allein ist nur Multi-Line-Literal-Aufbau und zaehlt
    // NICHT. Lokale Fassung analog uSQLInjection.HasNonLiteralPlus - bewusst
    // dupliziert statt geteilt, damit dieses Gate detektor-lokal bleibt.
    class function HasNonLiteralConcat(const S: string): Boolean; static;
    // FP-Gate (2026-07-31, FP-Klasse 'later-where-append'): True wenn im
    // selben Rumpf eine spaetere Zuweisung an DASSELBE Ziel das Ziel rechts
    // wiederverwendet (Akkumulator) UND dabei eine WHERE-Klausel anhaengt.
    class function HasLaterWhereAppend(Assigns: TList<TAstNode>;
      Cur: TAstNode): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, CommentedOutCode, ConsecutiveSection, GroupedDeclaration, SqlDangerousStatement, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.
// SqlDangerousStatement: dieser Detektor enthaelt seine eigenen SQL-Pattern-
// Strings ('grant all' / ' to public') als Such-Needles - Self-Match, kein Bug.

const
  EMIT_SEVERITY = lsError;

class function TSqlDangerousStatementDetector.FindDangerousVerb(
  const Low: string; out Verb, AfterVerb: string): Boolean;
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

  Result    := False;
  Verb      := '';
  // AfterVerb bleibt fuer ALTER/GRANT leer - beide Sonder-Zweige haben keine
  // feste Objekt-Position, das Template-Gate greift dort bewusst nicht.
  AfterVerb := '';

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

    // DROP ... IF EXISTS ist deliberate idempotente DDL (Migrationen, Test-
    // Setup/Teardown, Export-Builder) - analog dem ALTER-TABLE-IF-EXISTS-Gate
    // oben (Recharakterisierung after30 2026-07-12: 5/26 SCA058-Sample-FPs).
    // Nur DROP-Verben; TRUNCATE/UPDATE/DELETE kennen kein IF EXISTS.
    if V.StartsWith('''drop ') and (Pos(' if exists', Fragment) > 0) then Continue;

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
    begin
      if Pos(' where ', Fragment) > 0 then Continue;
      // Real-World-FP-Audit 2026-07-10: dynamic-WHERE-concat FP-Klasse.
      // Das UPDATE/DELETE-Literal ist nur ein Builder-Fragment; die
      // WHERE-Klausel kommt aus einem per '+' angehaengten Funktions-
      // Aufruf (CreateSQLWhereByRQL()/SqlFromWhere()/GetWhereClause()),
      // den der Literal-Scan als ' where ' nicht sieht. Ist so ein Call
      // im Fragment praesent -> unterdruecken. Nur Aufrufe mit '(' zaehlen,
      // damit blosse Table-/Feld-Idents (FilterTable, WhereFieldName) den
      // echten unfiltered-UPDATE-Fund NICHT verschlucken (kein TP-Verlust).
      if HasDynamicWhereCall(Fragment) then Continue;
    end;

    Verb := Trim(V);
    if (Length(Verb) > 0) and (Verb[1] = '''') then
      Verb := Copy(Verb, 2, MaxInt);
    Verb := UpperCase(Verb);
    // Objekt-Position: alles im Fragment HINTER dem Verb-Token. Basis fuer
    // das Template-Gate (2026-07-31), sonst unbenutzt.
    AfterVerb := Copy(Fragment, Length(V) + 1, MaxInt);
    Exit(True);
  end;
end;

class function TSqlDangerousStatementDetector.IsPlaceholderObject(
  const AfterVerb: string): Boolean;
// FP-Gate (2026-07-31, 30%-Real-World-Audit, FP-Klasse 'sql-template').
// Mechanismus: die HeidiSQL-Provider liefern pro Server-Dialekt SQL-
// BAUSTEINE zurueck ('DELETE FROM %s' fuer das Empty-Table-Feature,
// 'DROP DATABASE %s', 'TRUNCATE %s'). Steht an der Objekt-Position ein
// Format-Platzhalter (%s/%d/%0:s) oder ein benannter Parameter (:tbl), ist
// das kein ausfuehrbares Statement - der Aufrufer setzt es erst zusammen.
// Konservativ: nur der ERSTE Token hinter dem Verb zaehlt; ein Platzhalter
// irgendwo spaeter ('DELETE FROM logs WHERE d<%s') gilt NICHT als Template.
var
  S : string;
begin
  Result := False;
  S := TrimLeft(AfterVerb);
  if S = '' then Exit;
  if S[1] = '%' then Exit(True);
  // ':tbl' - benannter Parameter an der Objekt-Position. Nur mit folgendem
  // Buchstaben, damit ein blosses ':' (z.B. Zeitangaben) nicht matcht.
  if (S[1] = ':') and (Length(S) >= 2)
     and CharInSet(S[2], ['a'..'z', 'A'..'Z', '_']) then Exit(True);
end;

class function TSqlDangerousStatementDetector.IsExecSinkTarget(
  const TargetLow: string): Boolean;
// FP-Gate (2026-07-31): Zuweisungs-Ziele, bei denen das Statement direkt in
// eine ausfuehrende DB-Komponente wandert. Bewusst als SUBSTRING-Liste (also
// eher zu VIEL Senke erkannt) - eine erkannte Senke schaltet die Builder-
// Gates AB und der Fund bleibt. Falsch-negativ waere hier das Risiko, also
// lieber grosszuegig.
const
  SINK_TOKENS : array[0..5] of string = (
    'sql', 'commandtext', 'cmdtext', 'statement', 'query', 'stmt'
  );
var
  S : string;
begin
  Result := True;
  for S in SINK_TOKENS do
    if Pos(S, TargetLow) > 0 then Exit;
  Result := False;
end;

class function TSqlDangerousStatementDetector.HasExecSinkCall(
  const RhsLow: string): Boolean;
// ZUSATZHUERDE (2026-07-31 Nachtrag zum 30%-Audit, Drop-Sampling
// after119->after120): macht die beiden Nicht-Exec-Gates ENGER. Mechanismus:
// scannt den RHS nach Bezeichnern, die als FUNKTION benutzt werden (direkt
// gefolgt von '('), und trifft der Callee-Name die Exec-Familie, fuehrt der
// RHS selbst aus. Details:
//   * String-Literale werden uebersprungen - ein SQL-Text der zufaellig
//     'exec(' enthaelt ist kein Aufruf.
//   * Gewertet wird nur das LETZTE Glied einer Punkt-Kette: bei
//     'fConn.Props.ExecuteFmt(' sind 'fconn'/'props' nicht von '(' gefolgt,
//     nur 'executefmt' ist es. Damit zaehlt der tatsaechliche Callee.
//   * Needle ist bewusst 'exec' (Teilstring des Callee) - das deckt
//     Exec/ExecSQL/Execute/ExecuteFmt/ExecuteInlined/ExecuteDirect/
//     ExecuteNoResult/EngineExecute/InternalExecute in einem ab.
//   * Bewusst NICHT die Substring-Liste von IsExecSinkTarget: deren 'sql'
//     wuerde 'GetTableNameForSQL('/'CreateDeleteAllSQL(' (MVCFramework
//     ActiveRecord 5228/5278/5330) treffen und damit korrekt unterdrueckte
//     Builder-Fragmente wieder hochspuelen.
const
  EXEC_CALLEE_NEEDLE = 'exec';
var
  i, j, n, IdentStart : Integer;
  InStr : Boolean;
  Ident : string;
begin
  Result := False;
  n      := Length(RhsLow);
  InStr  := False;
  i      := 1;
  while i <= n do
  begin
    if InStr then
    begin
      if RhsLow[i] = '''' then
      begin
        // Verdoppeltes Apostroph = Escape, im String bleiben.
        if (i < n) and (RhsLow[i + 1] = '''') then
        begin
          Inc(i, 2);
          Continue;
        end;
        InStr := False;
      end;
      Inc(i);
      Continue;
    end;
    if RhsLow[i] = '''' then
    begin
      InStr := True;
      Inc(i);
      Continue;
    end;
    if CharInSet(RhsLow[i], ['a'..'z', 'A'..'Z', '_']) then
    begin
      IdentStart := i;
      while (i <= n) and CharInSet(RhsLow[i],
              ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(i);
      Ident := Copy(RhsLow, IdentStart, i - IdentStart);
      // Whitespace zwischen Bezeichner und '(' zulassen - der Parser fuegt
      // beim RHS-Zusammenbau zwar keinen ein, Quelltext-naher Input aber schon.
      j := i;
      while (j <= n) and CharInSet(RhsLow[j], [' ', #9, #13, #10]) do Inc(j);
      if (j <= n) and (RhsLow[j] = '(')
         and (Pos(EXEC_CALLEE_NEEDLE, Ident) > 0) then Exit(True);
      Continue;   // i steht bereits hinter dem Bezeichner
    end;
    Inc(i);
  end;
end;

class function TSqlDangerousStatementDetector.HasNonLiteralConcat(
  const S: string): Boolean;
// Lokale Fassung (2026-07-31): '+' ausserhalb von Stringliteralen, bei dem
// mindestens eine Seite KEIN Apostroph ist. 'a' + 'b' ist reiner Literal-
// Aufbau (kein Builder), 'a' + Ident/Call ist ein Builder-Fragment.
var
  i, j      : Integer;
  inStr     : Boolean;
  c         : Char;
  prev, nxt : Char;
begin
  Result := False;
  inStr  := False;
  i := 1;
  while i <= Length(S) do
  begin
    c := S[i];
    if c = '''' then
    begin
      // Verdoppeltes Apostroph = Escape, im String bleiben.
      if inStr and (i < Length(S)) and (S[i + 1] = '''') then
      begin
        Inc(i, 2);
        Continue;
      end;
      inStr := not inStr;
    end
    else if (not inStr) and (c = '+') then
    begin
      prev := #0;
      for j := i - 1 downto 1 do
        if S[j] > ' ' then begin prev := S[j]; Break; end;
      nxt := #0;
      for j := i + 1 to Length(S) do
        if S[j] > ' ' then begin nxt := S[j]; Break; end;
      if (prev <> '''') or (nxt <> '''') then Exit(True);
    end;
    Inc(i);
  end;
end;

class function TSqlDangerousStatementDetector.HasLaterWhereAppend(
  Assigns: TList<TAstNode>; Cur: TAstNode): Boolean;
// FP-Gate (2026-07-31, FP-Klasse 'later-where-append'). Mechanismus:
// MVCFramework CreateUpdateSQL setzt Z.5278 'UPDATE x SET ' und haengt
// Z.5301 ' where PK=:PK' an dieselbe Result-Variable an - der Literal-Scan
// sieht nur das erste Fragment. Bedingungen (alle drei noetig, damit ein
// echter unfiltered-UPDATE-Fund nicht durch irgendeine WHERE-Erwaehnung
// weiter unten verschwindet):
//   1. gleiches Zuweisungs-Ziel
//   2. die spaetere Zuweisung ist nicht VOR dem Fund (Zeile >= Fundzeile)
//   3. sie verwendet das Ziel rechts (Akkumulator) UND haengt eine
//      WHERE-Klausel an (Literal ' where' bzw. WHERE-injizierender Call)
var
  TargetLow : string;
  M         : TAstNode;
  RhsLow    : string;
begin
  Result := False;
  if (Assigns = nil) or (Cur = nil) then Exit;
  TargetLow := Trim(Cur.Name).ToLower;
  if TargetLow = '' then Exit;
  for M in Assigns do
  begin
    if M = Cur then Continue;
    if M.Line < Cur.Line then Continue;
    if Trim(M.Name).ToLower <> TargetLow then Continue;
    RhsLow := LowerCase(M.TypeRef);
    // Akkumulations-Nachweis WORTGEBUNDEN (2026-07-31, Pre-Build-Review-Fund
    // 'HasLaterWhereAppend prueft die Akkumulation per Substring'): mit dem
    // frueheren Pos() genuegte bei kurzen Zielnamen jedes zufaellige
    // Vorkommen im spaeteren RHS - 's := ''DELETE FROM orders''' wurde durch
    // ein voellig anderes 's := ''SELECT ... where id=1''' stillgelegt (das
    // 's' aus 'select'). Ebenso 'lsql' als Praefix von 'lsqlsuffix'.
    // ContainsWholeWordLower verlangt Nicht-Ident-Zeichen links und rechts
    // und ist damit strikt enger als Pos - das Gate kann dadurch nur
    // WENIGER unterdruecken (Monotonie gewahrt).
    if not TDetectorUtils.ContainsWholeWordLower(TargetLow, RhsLow) then
      Continue;  // keine Akkumulation
    if (Pos(' where', RhsLow) > 0) or (Pos('''where', RhsLow) > 0)
       or HasDynamicWhereCall(RhsLow) then
      Exit(True);
  end;
end;

class function TSqlDangerousStatementDetector.HasDynamicWhereCall(
  const Frag: string): Boolean;
// Real-World-FP-Audit 2026-07-10: siehe Deklarations-Kommentar. Frag ist
// bereits lowercased. Ablauf: (1) String-Literal-Inhalt entfernen -> nur
// Code-Tokens (Ident/Call/Operator) bleiben; (2) jedes WHERE-Needle suchen
// und nur werten, wenn der umgebende Bezeichner als Funktions-Aufruf '('
// benutzt wird. Nicht-aufloesbar/kein Call -> weiter melden (kein FN).
const
  NEEDLES : array[0..3] of string = ('where', 'filter', 'rql', 'clause');
var
  Sb          : TStringBuilder;
  i, n, p, q  : Integer;
  InStr       : Boolean;
  Code, Nd    : string;
begin
  Result := False;
  Sb := TStringBuilder.Create;
  try
    n := Length(Frag);
    InStr := False;
    i := 1;
    while i <= n do
    begin
      if InStr then
      begin
        if Frag[i] = '''' then
        begin
          // Verdoppeltes Apostroph = Escape, im String bleiben.
          if (i < n) and (Frag[i + 1] = '''') then begin Inc(i, 2); Continue; end;
          InStr := False;
        end;
        Inc(i);
        Continue;
      end;
      if Frag[i] = '''' then begin InStr := True; Inc(i); Continue; end;
      Sb.Append(Frag[i]);
      Inc(i);
    end;
    Code := Sb.ToString;
  finally
    Sb.Free;
  end;

  n := Length(Code);
  for Nd in NEEDLES do
  begin
    p := Pos(Nd, Code);
    while p > 0 do
    begin
      // Rest des umgebenden Bezeichners ueberspringen ...
      q := p + Length(Nd);
      while (q <= n) and CharInSet(Code[q],
              ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(q);
      // ... dann Whitespace bis zum naechsten signifikanten Zeichen.
      while (q <= n) and CharInSet(Code[q], [' ', #9, #13, #10]) do Inc(q);
      if (q <= n) and (Code[q] = '(') then Exit(True);
      p := Pos(Nd, Code, p + Length(Nd));
    end;
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

    // KEINE Severity-Abstufung (2026-07-31, Pre-Build-Review-Fund
    // 'Severity-Abstufung ADDIERT im Warning-/Note-Tier'): die Stufe kommt
    // wie bisher aus dem Regelkatalog (TLeakFinding.New -> SetKind), damit
    // dieses Inkrement pro Regel/Tier ausschliesslich ENTFERNT. Ein
    // Downgrade der DROP-Familie bzw. der Fixture-Pfade folgt als eigenes,
    // angekuendigtes Inkrement - Begruendung im Unit-Kopf.
    Results.Add(TLeakFinding.New(FileName, MethodNode.Name, Line,
      Msg, fkSqlDangerousStatement));
  end;

var
  Assigns, Calls : TList<TAstNode>;
  N : TAstNode;
  Low, Verb, AfterVerb : string;
begin
  // nkAssign: SQL.Text := 'UPDATE customers SET locked=1';
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for N in Assigns do
    begin
      Low := LowerCase(N.TypeRef);
      if not FindDangerousVerb(Low, Verb, AfterVerb) then Continue;

      // FP-Gates (2026-07-31) nur fuer NICHT-Exec-Faelle: eine Zuweisung an
      // SQL.Text/CommandText wird ausgefuehrt, ein Result-/Builder-String
      // erst vom Aufrufer vervollstaendigt.
      // ZUSATZHUERDE (2026-07-31 Nachtrag): "Exec-Fall" ist nicht nur das
      // ZIEL, sondern auch der RHS-AUFRUF. 'result := ExecuteFmt(...)' traegt
      // am Ziel 'result' kein Sink-Token, fuehrt aber sofort aus (mORMot2
      // ExecuteFmt/ExecuteInlined/ExecuteDirect). Beide Nicht-Exec-Gates
      // bleiben dann aus.
      if (not IsExecSinkTarget(LowerCase(N.Name))) and
         (not HasExecSinkCall(Low)) then
      begin
        // sql-template: 'DELETE FROM %s' & Co. (HeidiSQL-Provider).
        if IsPlaceholderObject(AfterVerb) then Continue;
        // sql-builder-fragment: Statement wird aus Nicht-Literalen
        // zusammengesetzt (MVCFramework CreateDeleteAllSQL/CreateUpdateSQL).
        if HasNonLiteralConcat(N.TypeRef) then Continue;
      end;

      // later-where-append: die WHERE-Klausel folgt weiter unten im Rumpf.
      if HasLaterWhereAppend(Assigns, N) then Continue;

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
      if FindDangerousVerb(Low, Verb, AfterVerb) then
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
