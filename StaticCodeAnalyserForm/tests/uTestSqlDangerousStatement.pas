unit uTestSqlDangerousStatement;

// Tests fuer TSqlDangerousStatementDetector (UPDATE/DELETE/TRUNCATE ohne WHERE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSqlDangerousStatement = class
  public
    // ---- Positive ---------------------------------------------------------
    [Test] procedure SqlDanger_UpdateWithoutWhere_Reported;
    [Test] procedure SqlDanger_DeleteFromWithoutWhere_Reported;
    [Test] procedure SqlDanger_TruncateTable_Reported;
    [Test] procedure SqlDanger_InCall_ExecSQL_Reported;

    // ---- Negative ---------------------------------------------------------
    [Test] procedure SqlDanger_UpdateWithWhere_NoFinding;
    [Test] procedure SqlDanger_DeleteWithWhere_NoFinding;
    [Test] procedure SqlDanger_Select_NoFinding;
    [Test] procedure SqlDanger_CaseInsensitiveWhere_NoFinding;
    // ---- Regression: Konkatenierte String-Literale ------------------------
    [Test] procedure SqlDanger_UpdateConcatLiteralWithWhere_NoFinding;
    [Test] procedure SqlDanger_NamedParamConcatWithWhere_NoFinding;
    [Test] procedure SqlDanger_TripleConcatWithWhere_NoFinding;
    [Test] procedure SqlDanger_ConcatStillNoWhere_Reported;

    // ---- FP-Regression: englischer Meldungstext mit SQL-Verb -------------
    [Test] procedure SqlDanger_UpdateInErrorMessage_NoFinding;
    [Test] procedure SqlDanger_DeleteInErrorMessage_NoFinding;
    [Test] procedure SqlDanger_UpdateNounInMessage_NoFinding;
    // ---- NATO-Permutationen: 26 englische Meldungs-Variationen je Verb ---
    // Schiesst durch das gesamte NATO-Phonetic-Alphabet als Substantiv, um
    // sicherzustellen dass der FP-Schutz nicht nur die konkrete 'CreFoId'-
    // Formulierung abdeckt. Eine einzige fehlschlagende Permutation =
    // gemeldetes Wort + Verb in der Fehlermeldung sichtbar.
    [Test] procedure SqlDanger_UpdateNatoEnglish_NoFinding;
    [Test] procedure SqlDanger_DeleteNatoEnglish_NoFinding;
    [Test] procedure SqlDanger_NatoTableNames_StillFlagged;

    // ---- Finding-Inhalt ---------------------------------------------------
    [Test] procedure SqlDanger_Finding_KindAndSeverity;
    [Test] procedure SqlDanger_Multiple_AllReported;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure SqlDanger_UpdateDynamicWhereCall_NotReported;
    [Test] procedure SqlDanger_UpdateWhereFieldNameIdent_Reported;
    // --- Recharakterisierung after30 2026-07-12: DROP ... IF EXISTS ---
    [Test] procedure SqlDanger_DropTableIfExists_NoFinding;
    [Test] procedure SqlDanger_DropTablePlain_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSqlDangerousStatement.SqlDanger_UpdateWithoutWhere_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''UPDATE customers SET locked=1''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSqlDangerousStatement),
      'genau 1 SqlDangerous-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'UPDATE customers SET locked=1'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der SQL-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_DeleteFromWithoutWhere_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DELETE FROM orders''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSqlDangerousStatement),
      'genau 1 SqlDangerous-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'DELETE FROM orders'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der SQL-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_TruncateTable_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''TRUNCATE TABLE log''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSqlDangerousStatement),
      'genau 1 SqlDangerous-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'TRUNCATE TABLE log'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der SQL-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_InCall_ExecSQL_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.ExecSQL(''DELETE FROM cache''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSqlDangerousStatement),
      'genau 1 SqlDangerous-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'DELETE FROM cache'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der SQL-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_UpdateWithWhere_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''UPDATE customers SET locked=1 WHERE id=42''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_DeleteWithWhere_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DELETE FROM orders WHERE status=''''paid''''''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_Select_NoFinding;
// SELECT ist nie gefaehrlich (kein Write).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''SELECT * FROM customers''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_CaseInsensitiveWhere_NoFinding;
// 'where' lowercase muss genauso wie 'WHERE' erkannt werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''update customers set locked=1 where id=42''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DELETE FROM logs''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkSqlDangerousStatement then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkSqlDangerousStatement, Hit.Kind);
    Assert.AreEqual(lsError, Hit.Severity);
    Assert.Contains(LowerCase(Hit.MissingVar), 'delete');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_Multiple_AllReported;
// Drei Statements ohne WHERE in derselben Methode -> 3 Findings.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE a SET x=1'';'#13#10 +
  '  q.ExecSQL;'#13#10 +
  '  q.SQL.Text := ''DELETE FROM b'';'#13#10 +
  '  q.ExecSQL;'#13#10 +
  '  q.SQL.Text := ''TRUNCATE TABLE c'';'#13#10 +
  '  q.ExecSQL;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 3);
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_UpdateConcatLiteralWithWhere_NoFinding;
// FP-Regression aus Real-World-Code: Prepare-Call mit zwei String-Literalen
// per Pascal '+'. Erstes Literal endet mit Space + '?', zweites beginnt
// mit 'WHERE'. Vor dem Concat-Merger fiel der Detector hier durch weil
// ' where ' (Space-WHERE-Space) nicht ueber die Apostroph-Grenze hinweg
// fand.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE vgbl SET datei = ? '' +'#13#10 +
  '                ''WHERE mandantid = ? AND vorgangid = ? '';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_NamedParamConcatWithWhere_NoFinding;
// Variante mit benannten Parametern (:Name) - in mORMot / Firebird /
// FireDAC / Oracle ueblich. Selbe Konkatenations-Form wie oben.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE customers SET locked=:L '' +'#13#10 +
  '                ''WHERE id=:Id'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_TripleConcatWithWhere_NoFinding;
// 3-teilige Kette - der Merger muss bis zum letzten Glied durchgehen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE c '' + ''SET x=1 '' + ''WHERE id=?'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_UpdateInErrorMessage_NoFinding;
// FP-Regression aus Real-World-Code (RHDInternalAPI_NextGen, Debtor.Service.pas):
// Englische Error-Message beginnt mit dem Wort 'Update' aber enthaelt kein
// SQL. Detector muss erkennen dass ohne ' set ' im Fragment keine
// UPDATE-Syntax vorliegt und darf nicht feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var mErrorText: string;'#13#10 +
  'begin mErrorText := ''Update failed for CreFoId''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_DeleteInErrorMessage_NoFinding;
// FP-Schutz: 'Delete failed' / 'Could not delete' - SQL-DELETE hat per
// Syntax IMMER FROM, also darf bare 'delete ' nicht matchen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var msg: string;'#13#10 +
  'begin msg := ''Delete failed for order #5''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_UpdateNounInMessage_NoFinding;
// 'Update' als Substantiv in einem Meldungstext - kein SQL.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var msg: string;'#13#10 +
  'begin msg := ''Update notification for user #42''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
  finally F.Free; end;
end;

// NATO-Phonetic-Alphabet als Test-Daten-Permutation. Wird von drei Tests
// genutzt: zwei negative (englische Meldungen), eine positive (echte SQL
// mit NATO-Worten als Tabellennamen).
const
  NATO_WORDS : array[0..25] of string = (
    'Alfa',    'Bravo',   'Charlie', 'Delta',   'Echo',
    'Foxtrot', 'Golf',    'Hotel',   'India',   'Juliet',
    'Kilo',    'Lima',    'Mike',    'November','Oscar',
    'Papa',    'Quebec',  'Romeo',   'Sierra',  'Tango',
    'Uniform', 'Victor',  'Whiskey', 'Xray',    'Yankee',
    'Zulu'
  );

procedure TTestSqlDangerousStatement.SqlDanger_UpdateNatoEnglish_NoFinding;
// 26 Permutationen: 'Update <Nato> failed for record'. Keine darf
// als SQL-Bug gemeldet werden. Failure-Message nennt das verantwortliche
// NATO-Wort damit Regressionen sofort lokalisierbar sind.
var
  Word    : string;
  Source  : string;
  Finds   : TObjectList<TLeakFinding>;
begin
  for Word in NATO_WORDS do
  begin
    Source :=
      'unit t; implementation'#13#10 +
      'procedure Foo;'#13#10 +
      'var msg: string;'#13#10 +
      'begin msg := ''Update ' + Word + ' failed for record''; end;';
    Finds := TFindingHelper.FindingsOf(Source);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(Finds, fkSqlDangerousStatement),
        Format('FP fuer NATO-Wort "%s" - "Update %s failed for record" ist kein SQL',
          [Word, Word]));
    finally
      Finds.Free;
    end;
  end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_DeleteNatoEnglish_NoFinding;
// Analog zu Update-Variante: 'Delete <Nato> not authorized'. Da der
// Detector bare 'delete ' (ohne FROM) gar nicht mehr matcht, muessen
// alle 26 Permutationen leise durchlaufen.
var
  Word    : string;
  Source  : string;
  Finds   : TObjectList<TLeakFinding>;
begin
  for Word in NATO_WORDS do
  begin
    Source :=
      'unit t; implementation'#13#10 +
      'procedure Foo;'#13#10 +
      'var msg: string;'#13#10 +
      'begin msg := ''Delete ' + Word + ' not authorized''; end;';
    Finds := TFindingHelper.FindingsOf(Source);
    try
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(Finds, fkSqlDangerousStatement),
        Format('FP fuer NATO-Wort "%s" - "Delete %s not authorized" ist kein SQL',
          [Word, Word]));
    finally
      Finds.Free;
    end;
  end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_NatoTableNames_StillFlagged;
// Gegen-Test: ECHTE gefaehrliche SQL mit NATO-Tabellennamen. Stellt
// sicher dass der FP-Fix nicht versehentlich das halbe Vokabular
// suppressed - jedes NATO-Wort muss als Tabellenname weiterhin einen
// Bug ausloesen, sobald die UPDATE-Syntax (SET ohne WHERE) erfuellt ist.
var
  Word    : string;
  Source  : string;
  Finds   : TObjectList<TLeakFinding>;
begin
  for Word in NATO_WORDS do
  begin
    Source :=
      'unit t; implementation'#13#10 +
      'procedure Foo;'#13#10 +
      'var q: TFDQuery;'#13#10 +
      'begin q.SQL.Text := ''UPDATE ' + Word + ' SET status=1''; end;';
    Finds := TFindingHelper.FindingsOf(Source);
    try
      Assert.IsTrue(TFindingHelper.Count(Finds, fkSqlDangerousStatement) >= 1,
        Format('Tabellenname "%s" - echte gefaehrliche UPDATE-SQL wurde nicht erkannt',
          [Word]));
    finally
      Finds.Free;
    end;
  end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_ConcatStillNoWhere_Reported;
// Gegenteilige Richtung: Konkatenation, aber das gemergte SQL hat
// TROTZDEM kein WHERE - muss weiterhin als Bug erkannt werden. Der
// Merger soll nicht versehentlich echte Bugs verstecken.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE customers '' + ''SET locked=1'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSqlDangerousStatement),
      'genau 1 SqlDangerous-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'UPDATE customers '' + ''SET locked=1'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der SQL-Zeile liegen');
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestSqlDangerousStatement.SqlDanger_UpdateDynamicWhereCall_NotReported;
// FP-Regression Real-World-FP-Audit 2026-07-10 (delphimvcframework,
// MVCFramework.ActiveRecord.pas ~Z.3310): das UPDATE-Literal ist nur ein
// Builder-Fragment; die WHERE-Klausel wird per '+' aus dem Funktions-Aufruf
// CreateSQLWhereByRQL() angehaengt (liefert laut Code-Kommentar ' WHERE ...').
// Der Literal-Scan sieht kein ' where ', aber HasDynamicWhereCall erkennt den
// WHERE-injizierenden Call ('...where...(') im literal-freien Code-Teil und
// unterdrueckt den Fund. -> kein Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var lSQL, lTable: string;'#13#10 +
  'begin'#13#10 +
  '  lSQL := ''UPDATE '' + lTable + '' SET locked=1 '' + CreateSQLWhereByRQL(lTable);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'dynamic-WHERE-concat: CreateSQLWhereByRQL() haengt die WHERE-Klausel an - kein unfiltered UPDATE');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_UpdateWhereFieldNameIdent_Reported;
// TP-Guard-Grenze zum dynamic-WHERE-Fix (kein TP-Verlust): das per '+'
// angehaengte Glied ist ein BLOSSER Bezeichner (WhereFieldName), KEIN Call mit
// '(' - injiziert also keine WHERE-Klausel. HasDynamicWhereCall wertet nur
// where/filter/rql/clause-Idents, die als Funktion '(' aufgerufen werden;
// ein blosser Feld-/Table-Ident darf den echten unfiltered-UPDATE-Fund NICHT
// verschlucken (vgl. mormot.orm.sql WhereFieldName='' Branch). -> muss feuern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var lSQL, lTable, WhereFieldName: string;'#13#10 +
  'begin'#13#10 +
  '  lSQL := ''UPDATE '' + lTable + '' SET locked=1 '' + WhereFieldName;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
    'unfiltered UPDATE mit blossem WhereFieldName-Ident (kein Call) muss weiter als Bug feuern');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_DropTableIfExists_NoFinding;
// Recharakterisierung after30: DROP TABLE IF EXISTS ist deliberate idempotente
// DDL (Migration/Test-Cleanup) - analog dem bestehenden ALTER-IF-EXISTS-Gate.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DROP TABLE IF EXISTS temp_import''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'DROP TABLE IF EXISTS ist deliberate idempotente DDL -> kein SCA058-Fund');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_DropTablePlain_StillReported;
// TP-Gegenprobe: ein DROP TABLE OHNE IF EXISTS bleibt destruktiv -> Fund. Beweist,
// dass das Gate IF-EXISTS-spezifisch ist und nicht alle DROPs unterdrueckt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DROP TABLE customers''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
    'DROP TABLE ohne IF EXISTS bleibt destruktiv -> SCA058-Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSqlDangerousStatement);

end.
