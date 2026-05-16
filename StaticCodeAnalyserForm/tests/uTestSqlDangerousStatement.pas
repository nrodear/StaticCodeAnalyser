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

initialization
  TDUnitX.RegisterTestFixture(TTestSqlDangerousStatement);

end.
