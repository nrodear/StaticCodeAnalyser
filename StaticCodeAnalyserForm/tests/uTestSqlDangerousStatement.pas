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
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1);
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSqlDangerousStatement));
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
      Assert.AreEqual(0, TFindingHelper.Count(Finds, fkSqlDangerousStatement),
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
      Assert.AreEqual(0, TFindingHelper.Count(Finds, fkSqlDangerousStatement),
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkSqlDangerousStatement) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSqlDangerousStatement);

end.
