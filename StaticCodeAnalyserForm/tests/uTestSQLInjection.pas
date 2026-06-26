unit uTestSQLInjection;

// Tests fuer den TSQLInjectionDetector (Basis und Erweiterungen).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- SQLInjection (TSQLInjectionDetector) ------------------------------------------
  [TestFixture]
  TTestSQLInjection = class
  public
    [Test] procedure SQL_AssignToSQLText_WithConcat_ReportsError;
    [Test] procedure SQL_AssignToCommandText_WithConcat_ReportsError;
    [Test] procedure SQL_StringLiteralContainsSELECT_WithConcat_ReportsError;
    [Test] procedure SQL_NoConcat_NoFinding;
    [Test] procedure SQL_AddCall_WithConcat_ReportsError;
    [Test] procedure SQL_ParametrizedQuery_NoFinding;
    [Test] procedure SQL_DocStringWithSQLKeyword_NoFinding;
    [Test] procedure SQL_LiteralOnlyConcat_NoFinding;
    [Test] procedure SQL_CreateTableMultilineLiteral_NoFinding;
    // Wortgrenze: 'commandtext' darf nicht 'mycommandtextra' matchen
    [Test] procedure SQL_CommandTextSubstring_NoFalsePositive;
  end;

  // ---- SQLInjection Erweiterungen ----------------------------------------------------
  [TestFixture]
  TTestSQLInjectionExt = class
  public
    [Test] procedure SQL_AssignSelectStarConcat_IntToStrSafe_NoFinding;
    [Test] procedure SQL_SchemaSanitizerHelper_NoFinding;
    [Test] procedure SQL_DeleteWithVarConcat_ReportsError;
    [Test] procedure SQL_AssignWithoutSQLKeyword_NoFinding;
    // ---- Severity / Finding-Inhalt / Multi-Hit ------------------------------
    [Test] procedure SQL_Finding_KindAndSeverity;
    [Test] procedure SQL_Finding_MissingVarMentionsTargetAndFixScore;
    [Test] procedure SQL_MultipleHitsInSameMethod_AllReported;
    // ---- Format-Family (mORMot-Pattern) -------------------------------------
    [Test] procedure SQL_FormatUtf8_WithSqlKeyword_Reported;
    [Test] procedure SQL_ExecuteFmt_TablenamePlaceholder_Reported;
    [Test] procedure SQL_FormatWithoutSql_NoFinding;
    // ---- Nicht-SQL-Senken (Real-World 2026-06-26 FP-Klasse) -----------------
    // Log-/UI-Aufrufe tragen oft Prosa die mit SQL-Verben ('Update '/'Create '/
    // 'Exec ') beginnt -> duerfen NICHT als SQL-Concat flaggen.
    [Test] procedure SQL_LogMsgWithSqlVerb_NoFinding;
    [Test] procedure SQL_ShowMessageFormatWithSqlVerb_NoFinding;
    [Test] procedure SQL_StatusBarPanelCaption_NoFinding;
    // Gegenkontrolle: SQL-Builder OHNE bekannte Exec-Methode (Alcinoe
    // SelectData) muss ueber den Keyword-Zweig weiterhin feuern.
    [Test] procedure SQL_NonExecMethodSelectConcat_Reported;
  end;

implementation

{ ---- SQLInjection ---- }

procedure TTestSQLInjection.SQL_AssignToSQLText_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Search(Id: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM users WHERE id = ''+Id;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'SQL.Text mit Konkatenation – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_AssignToCommandText_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Tbl: string);'#13#10+
  'begin'#13#10+
  '  Cmd.CommandText := ''UPDATE ''+Tbl+'' SET active=1'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection), 'CommandText – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_StringLiteralContainsSELECT_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Name: string);'#13#10+
  'begin'#13#10+
  '  s := ''SELECT * FROM t WHERE name = ''+Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'SELECT-Literal mit Konkatenation – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_NoConcat_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run;'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM users WHERE id = :Id'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'Parametrisiertes Query ohne + – kein Befund');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_AddCall_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Id: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Add(''SELECT * FROM t WHERE id = ''+Id);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'SQL.Add mit Konkatenation – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_ParametrizedQuery_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Name: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM t WHERE name = :Name'';'#13#10+
  '  Query.ParamByName(''Name'').AsString := Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'Parametrisiertes Query – kein Befund');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_DocStringWithSQLKeyword_NoFinding;
// Reproduziert den FixHint-Falschpositiv: ein Feld wie Result.Before erhält
// einen Dokumentations-String, der SQL-Keywords NICHT an Position 1 hat.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.BuildHint;'#13#10+
  'begin'#13#10+
  '  Result.Before :='#13#10+
  '    ''Query.SQL.Text :=''+'#13#10+
  '    ''  ''''SELECT * FROM t'''';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'Doku-String mit SQL-Keyword – kein Befund (H2 nur bei Position 1)');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_LiteralOnlyConcat_NoFinding;
// Zwei oder mehr Stringliterale per '+' verkettet sind reine Multi-Line-
// Literale, kein SQL-Injection-Risiko - es gibt keine Variable die ein
// Angreifer manipulieren koennte.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT a FROM t'' + '' WHERE x=1'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'Pure Literal-Konkatenation darf kein SQL-Injection-Befund sein');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_CreateTableMultilineLiteral_NoFinding;
// Konkretes Beispiel aus Unit1.pas (sample-dunitx-belege_ui):
// CREATE TABLE - mehrzeilige Stringliteral-Konkatenation, KEIN Risiko.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.CreateTable;'#13#10+
  'begin'#13#10+
  '  SQLQuery.SQL.Text := ''CREATE TABLE IF NOT EXISTS Kommentare '' +'#13#10+
  '    ''(id TEXT PRIMARY KEY NOT NULL, Teaser TEXT, Info TEXT)'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'Mehrzeiliges CREATE TABLE-Literal darf kein SQL-Injection-Befund sein');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_CommandTextSubstring_NoFalsePositive;
// Wortgrenze-Test: 'mycommandtextra' enthaelt 'commandtext' als Substring,
// darf aber NICHT als SQL-Property erkannt werden. Vor dem WholeWord-Fix
// in IsAssignRisk haette die naive Pos()-Suche hier einen Treffer geliefert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var dummy: string;'#13#10+
  'begin'#13#10+
  '  mycommandtextra := dummy + ''abc'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      '"mycommandtextra" darf nicht als SQL-Property-Match gelten');
  finally F.Free; end;
end;

// =============================================================================
// SQLInjection-Erweiterungen
// =============================================================================

procedure TTestSQLInjectionExt.SQL_AssignSelectStarConcat_IntToStrSafe_NoFinding;
// 'WHERE id = ' + IntToStr(Id) ist tatsaechlich injection-sicher -
// IntToStr akzeptiert nur Integer, der Output ist garantiert numerisch.
// Recent fix `AllConcatTermsSafe` whitelistet IntToStr/Int64ToStr/
// FormatInt/QuotedStr/QuotedSQL etc. - alle Konkat-Terme sind entweder
// String-Literale ODER safe-cast-Calls -> kein Risiko.
//
// Wer trotzdem warnen will: bare Variable statt IntToStr verwenden.
// Siehe SQL_DeleteWithVarConcat fuer das korrekte Risiko-Pattern.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Id: Integer);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM users WHERE id = '' + IntToStr(Id);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'IntToStr-Konkat ist safe-cast-whitelisted');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_SchemaSanitizerHelper_NoFinding;
// Regression DMVCFramework SQLGenerators - SQL-Builder mit Schema-
// Sanitizer-Helpern (GetTableNameForSQL, GetFieldNameForSQL) und
// Quote*-Eskaper sind injection-sicher. Detector erkennt diese
// Prefix-Pattern jetzt als safe-cast (analog IntToStr-Whitelist).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var lSB: TStringBuilder;'#13#10+
  'begin'#13#10+
  '  lSB.Append(''INSERT INTO '' + GetTableNameForSQL(TableMap.fTableName) + '' ('');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
      'GetTableNameForSQL ist Schema-Sanitizer (Get*ForSQL-Konvention)');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_DeleteWithVarConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Name: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''DELETE FROM t WHERE name = '' + Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1);
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_AssignWithoutSQLKeyword_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''hello '' + ''world'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection));
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var q: TFDQuery; UserId: string;'#13#10+
  'begin q.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkSQLInjection then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkSQLInjection finding expected');
    Assert.AreEqual(fkSQLInjection, Hit.Kind);
    Assert.AreEqual(lsError, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_Finding_MissingVarMentionsTargetAndFixScore;
// MissingVar enthaelt: LHS-Target + FormatShort-Estimate (Score X/5 ...).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var q: TFDQuery; UserId: string;'#13#10+
  'begin q.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkSQLInjection then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    // Target + Fix-Score-Hinweis
    Assert.Contains(LowerCase(Hit.MissingVar), 'sql');
    Assert.Contains(Hit.MissingVar, '/5');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_FormatUtf8_WithSqlKeyword_Reported;
// mORMot-Idiom: FormatUtf8('SELECT * FROM % WHERE id=%', [tbl, id])
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string; tbl, id: string;'#13#10+
  'begin s := FormatUtf8(''SELECT * FROM % WHERE id=%'', [tbl, id]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1);
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_ExecuteFmt_TablenamePlaceholder_Reported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var DB: TRestServerDB; tbl: string;'#13#10+
  'begin DB.ExecuteFmt(''DROP TABLE %'', [tbl]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1);
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_FormatWithoutSql_NoFinding;
// Format ohne SQL-Keyword - kein Risiko
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string; n: Integer;'#13#10+
  'begin s := Format(''Count: %d'', [n]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection));
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_LogMsgWithSqlVerb_NoFinding;
// Real-World FP: cnwizards CnDebugger.LogMsg('Update Feed: ' + Def.Url).
// Debug-Log, keine DB-Senke - 'Update '-Prosa darf nicht flaggen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(const Url: string);'#13#10+
  'begin'#13#10+
  '  CnDebugger.LogMsg(''Update Feed: '' + Url);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'LogMsg mit SQL-Verb-Prosa ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_ShowMessageFormatWithSqlVerb_NoFinding;
// Real-World FP: ShowMessage(Format('Create %d Success. %d Fail.', [s, f])).
// UI-Meldung via Format (H3-Pfad) - keine SQL.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(s, f: Integer);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Create %d Success. %d Fail.'', [s, f]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'ShowMessage(Format(...)) ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_StatusBarPanelCaption_NoFinding;
// Real-World FP: ALWebSpider StatusBar2.Panels[0].Text := 'Update Href...'
// + FileName. UI-Caption (H2-Pfad), keine SQL.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(const FileName: string);'#13#10+
  'begin'#13#10+
  '  StatusBar2.Panels[0].Text := ''Update Href for file: '' + FileName;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'StatusBar-Panel-Caption ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_NonExecMethodSelectConcat_Reported;
// TP-Kontrolle: Alcinoe-Style SelectData('SELECT ' + Part) - keine bekannte
// Exec-Methode, aber echter SQL-Aufbau. Der Keyword-Zweig (nicht durch das
// Sink-Gate blockiert) muss weiterhin feuern.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(const Part: string);'#13#10+
  'begin'#13#10+
  '  SelectData(''SELECT '' + Part);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1,
    'SQL-Builder ohne Exec-Methode muss ueber Keyword-Zweig feuern');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_MultipleHitsInSameMethod_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var q1, q2: TFDQuery; UserId, ProdId: string;'#13#10+
  'begin'#13#10+
  '  q1.SQL.Text := ''SELECT * FROM users WHERE id='' + UserId;'#13#10+
  '  q2.SQL.Text := ''SELECT * FROM products WHERE id='' + ProdId;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkSQLInjection));
  finally F.Free; end;
end;

end.
