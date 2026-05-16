unit uTestConcatToFormat;

// Tests fuer den TConcatToFormatDetector (AST-basiert).
//
// Heuristik unter Test (vgl. uConcatToFormat.pas):
//   * Mindestens MIN_NON_LITERAL_PLUS (=2) echte '+' Operatoren auf RHS
//   * Mindestens ein Literal und ein Non-Literal-Term in der Kette
//   * SQL-LHS (z.B. '.sql.text') wird ausgeklammert (uSQLInjection-Domain)
//   * RHS mit bereits vorhandenem 'Format(' / 'FormatUtf8(' -> kein Hint
//   * Severity-Default: lsWarning, Kind: fkConcatToFormat

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConcatToFormat = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure Concat_TwoPluses_LiteralAndVar_Reported;
    [Test] procedure Concat_ThreePluses_MixedTerms_Reported;
    [Test] procedure Concat_WithIntToStrCall_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure Concat_SinglePlus_BelowThreshold_NoFinding;
    [Test] procedure Concat_OnlyLiterals_NoFinding;
    [Test] procedure Concat_OnlyVariables_NoFinding;
    [Test] procedure Concat_AlreadyUsesFormat_Suppressed;
    [Test] procedure Concat_SqlContext_DeferredToSqlInjection;

    // ---- Finding-Inhalt / FindingKind / Severity --------------------------
    [Test] procedure Concat_Finding_KindAndSeverity;
    [Test] procedure Concat_Finding_MissingVarMentionsPlusCount;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

// ---- Positive Varianten ------------------------------------------------------

procedure TTestConcatToFormat.Concat_TwoPluses_LiteralAndVar_Reported;
// 'a' + x + 'b'  -> 2 echte '+', Literal + Variable -> Treffer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: string; r: string;'#13#10 +
  'begin r := ''a'' + x + ''b''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_ThreePluses_MixedTerms_Reported;
// Kette mit vier Termen: 'Hallo ' + Name + ', du bist ' + Age
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Name: string; Age: string; r: string;'#13#10 +
  'begin r := ''Hallo '' + Name + '', du bist '' + Age; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_WithIntToStrCall_Reported;
// Call-Expression IntToStr(Age) zaehlt als Non-Literal-Term.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Age: Integer; r: string;'#13#10 +
  'begin r := ''Alter='' + IntToStr(Age) + ''.''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

// ---- Negative Varianten / Guards --------------------------------------------

procedure TTestConcatToFormat.Concat_SinglePlus_BelowThreshold_NoFinding;
// 'a' + x  -> nur 1 echtes '+', unterhalb der Schwelle MIN_NON_LITERAL_PLUS=2.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: string; r: string;'#13#10 +
  'begin r := ''a'' + x; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_OnlyLiterals_NoFinding;
// Reine Literal-Konkatenation - kein Format-Kandidat.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var r: string;'#13#10 +
  'begin r := ''a'' + ''b'' + ''c''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_OnlyVariables_NoFinding;
// Reine Variablen-Konkat - kein Literal-Anteil, also kein Format-Hint
// (sonst waeren auch a + b + c betroffen, was nicht sinnvoll ist).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c, r: string;'#13#10 +
  'begin r := a + b + c; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_AlreadyUsesFormat_Suppressed;
// RHS enthaelt bereits Format(...) -> kein Refactor-Hint.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Name: string; r: string;'#13#10 +
  'begin r := ''Pre '' + Format(''%s'', [Name]) + '' Post''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_SqlContext_DeferredToSqlInjection;
// LHS .SQL.Text -> Skip (uSQLInjection ist zustaendig).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Q: TFDQuery; UserId, WhereClause: string;'#13#10 +
  'begin Q.SQL.Text := ''SELECT * FROM t WHERE id='' + UserId + WhereClause; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkConcatToFormat));
  finally F.Free; end;
end;

// ---- Finding-Inhalt ---------------------------------------------------------

procedure TTestConcatToFormat.Concat_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: string; r: string;'#13#10 +
  'begin r := ''a'' + x + ''b''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkConcatToFormat then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkConcatToFormat finding expected');
    Assert.AreEqual(fkConcatToFormat, Hit.Kind);
    Assert.AreEqual(lsWarning,        Hit.Severity);
  finally F.Free; end;
end;

procedure TTestConcatToFormat.Concat_Finding_MissingVarMentionsPlusCount;
// 'a' + x + 'b' + y  -> 3 echte '+' Operatoren; Report enthaelt die Zahl.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y, r: string;'#13#10 +
  'begin r := ''a'' + x + ''b'' + y; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkConcatToFormat then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkConcatToFormat finding expected');
    Assert.Contains(Hit.MissingVar, '3');
    Assert.Contains(Hit.MissingVar, 'Format');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConcatToFormat);

end.
