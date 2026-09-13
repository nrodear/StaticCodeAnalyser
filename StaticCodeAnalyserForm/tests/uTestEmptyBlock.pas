unit uTestEmptyBlock;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyBlock = class
  public
    [Test] procedure NonEmptyBlock_NoFinding;
    [Test] procedure EmptySameLine_Reported;
    [Test] procedure EmptyMultiline_Reported;
    [Test] procedure EmptyMethodBody_NotReported;
    [Test] procedure TopLevelInitEmpty_NotReported;
    [Test] procedure EmptyBlock_KindAndSeverity;
    [Test] procedure LiteralBeginEnd_NotReported;
    // Posten 199: while / else / case und der var-Rueckwaertslauf
    [Test] procedure EmptyBlockAfterWhile_Reported;
    [Test] procedure EmptyBlockAfterElse_Reported;
    [Test] procedure EmptyBlockInCaseBranch_Reported;
    [Test] procedure EmptyRoutineBodyAfterVarSection_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 199: die uebrigen Starter der Keywordliste ----------- }
//
// Getestet war nur der if/then-Kontext. IsRoutineBody kennt aber
// mehrere Starter, und 'while', 'else' und 'case' waren allesamt
// unbelegt - ebenso der var-Section-Rueckwaertslauf, der einen
// LEEREN ROUTINENRUMPF von einem leeren Block unterscheidet.
//
// Alle vier am gebauten Stand gemessen.

procedure TTestEmptyBlock.EmptyBlockAfterWhile_Reported;
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  while C do begin end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkEmptyBlock),
      'ein leerer while-Rumpf ist ein leerer Block');
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptyBlockAfterElse_Reported;
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if C then A else begin end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkEmptyBlock),
      'ein leerer else-Zweig ist ein leerer Block');
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptyBlockInCaseBranch_Reported;
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  case K of 1: begin end; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkEmptyBlock),
      'ein leerer case-Zweig ist ein leerer Block');
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptyRoutineBodyAfterVarSection_NoFinding;
// DIE ABGRENZUNG: ein leerer ROUTINENRUMPF ist kein leerer Block -
// dafuer laeuft der Scanner von begin aus RUECKWAERTS ueber die
// var-Sektion bis zum Routinenkopf. Genau dieser Rueckwaertslauf war
// ungetestet; ohne ihn wuerde hier gemeldet. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var I: Integer;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkEmptyBlock),
      'ein leerer Routinenrumpf hinter einer var-Sektion ist kein '
      + 'leerer Block');
  finally F.Free; end;
end;


procedure TTestEmptyBlock.NonEmptyBlock_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyBlock));
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptySameLine_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  if Active then begin end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyBlock) >= 1);
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptyMultiline_Reported;
// Mehrzeiliger leerer in-statement-Block. Methoden-Bodies sind explizit
// ausgenommen (deckt uEmptyMethod ab), daher der `if X then begin..end;`
// Wrapper um die zu pruefende Stelle.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if Active then'#13#10 +
  '  begin'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyBlock) >= 1);
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptyMethodBody_NotReported;
// Leere Methoden-Bodies sind explizit ausgenommen (uEmptyMethod deckt
// das ab). Hier darf KEIN fkEmptyBlock erscheinen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyBlock));
  finally F.Free; end;
end;

procedure TTestEmptyBlock.TopLevelInitEmpty_NotReported;
// `begin end.` als Unit-Initialization darf nicht melden.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'begin'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyBlock));
  finally F.Free; end;
end;

procedure TTestEmptyBlock.EmptyBlock_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; if X then begin end; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyBlock then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyBlock, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,      Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyBlock finding');
  finally F.Free; end;
end;

procedure TTestEmptyBlock.LiteralBeginEnd_NotReported;
// Review-MEDIUM 2026-08-09: 'begin end' INNERHALB eines String-Literals
// (SQL-Block/Codegen-Template) ist kein leerer Code-Block - vor dem Fix
// liess der Wortgrenzen-Check das Quote-Zeichen durch und meldete FP.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure EmitSqlTemplate;'#13#10 +
  'begin'#13#10 +
  '  if TemplateActive then AppendSql(''begin end'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyBlock),
    '''begin end'' im String-Literal ist kein leerer Block');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyBlock);

end.
