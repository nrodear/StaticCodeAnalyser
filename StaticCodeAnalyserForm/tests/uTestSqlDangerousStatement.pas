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

    // --- 30%-Real-World-Audit 2026-07-31: FP-Gates ---
    // FP-Klasse 'sql-template' (HeidiSQL dbstructures* Provider-Bausteine)
    [Test] procedure SqlDanger_PlaceholderTemplateInGetter_NoFinding;
    [Test] procedure SqlDanger_PlaceholderTemplateOnSqlSink_StillReported;
    // FP-Klasse 'sql-builder-fragment' (MVCFramework CreateDeleteAllSQL)
    [Test] procedure SqlDanger_BuilderFragmentToResult_NoFinding;
    [Test] procedure SqlDanger_BuilderFragmentToSqlSink_StillReported;
    // FP-Klasse 'later-where-append' (MVCFramework CreateUpdateSQL)
    [Test] procedure SqlDanger_LaterWhereAppend_NoFinding;
    [Test] procedure SqlDanger_LaterOrderByAppend_StillReported;
    [Test] procedure SqlDanger_LaterUnrelatedStatementShortTarget_StillReported;
    // --- TP-Rueckholung 2026-07-31 (Drop-Sampling after119->after120) ---
    // Format-ausfuehrende DB-APIs: Format-String + Argumente sind EIN Aufruf,
    // der SOFORT ausfuehrt. Das Platzhalter-/Builder-Gate darf dort nicht
    // greifen. Alle drei Tests sind ohne HasExecSinkCall ROT.
    [Test] procedure SqlDanger_ExecuteFmtPlaceholderUpdate_Reported;
    [Test] procedure SqlDanger_ExecuteInlinedPlaceholderUpdate_Reported;
    [Test] procedure SqlDanger_ExecuteDirectPlaceholderDrop_Reported;
    // Gegenproben: die 20 weiterhin korrekt gedroppten Muster
    [Test] procedure SqlDanger_ExecuteFmtWithWhere_NoFinding;
    [Test] procedure SqlDanger_SqlSuffixedCalleeIsNoExecSink_NoFinding;
    [Test] procedure SqlDanger_NonExecBuilderCallInRhs_NoFinding;
    [Test] procedure SqlDanger_ExecTokenInsideLiteral_NoFinding;

    // --- Monotonie-Pins 2026-07-31 (Pre-Build-Review): KEINE Abstufung ---
    // Die zurueckgenommene Severity-Abstufung (DROP -> lsWarning,
    // Fixture-Pfad -> lsHint) darf nicht unangekuendigt zurueckkehren -
    // beide Tests werden rot, sobald sie wieder eingebaut wird.
    [Test] procedure SqlDanger_DropTable_SeverityStaysError;
    [Test] procedure SqlDanger_FixturePath_SeverityStaysError;
  end;

implementation

// noinspection-file SqlDangerousStatement
// Die Fixtures enthalten DELETE/UPDATE ohne WHERE absichtlich - genau das
// ist der Pruefgegenstand. Ohne diese Zeile meldet der Self-Scan acht
// Error-Funde im eigenen Testcode.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uParser2, uSqlDangerousStatement,
  uTestFindingHelper;

// Der zentrale Harness TFindingHelper.FindingsOf verwendet den festen
// Platzhalter-Dateinamen 'sample.pas'. Der Monotonie-Pin
// SqlDanger_FixturePath_SeverityStaysError (2026-07-31) braucht aber einen
// ECHTEN Test-Pfad, um zu belegen dass der Detektor dort NICHT abstuft,
// deshalb hier ein schlanker Direkt-Aufruf nur dieses Detektors. Der
// Detektor selbst laeuft regulaer im AST-Harness (FindingsOf) -
// s. uTestFindingHelper Z.187.
function SqlDangerFindingsFor(const ASource, AFileName: string)
  : TObjectList<TLeakFinding>;
var
  P    : TParser2;
  Root : TAstNode;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  P := TParser2.Create;
  try
    Root := P.ParseSource(ASource);
    try
      TSqlDangerousStatementDetector.AnalyzeUnit(Root, AFileName, Result);
    finally
      Root.Free;
    end;
  finally
    P.Free;
  end;
end;

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

// --- 30%-Real-World-Audit 2026-07-31: FP-Gates ---

procedure TTestSqlDangerousStatement.SqlDanger_PlaceholderTemplateInGetter_NoFinding;
// FP-Klasse 'sql-template' (HeidiSQL dbstructures.pas:213 / dbstructures.
// mssql.pas:430 / dbstructures.interbase.pas:186 / dbstructures.mysql.pas:3247):
// die Provider liefern pro Server-Dialekt SQL-BAUSTEINE mit %s an der
// Objekt-Position zurueck. Das ist kein ausfuehrbares Statement, sondern ein
// Template das der Aufrufer erst fuellt.
const SRC =
  'unit t; implementation'#13#10 +
  'function TProvider.GetSql(AId: TQueryId): string;'#13#10 +
  'begin'#13#10 +
  '  Result := ''DELETE FROM %s'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'Platzhalter-Template eines Provider-Getters ist kein ausfuehrbares Statement');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_PlaceholderTemplateOnSqlSink_StillReported;
// TP-Gegenprobe zum Template-Gate: dasselbe Literal DIREKT in eine
// Exec-Property geschrieben wird auch ausgefuehrt -> bleibt Fund. Beweist,
// dass das Gate an das Nicht-Exec-Ziel (Result/lokale Variable) gebunden ist.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DELETE FROM %s''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
    'Template direkt in SQL.Text bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_BuilderFragmentToResult_NoFinding;
// FP-Klasse 'sql-builder-fragment' (delphimvcframework
// MVCFramework.ActiveRecord.pas:5228 CreateDeleteAllSQL): das Statement wird
// an Result zusammengesetzt und vom Aufrufer (CreateDeleteSQL) um
// ' WHERE PK=:PK' ergaenzt. Kein Exec-Sink im Rumpf -> kein Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'function TGen.CreateDeleteAllSQL(const TableName: string): string;'#13#10 +
  'begin'#13#10 +
  '  Result := ''DELETE FROM '' + GetTableNameForSQL(TableName);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'Builder-Fragment an Result ohne Exec-Sink ist kein unfiltered DELETE');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_BuilderFragmentToSqlSink_StillReported;
// TP-Gegenprobe zum Builder-Gate: dieselbe Konkatenation direkt in SQL.Text
// wird ausgefuehrt und loescht die ganze Tabelle -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const TableName: string);'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''DELETE FROM '' + TableName;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
    'DELETE-Konkat direkt in SQL.Text bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_LaterWhereAppend_NoFinding;
// FP-Klasse 'later-where-append' (delphimvcframework
// MVCFramework.ActiveRecord.pas:5278 CreateUpdateSQL): das UPDATE-Praefix
// wird gesetzt, 23 Zeilen spaeter haengt DIESELBE Funktion ' where PK=:PK'
// an dasselbe Ziel an. Das Mutationsfenster des Literal-Scans war zu kurz.
// Bewusst mit Exec-Ziel (SQL.Text), damit das Builder-Gate NICHT greift und
// wirklich die Anhaengungs-Erkennung getestet wird.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE customers SET locked=1 '';'#13#10 +
  '  q.SQL.Text := q.SQL.Text + '' WHERE id=5'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'die WHERE-Klausel wird im selben Rumpf angehaengt -> kein unfiltered UPDATE');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_LaterOrderByAppend_StillReported;
// TP-Gegenprobe: es wird zwar spaeter an dasselbe Ziel angehaengt, aber OHNE
// WHERE-Klausel - das UPDATE trifft weiterhin alle Zeilen -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  q.SQL.Text := ''UPDATE customers SET locked=1 '';'#13#10 +
  '  q.SQL.Text := q.SQL.Text + '' ORDER BY id'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
    'Anhaengung ohne WHERE darf den unfiltered-UPDATE-Fund nicht verschlucken');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_LaterUnrelatedStatementShortTarget_StillReported;
// Regression zum Pre-Build-Review-Fund 'HasLaterWhereAppend prueft die
// Akkumulation per Substring' (2026-07-31): Zielname 's', und die zweite
// Zuweisung ist ein VOELLIG ANDERES Statement, das das Ziel rechts gar
// nicht verwendet. Mit der alten Pos()-Pruefung genuegte das 's' aus
// 'select' als Akkumulations-Nachweis, danach traf ' where' und der echte
// DELETE-ohne-WHERE-Fund der ersten Zeile verschwand. Mit der
// wortgebundenen Pruefung bleibt er erhalten.
// Ohne den Fix ist dieser Test ROT.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; q: TFDQuery;'#13#10 +
  'begin'#13#10 +
  '  s := ''DELETE FROM orders'';'#13#10 +
  '  q.SQL.Text := s;'#13#10 +
  '  s := ''SELECT * FROM orders where id=1'';'#13#10 +
  '  q.SQL.Text := s;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'ein unabhaengiges spaeteres Statement ist keine WHERE-Anhaengung - ' +
    'der DELETE-ohne-WHERE-Fund muss bleiben');
  finally F.Free; end;
end;

// --- TP-Rueckholung 2026-07-31 (Drop-Sampling after119->after120) ---

procedure TTestSqlDangerousStatement.SqlDanger_ExecuteFmtPlaceholderUpdate_Reported;
// TP-Verlust 1 (mORMot2-2.4-stable/src/orm/mormot.orm.sqlite3.pas:2269,
// TRestOrmServerDB.UpdateField): 'UPDATE % SET %=%' geht als Format-String an
// ExecuteFmt - der Quellkommentar sagt selbst "update ALL with no inline".
// Das Statement wird SOFORT ausgefuehrt und trifft jede Zeile der Tabelle.
// Das Zuweisungsziel ist 'result' und traegt kein Sink-Token, die Ausfuehrung
// liegt im RHS -> nur HasExecSinkCall sieht sie.
// Ohne den Fix ist dieser Test ROT (IsPlaceholderObject unterdrueckt).
const SRC =
  'unit t; implementation'#13#10 +
  'function TRestOrmServerDB.UpdateField(const SetFieldName, SetValue: string): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := ExecuteFmt(''UPDATE % SET %=%'', [SqlTableName, SetFieldName, SetValue]);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
      'ExecuteFmt fuehrt den Format-String sofort aus - ' +
      'ein UPDATE ohne WHERE bleibt hier ein Production-Disaster');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'UPDATE % SET %=%'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der ExecuteFmt-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_ExecuteInlinedPlaceholderUpdate_Reported;
// TP-Verlust 2 (mORMot2-2.4-stable/src/orm/mormot.orm.sql.pas:1601,
// TRestStorageExternal.EngineUpdateField, Zweig WhereFieldName = ''): genau
// der Zweig OHNE WHERE-Feld setzt das Feld in ALLEN Zeilen. Der Callee heisst
// ExecuteInlined (nicht ExecuteFmt) - das Needle muss die ganze Exec-Familie
// abdecken, nicht nur einen Namen.
// Ohne den Fix ist dieser Test ROT.
const SRC =
  'unit t; implementation'#13#10 +
  'function TRestStorageExternal.EngineUpdateField(const SetFieldName, SetValue: string): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := ExecuteInlined(''update % set %=:(%):'', [FTableName, SetFieldName, SetValue], False) <> nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
      'ExecuteInlined ohne WHERE-Feld aktualisiert alle Zeilen -> Fund');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'update % set %=:(%):'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der ExecuteInlined-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_ExecuteDirectPlaceholderDrop_Reported;
// TP-Verlust 3 (mORMot2-2.4-stable/src/orm/mormot.orm.sql.pas:2448,
// TOrmVirtualTableExternal.Drop): 'drop table %' wird per ExecuteDirect
// abgesetzt - DDL, sofort, ohne IF EXISTS. Deckt zusaetzlich ab, dass die
// Rueckholung nicht UPDATE-spezifisch ist, sondern fuer die DROP-Familie
// genauso gilt.
// Ohne den Fix ist dieser Test ROT.
const SRC =
  'unit t; implementation'#13#10 +
  'function TOrmVirtualTableExternal.Drop: Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := ExecuteDirect(''drop table %'', [FTableName], [], False) <> nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1,
      'ExecuteDirect setzt das DROP TABLE sofort ab -> Fund');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'drop table %'),
      TFindingHelper.FirstOf(F, fkSqlDangerousStatement).LineNumber,
      'Fund muss auf der ExecuteDirect-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_ExecuteFmtWithWhere_NoFinding;
// Ober-Grenze der Rueckholung: derselbe Aufruf, aber MIT WHERE-Klausel im
// Format-String - das ist die Schwester-Zeile mormot.orm.sqlite3.pas:2271
// ('update WHERE'). Die Exec-Erkennung schaltet nur die beiden
// Nicht-Exec-Gates ab, sie darf die WHERE-Pruefung NICHT aushebeln, sonst
// wuerde jeder ExecuteFmt-Aufruf zum Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'function TRestOrmServerDB.UpdateField(const SetFieldName, SetValue: string): Boolean;'#13#10 +
  'begin'#13#10 +
  '  Result := ExecuteFmt(''UPDATE % SET %=:(%): WHERE %=:(%):'', [SqlTableName, SetFieldName, SetValue]);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'ExecuteFmt MIT WHERE ist gefiltert - die Exec-Erkennung darf die ' +
    'WHERE-Pruefung nicht aushebeln');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_SqlSuffixedCalleeIsNoExecSink_NoFinding;
// Gegenprobe zu den 20 weiterhin korrekt gedroppten Mustern, scharfe Kante
// (delphimvcframework MVCFramework.ActiveRecord.pas:5228/5278/5330): der
// RHS-Callee heisst GetTableNameForSQL - er ENTHAELT 'sql', fuehrt aber
// nichts aus. Haette man fuer den RHS die Substring-Liste von
// IsExecSinkTarget wiederverwendet, kaeme dieses Builder-Fragment sofort
// wieder hoch. Das Exec-Needle ist deshalb 'exec', nicht 'sql'.
const SRC =
  'unit t; implementation'#13#10 +
  'function TGen.CreateDeleteAllSQL(const TableName: string): string;'#13#10 +
  'begin'#13#10 +
  '  Result := Format(''DELETE FROM %s'', [GetTableNameForSQL(TableName)]);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'Format()/GetTableNameForSQL() fuehren nichts aus - das Template bleibt ' +
    'ein Baustein und bleibt unterdrueckt');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_NonExecBuilderCallInRhs_NoFinding;
// Gegenprobe (HeidiSQL exportgrid.pas:954): im RHS steht ein Aufruf
// (QuoteIdent), aber kein Exec-Aufruf - das sql-builder-fragment-Gate muss
// weiter greifen. Beweist, dass die Rueckholung an den Callee-NAMEN
// gebunden ist und nicht an "im RHS steht irgendein Aufruf".
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TExporter.AddRow(const TableName: string);'#13#10 +
  'var tmp: string;'#13#10 +
  'begin'#13#10 +
  '  tmp := tmp + ''UPDATE '' + Conn.QuoteIdent(TableName) + '' SET '';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'QuoteIdent() ist kein Exec-Sink - das Builder-Fragment bleibt unterdrueckt');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_ExecTokenInsideLiteral_NoFinding;
// Gegenprobe zur Literal-Blindheit (HeidiSQL dbstructures*-Provider): das
// Exec-Needle steht NUR im SQL-Text selbst, nicht als Pascal-Aufruf. Ein
// Provider-Baustein bleibt ein Baustein, auch wenn sein Text zufaellig
// 'exec(' enthaelt.
const SRC =
  'unit t; implementation'#13#10 +
  'function TProvider.GetSql(AId: TQueryId): string;'#13#10 +
  'begin'#13#10 +
  '  Result := ''TRUNCATE %s -- exec(all)'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSqlDangerousStatement),
    'exec( im String-Literal ist kein Aufruf - Provider-Template bleibt unterdrueckt');
  finally F.Free; end;
end;

// --- Monotonie-Pins 2026-07-31 (Pre-Build-Review) ---

procedure TTestSqlDangerousStatement.SqlDanger_DropTable_SeverityStaysError;
// Pre-Build-Review-Fund 'Severity-Abstufung ADDIERT im Warning-/Note-Tier':
// die zunaechst geplante Abstufung DROP -> lsWarning wurde ersatzlos
// zurueckgenommen (Korpus-Gate dieses Inkrements erlaubt pro Regel/Tier nur
// Entfernungen). Dieser Pin wird rot, sobald sie unangekuendigt
// zurueckkehrt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DROP TABLE customers''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := TFindingHelper.FirstOf(F, fkSqlDangerousStatement);
    Assert.IsNotNull(Hit, 'DROP TABLE muss weiterhin gemeldet werden');
    Assert.AreEqual(lsError, Hit.Severity,
      'DROP bleibt vorerst im Error-Tier - ein Downgrade ist ein eigenes, ' +
      'angekuendigtes Inkrement');
  finally F.Free; end;
end;

procedure TTestSqlDangerousStatement.SqlDanger_FixturePath_SeverityStaysError;
// Gegenstueck zum Pin oben fuer die zweite zurueckgenommene Abstufung
// (Test-/Fixture-Pfad -> lsHint). Der Pfad matcht TDetectorUtils.
// IsTestFixturePath auf Stufe tplSecret (Segment 'unittests' + Basename
// '*TestsU'); trotzdem muss die Stufe unveraendert lsError sein. Der
// Direkt-Harness ist noetig, weil FindingsOf immer 'sample.pas' meldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: TFDQuery;'#13#10 +
  'begin q.SQL.Text := ''DELETE FROM customers2''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := SqlDangerFindingsFor(SRC, 'D:\repo\unittests\general\ActiveRecordTestsU.pas');
  try
    Hit := TFindingHelper.FirstOf(F, fkSqlDangerousStatement);
    Assert.IsNotNull(Hit, 'Fixture-Fund bleibt erhalten');
    Assert.AreEqual(lsError, Hit.Severity,
      'kein Pfad-abhaengiges Downgrade in diesem Inkrement');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSqlDangerousStatement);

end.
