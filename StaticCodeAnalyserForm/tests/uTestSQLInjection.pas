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
    // Real-World FP (BuildLogStats): Windows-Batch call "..."/msbuild ist kein SQL;
    // Gegenkontrolle: echtes SQL CALL proc bleibt erkannt.
    [Test] procedure SQL_BatchCallCommand_NoFinding;
    [Test] procedure SQL_RealSqlCallFormat_Reported;
    // ---- Nicht-SQL-Senken (Real-World 2026-06-26 FP-Klasse) -----------------
    // Log-/UI-Aufrufe tragen oft Prosa die mit SQL-Verben ('Update '/'Create '/
    // 'Exec ') beginnt -> duerfen NICHT als SQL-Concat flaggen.
    [Test] procedure SQL_LogMsgWithSqlVerb_NoFinding;
    [Test] procedure SQL_ShowMessageFormatWithSqlVerb_NoFinding;
    [Test] procedure SQL_StatusBarPanelCaption_NoFinding;
    // Gegenkontrolle: SQL-Builder OHNE bekannte Exec-Methode (Alcinoe
    // SelectData) muss ueber den Keyword-Zweig weiterhin feuern.
    [Test] procedure SQL_NonExecMethodSelectConcat_Reported;
    // ---- Verb-Prosa-Gate (Real-World 2026-06-27 FP-Klasse) ------------------
    // Englische Saetze beginnen oft mit DDL/CTE-Verben ('Create file '/'Delete
    // directory '/'with spaces'/'update one field') -> kein SQL. Echtes SQL hat
    // nach dem Verb eine rigide Fortsetzung (Objekt-KW / ' SET ' / ' AS ' /
    // Concat-Ende / %-Placeholder). FP-Faelle:
    [Test] procedure SQL_DdlVerbProseAssign_NoFinding;
    [Test] procedure SQL_WithProseInCheck_NoFinding;
    [Test] procedure SQL_UpdateProseInCheck_NoFinding;
    // ...TP-Gegenkontrollen (echtes DDL/CTE/UPDATE muss weiter feuern):
    [Test] procedure SQL_RealDdlCreateDrop_Reported;
    [Test] procedure SQL_RealCteWithAs_Reported;
    [Test] procedure SQL_RealUpdateSet_Reported;
    // String-Literal-befreiter CALL-Methoden-Match: 'open(' im DDE-Kommando
    // '[Open("%1")]' (Dev-Cpp RegisterDDEServer) ist kein Methodenaufruf.
    [Test] procedure SQL_DdeOpenInStringLiteral_NoFinding;
    // ---- Const/Literal-Dataflow-Gate (Real-World 2026-07-04, Prio 1) --------
    // FP-Klassen const-concat / const-derived-variable / int-format-concat:
    // Konkatenation bzw. Format-Substitution, die nachweislich nur aus
    // Literalen/lokalen Literal-Variablen/Integern besteht, ist kein
    // Injection-Vektor.
    [Test] procedure SQL_ExecuteFmtAllLiteralArgs_NoFinding;
    [Test] procedure SQL_ConstDerivedVariableConcat_NoFinding;
    [Test] procedure SQL_LocalConstConcat_NoFinding;
    [Test] procedure SQL_IntFormatMaskConcat_NoFinding;
    [Test] procedure SQL_ExecuteFmtIntegerArgs_NoFinding;
    // ...TP-Gegenkontrollen (String-Variablen bleiben Risiko):
    [Test] procedure SQL_ExecuteFmtStringParamArgs_Reported;
    [Test] procedure SQL_VariableFromUserInput_Reported;
    [Test] procedure SQL_FormatStringMaskConcat_Reported;
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'genau 1 SQLInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'DELETE FROM t WHERE name'),
      TFindingHelper.FirstOf(F, fkSQLInjection).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'genau 1 SQLInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FormatUtf8'),
      TFindingHelper.FirstOf(F, fkSQLInjection).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'genau 1 SQLInjection-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ExecuteFmt'),
      TFindingHelper.FirstOf(F, fkSQLInjection).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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

procedure TTestSQLInjectionExt.SQL_BatchCallCommand_NoFinding;
// Real-World FP (BuildLogStats RunMSBuild): ein Windows-Batch wird zeilenweise
// in eine TStringList gebaut + als .bat gespeichert. Format('call "%s"',[...])
// ist der Batch-call-Befehl, NICHT der SQL-Stored-Proc-CALL; die msbuild-Zeile
// hat kein SQL-Keyword. Darf NICHT als SQL-Injection flaggen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.RunMSBuild(RsVars, ATarget, AConfig, APlatform: string);'#13#10+
  'var SL: TStringList;'#13#10+
  'begin'#13#10+
  '  SL.Add(Format(''call "%s"'', [RsVars]));'#13#10+
  '  SL.Add(Format(''msbuild "%s" /t:Build /p:Config=%s /p:Platform=%s'','#13#10+
  '    [ATarget, AConfig, APlatform]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'Batch call "..."/msbuild ist kein SQL');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_RealSqlCallFormat_Reported;
// Gegenkontrolle zum 'call'-Sonder-Gate: echtes SQL  CALL <proc>  via Format
// bleibt erkannt. Das Gate schluckt nur das Shell-call "..." (folgendes "),
// nicht das von einem Prozedurnamen gefolgte SQL-CALL.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Del(UserId: string);'#13#10+
  'begin'#13#10+
  '  DB.ExecSQL(Format(''CALL sp_delete(%s)'', [UserId]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1,
    'echtes SQL CALL proc(%s) bleibt SQL-Injection-Risiko');
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

procedure TTestSQLInjectionExt.SQL_DdlVerbProseAssign_NoFinding;
// Real-World FP (jcl makedist MakeDistActions): Result := 'Create file ' + X.
// Eine Caption-/Beschreibungs-Funktion; 'Create '/'Delete ' sind hier engl.
// Verben, gefolgt von Alltagsnomen (file/directory), kein SQL-Objekt-Keyword.
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Describe: string;'#13#10+
  'begin'#13#10+
  '  Result := ''Create file '' + FName + '' and set content to '' + FBody;'#13#10+
  '  Result := ''Delete directory '' + FDir;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'DDL-Verb + Alltagsnomen ist englische Prosa, kein SQL');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_WithProseInCheck_NoFinding;
// Real-World FP (mORMot test.core.data): Check(TryUtf8ToBcd(' '+u+' ', b2),
// 'with spaces'). Die Assert-Message 'with spaces' matcht das CTE-Keyword
// 'with ', der ' '+u+' '-Concat liefert den Non-Literal-Plus. Kein CTE.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(u: string; b2: TBcd);'#13#10+
  'begin'#13#10+
  '  Check(TryUtf8ToBcd('' '' + u + '' '', b2), ''with spaces'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    '''with spaces'' ist Prosa, kein CTE (WITH .. AS)');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_UpdateProseInCheck_NoFinding;
// Real-World FP (mORMot test.orm.core): Check(UpdateField(.., [100 + 10]),
// 'update one field of a given record'). Die Message matcht 'update ', der
// [100 + 10]-Concat liefert den Non-Literal-Plus. Kein UPDATE .. SET.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(rec: TObject);'#13#10+
  'begin'#13#10+
  '  Check(DoUpdateField(rec, 100, ''ValWord'', [100 + 10]),'#13#10+
  '    ''update one field of a given record'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    '''update one field...'' ist Prosa, kein UPDATE .. SET');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_RealDdlCreateDrop_Reported;
// TP-Kontrolle: echtes DDL muss weiter feuern. 'CREATE TABLE '+x (Objekt-KW
// TABLE) UND 'DROP '+ObjType (Verb endet am Literal -> Concat-Risk).
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Ddl(Tbl, ObjType: string): string;'#13#10+
  'begin'#13#10+
  '  Result := ''CREATE TABLE '' + Tbl;'#13#10+
  '  Result := ''DROP '' + ObjType + '' x'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkSQLInjection),
    'echtes CREATE TABLE / DROP <obj> bleibt SQL-Injection-Risiko');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_RealCteWithAs_Reported;
// TP-Kontrolle: echte CTE  WITH c AS (SELECT ... FROM '+x+')  muss feuern.
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Cte(Tbl: string): string;'#13#10+
  'begin'#13#10+
  '  Result := ''WITH c AS (SELECT * FROM '' + Tbl + '')'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1,
    'echte CTE (WITH .. AS) bleibt SQL-Injection-Risiko');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_RealUpdateSet_Reported;
// TP-Kontrolle: echtes  UPDATE users SET name='+x  muss feuern.
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Upd(Name: string): string;'#13#10+
  'begin'#13#10+
  '  Result := ''UPDATE users SET name='' + Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1,
    'echtes UPDATE .. SET bleibt SQL-Injection-Risiko');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_DdeOpenInStringLiteral_NoFinding;
// Real-World FP (Dev-Cpp FileAssocs): RegisterDDEServer('DevCpp.'+Ext, 'open',
// '[Open("%1")]'). Das DDE-Kommando-Literal '[Open("%1")]' enthaelt 'Open(',
// das faelschlich die Exec-Methode 'open(' matchte. Match erfolgt jetzt auf
// String-Literal-befreitem Text -> 'Open(' im Literal zaehlt nicht.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Ext: string);'#13#10+
  'begin'#13#10+
  '  RegisterDDEServer(''DevCpp.'' + Ext, ''open'', ''[Open("%1")]'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    '''Open('' im DDE-Kommando-Literal ist kein Methodenaufruf');
  finally F.Free; end;
end;

// =============================================================================
// Const/Literal-Dataflow-Gate (Real-World-Audit 2026-07-04, Sektion 3.1)
// =============================================================================

procedure TTestSQLInjectionExt.SQL_ExecuteFmtAllLiteralArgs_NoFinding;
// Real-World FP (fpClass const-concat, mORMot dmvc-ai server.pas:91/95/99):
// Seed-Daten-INSERT via ExecuteFmt - ALLE Argument-Array-Elemente sind
// hartkodierte Literale ('ACME', ..., 5). Kein externer Input, keine
// Injection moeglich -> kein Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Seed;'#13#10+
  'begin'#13#10+
  '  fServer.Orm.ExecuteFmt('#13#10+
  '    ''INSERT INTO CustomerOrm (Code, CompanyName, City, Rating, Note) '' +'#13#10+
  '    ''VALUES (%, %, %, %, %)'','#13#10+
  '    [''ACME'', ''ACME Corporation'', ''New York'', 5, ''Premium customer'']);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'Seed-INSERT mit reinen Literal-Argumenten ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_ConstDerivedVariableConcat_NoFinding;
// Real-World FP (fpClass const-derived-variable, DMVC activerecord_showcase
// MainFormU.pas:3207/3237/3296): die konkatenierte Variable wird in der
// Routine AUSSCHLIESSLICH per if/else aus String-Literalen zugewiesen
// (geschlossene Wertemenge 'DATETIME2'/'TIMESTAMP') -> kein Angreifer-
// Einfluss, kein Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.SetupTable;'#13#10+
  'var lTimestampType, lDDL: string;'#13#10+
  'begin'#13#10+
  '  if GetBackend = ''mssql'' then'#13#10+
  '    lTimestampType := ''DATETIME2'''#13#10+
  '  else'#13#10+
  '    lTimestampType := ''TIMESTAMP'';'#13#10+
  '  lDDL := ''CREATE TABLE audit_demo ('' +'#13#10+
  '    ''  created_at '' + lTimestampType + '')'';'#13#10+
  '  Conn.ExecSQL(lDDL);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'Variable aus geschlossener Literalmenge ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_LocalConstConcat_NoFinding;
// fpClass const-concat, Variante lokale Konstante: Konkatenation aus
// Literal + echter const mit Literal-Wert - zur Compile-Zeit fix.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run;'#13#10+
  'const ORDER_COL = ''LastName'';'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''SELECT * FROM People ORDER BY '' + ORDER_COL;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'Konkatenation mit lokaler Literal-Konstante ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_IntFormatMaskConcat_NoFinding;
// Real-World FP (fpClass int-format-concat, DMVC outputcachewithredis
// PeopleModuleU.pas:88/116): der einzige variable Konkat-Anteil ist
// Format() mit reiner %d-Maske (Paging LIMIT/ROWS) - kann nur Ziffern
// erzeugen, kein Injection-/Syntax-Risiko.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.GetPeople(APage: Integer);'#13#10+
  'var StartRec, EndRec: Integer;'#13#10+
  'begin'#13#10+
  '  qryPeople.Open(''SELECT * FROM PEOPLE ORDER BY LAST_NAME '' +'#13#10+
  '    Format(''ROWS %d to %d'', [StartRec, EndRec]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'Format-Maske nur mit %d-Platzhaltern ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_ExecuteFmtIntegerArgs_NoFinding;
// Real-World FP (fpClass int-format-concat, mORMot dmvc-ai
// api.impl.pas:62/133/299/407): mORMot-'%'-Substitution mit
// ausschliesslich Integer-Argumenten (RowID/Rating) - Integer koennen
// keine SQL-Syntax injizieren.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Del(id: Integer);'#13#10+
  'begin'#13#10+
  '  Server.Orm.ExecuteFmt(''DELETE FROM CustomerOrm WHERE RowID=%'', [id]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSQLInjection),
    'ExecuteFmt mit reinen Integer-Argumenten ist keine SQL-Injection');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_ExecuteFmtStringParamArgs_Reported;
// TP-Gegenkontrolle (Korpus-TP mORMot dmvc-ai api.impl.pas:90/110): REST-
// exponierte String-Parameter (RawUtf8) werden per '%' roh substituiert -
// echte SQL-Injection, das Dataflow-Gate darf NICHT greifen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.CreateCustomer(const code, city: RawUtf8; rating: Integer);'#13#10+
  'begin'#13#10+
  '  Server.Orm.ExecuteFmt(''INSERT INTO CustomerOrm (Code, City, Rating) '' +'#13#10+
  '    ''VALUES (%, %, %)'', [code, city, rating]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'ExecuteFmt mit String-Parametern bleibt SQL-Injection-Risiko');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ExecuteFmt'),
      TFindingHelper.FirstOf(F, fkSQLInjection).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_VariableFromUserInput_Reported;
// TP-Gegenkontrolle zum const-derived-Gate: sobald die Variable auch nur
// EINE nicht-literale Zuweisung hat (UI-Input), bleibt der Fund stehen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run;'#13#10+
  'var lFilter: string;'#13#10+
  'begin'#13#10+
  '  lFilter := Edit1.Text;'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM t WHERE name='' + lFilter;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'Variable mit nicht-literaler Zuweisung bleibt SQL-Injection-Risiko');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'WHERE name='),
      TFindingHelper.FirstOf(F, fkSQLInjection).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_FormatStringMaskConcat_Reported;
// TP-Gegenkontrolle zum Masken-Gate: Format mit %s-Platzhalter kann
// beliebige Strings in das SQL tragen - Fund bleibt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Name: string);'#13#10+
  'begin'#13#10+
  '  qry.Open(''SELECT * FROM t WHERE name='' + Format(''%s'', [Name]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSQLInjection),
      'Format mit %s-Maske bleibt SQL-Injection-Risiko');
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
