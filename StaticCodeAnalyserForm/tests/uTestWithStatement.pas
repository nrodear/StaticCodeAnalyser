unit uTestWithStatement;

// Tests fuer den TWithStatementDetector (file-basiertes Scanning).
//
// Wegen File-Scan via TStringList.LoadFromFile gehen alle Tests ueber
// FindingsOfFile (schreibt SRC in eine Temp-Datei und ruft alle file-
// basierten Detektoren auf).
//
// Lexer-Schritte unter Test:
//   * `with`-Match nur mit beidseitiger Wortgrenze
//   * String-Literale ('..' inkl. ''-Escape) werden uebersprungen
//   * //, {..}, (*..*) - Kommentare werden uebersprungen (mehrzeilig fuer
//     die Block-Varianten)
//   * Pro Zeile nur ein Finding (auch bei `with a do with b do ...`)
//   * Default-Severity = lsWarning, Kind = fkWithStatement

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWithStatement = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure With_SimpleStatement_Reported;
    [Test] procedure With_NestedWith_OnePerLineRule;
    [Test] procedure With_MultipleStatements_AllReported;
    [Test] procedure With_UppercaseKeyword_StillReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure With_AsIdentifierPart_NoFinding;
    [Test] procedure With_InsideStringLiteral_NoFinding;
    [Test] procedure With_InLineComment_NoFinding;
    [Test] procedure With_InBlockComment_NoFinding;

    // ---- Finding-Inhalt / FindingKind / Severity --------------------------
    [Test] procedure With_Finding_KindAndSeverity;
    [Test] procedure With_Finding_LineAndSnippetPopulated;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// ---- Positive Varianten ------------------------------------------------------

procedure TTestWithStatement.With_SimpleStatement_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  with L do Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

procedure TTestWithStatement.With_NestedWith_OnePerLineRule;
// `with a do with b do ...` in einer Zeile -> nur ein Finding pro Zeile.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList; O: TObject;'#13#10 +
  'begin'#13#10 +
  '  with L do with O do Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

procedure TTestWithStatement.With_MultipleStatements_AllReported;
// Drei `with`-Zeilen -> drei Findings.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  with L do Add(''a'');'#13#10 +
  '  with L do Add(''b'');'#13#10 +
  '  with L do Add(''c'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(3, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

procedure TTestWithStatement.With_UppercaseKeyword_StillReported;
// Pascal ist case-insensitive -> `WITH` triggert ebenfalls.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  WITH L DO Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

// ---- Negative Varianten / Guards --------------------------------------------

procedure TTestWithStatement.With_AsIdentifierPart_NoFinding;
// Bezeichner `Withdraw`, `EndsWith`, `MyWithness` enthalten `with` aber
// als Identifier-Substring - Wortgrenze schuetzt davor.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Withdraw;'#13#10 +
  'var EndsWith: Boolean; MyWithness: Integer;'#13#10 +
  'begin'#13#10 +
  '  EndsWith := False;'#13#10 +
  '  MyWithness := 42;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

procedure TTestWithStatement.With_InsideStringLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := ''with L do nichts'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

procedure TTestWithStatement.With_InLineComment_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // with L do Add(''x'');'#13#10 +
  '  Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

procedure TTestWithStatement.With_InBlockComment_NoFinding;
// Mehrzeiliger {..}-Kommentar - InBlockComm muss ueber Zeilen mitgefuehrt
// werden, sonst rutscht das with auf Zeile 2 durch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { Block-Kommentar'#13#10 +
  '    with L do Add(x);'#13#10 +
  '    Ende }'#13#10 +
  '  Bar;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

// ---- Finding-Inhalt ---------------------------------------------------------

procedure TTestWithStatement.With_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  with L do Add(''x'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkWithStatement then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkWithStatement finding expected');
    Assert.AreEqual(fkWithStatement, Hit.Kind);
    Assert.AreEqual(lsWarning,       Hit.Severity);
  finally F.Free; end;
end;

procedure TTestWithStatement.With_Finding_LineAndSnippetPopulated;
// LineNumber muss gesetzt sein, MissingVar enthaelt einen Snippet-Hinweis
// mit dem with-Keyword.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  with L do Add(''x'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkWithStatement then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkWithStatement finding expected');
    Assert.AreNotEqual('', Hit.LineNumber);
    Assert.Contains(LowerCase(Hit.MissingVar), 'with');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWithStatement);

end.
