unit uTestGotoStatement;

// Tests fuer den TGotoStatementDetector (file-basiertes Scanning).
//
// Wegen File-Scan via TStringList.LoadFromFile gehen alle Tests ueber
// FindingsOfFile (schreibt SRC in eine Temp-Datei und ruft alle file-
// basierten Detektoren auf).
//
// Lexer-Schritte unter Test:
//   * `goto`-Match nur mit beidseitiger Wortgrenze
//   * String-Literale ('..' inkl. ''-Escape) werden uebersprungen
//   * //, {..}, (*..*) - Kommentare werden uebersprungen (mehrzeilig fuer
//     die Block-Varianten)
//   * Default-Severity = lsWarning, Kind = fkGotoStatement
//
// SonarDelphi-Mapping: communitydelphi:GotoStatement.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGotoStatement = class
  public
    // ---- Positive Varianten ----
    [Test] procedure Goto_SimpleJump_Reported;
    [Test] procedure Goto_MultipleJumps_AllReported;
    [Test] procedure Goto_UppercaseKeyword_StillReported;

    // ---- Negative Varianten / Guards ----
    [Test] procedure Goto_AsIdentifierPart_NoFinding;
    [Test] procedure Goto_InsideStringLiteral_NoFinding;
    [Test] procedure Goto_InLineComment_NoFinding;
    [Test] procedure Goto_InBlockComment_NoFinding;
    [Test] procedure Goto_InParenStarComment_NoFinding;

    // ---- Finding-Inhalt / FindingKind / Severity ----
    [Test] procedure Goto_Finding_KindAndSeverity;
    [Test] procedure Goto_Finding_LinePopulated;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// ---- Positive Varianten ----

procedure TTestGotoStatement.Goto_SimpleJump_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'label MyExit;'#13#10 +
  'begin'#13#10 +
  '  goto MyExit;'#13#10 +
  '  MyExit:'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_MultipleJumps_AllReported;
// Drei separate `goto`-Zeilen -> drei Findings.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'label A, B, C;'#13#10 +
  'begin'#13#10 +
  '  if a then goto A;'#13#10 +
  '  if b then goto B;'#13#10 +
  '  if c then goto C;'#13#10 +
  '  A: B: C:'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(3, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_UppercaseKeyword_StillReported;
// Pascal-Keywords sind case-insensitive; GOTO == goto == Goto.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'label X;'#13#10 +
  'begin'#13#10 +
  '  GOTO X;'#13#10 +
  '  X:'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

// ---- Negative Varianten / Guards ----

procedure TTestGotoStatement.Goto_AsIdentifierPart_NoFinding;
// Bezeichner die `goto` enthalten ("MyGotoFlag", "PageGotoButton")
// duerfen NICHT matchen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var MyGotoFlag : Boolean; PageGotoButton: TObject;'#13#10 +
  'begin'#13#10 +
  '  MyGotoFlag := True;'#13#10 +
  '  PageGotoButton := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_InsideStringLiteral_NoFinding;
// 'goto' in einem String darf NICHT matchen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''do not use goto here'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_InLineComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // goto label is deprecated, do not use'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_InBlockComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { goto explained in section 7.3 }'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_InParenStarComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  (* goto loop_start is not allowed *)'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkGotoStatement));
  finally F.Free; end;
end;

// ---- Finding-Inhalt / FindingKind / Severity ----

function FirstGoto(F: TObjectList<TLeakFinding>): TLeakFinding;
var Fnd: TLeakFinding;
begin
  Result := nil;
  for Fnd in F do
    if Fnd.Kind = fkGotoStatement then Exit(Fnd);
end;

procedure TTestGotoStatement.Goto_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'label X;'#13#10 +
  'begin'#13#10 +
  '  goto X;'#13#10 +
  '  X:'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Fnd := FirstGoto(F);
    Assert.IsNotNull(Fnd, 'expected one fkGotoStatement finding');
    Assert.AreEqual<TFindingKind>(fkGotoStatement, Fnd.Kind);
    Assert.AreEqual<TLeakSeverity>(lsWarning,      Fnd.Severity);
  finally F.Free; end;
end;

procedure TTestGotoStatement.Goto_Finding_LinePopulated;
const SRC =
  'unit t; implementation'#13#10 +    // line 1
  'procedure Foo;'#13#10 +             // line 2
  'label X;'#13#10 +                   // line 3
  'begin'#13#10 +                      // line 4
  '  goto X;'#13#10 +                  // line 5  <-- finding here
  '  X:'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Fnd := FirstGoto(F);
    Assert.IsNotNull(Fnd);
    Assert.AreEqual('5', Fnd.LineNumber);
    Assert.Contains(Fnd.MissingVar, 'goto');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGotoStatement);

end.
