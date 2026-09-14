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
    // Voll-Review 2026-09-12 (Blocker): Exit am Treffer verlor den
    // Kommentar-Zustand des Zeilenrests.
    [Test] procedure With_CommentOpenedAfterHit_NextLineNotScanned;
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
    // Posten 225: (* *) mehrzeilig, Zustandsleck-Regression, -Escape
    [Test] procedure With_InMultiLineParenStarComment_NoFinding;
    [Test] procedure With_ThenCommentOpened_NoSecondFinding;
    [Test] procedure With_InStringWithEscapedQuote_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// ---- Positive Varianten ------------------------------------------------------

procedure TTestWithStatement.With_CommentOpenedAfterHit_NextLineNotScanned;
// 'with L do begin  { alte Notiz' meldet (korrekt) - aber das dahinter
// GEOEFFNETE '{' muss den Zustand setzen: die auskommentierte
// Folgezeile 'with M do Add(1); }' darf NICHT melden. Vor dem Fix: 2.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  with L do begin  { alte Notiz'#13#10 +
  '  with M do Add(1); }'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkWithStatement),
    'das auskommentierte with der Folgezeile darf nicht melden');
  finally F.Free; end;
end;

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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkWithStatement));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkWithStatement));
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
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkWithStatement));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkWithStatement));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithStatement));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithStatement));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithStatement));
  finally F.Free; end;
end;

{ --- Posten 225: die drei Zusagen des Unit-Kopfs belegen --------- }
//
// Der Unit-Kopf listet '(*..*)-Blockkommentare (mehrzeilig)' und den
// ''-Escape in Strings als getestete Lexer-Schritte. Vorhanden war
// aber nur der einzeilige {..}-Test und ein einfacher String-Test.
//
// Alle drei hier am gebauten Stand gemessen. Keiner aendert Verhalten -
// sie belegen Zusagen, die bisher nur behauptet waren.

procedure TTestWithStatement.With_InMultiLineParenStarComment_NoFinding;
// Die (* *)-Zusage des Kopfs, mehrzeilig. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  Beep;  (*'#13#10+
  '  with L do Bar;'#13#10+
  '  *)'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkWithStatement),
      'with in einem mehrzeiligen (* *) ist kein Code');
  finally F.Free; end;
end;

procedure TTestWithStatement.With_ThenCommentOpened_NoSecondFinding;
// REGRESSIONSWAECHTER fuer den Blocker-Fix des Voll-Reviews: FindWith
// scannt die Zeile auch NACH dem Treffer zu Ende, damit ein dahinter
// geoeffnetes "{" verfolgt wird. Ohne den Fix waeren es 2.
// Gemessen: 1.
//
// In derselben Charge hat genau dieses Leck noch in
// uSuperfluousSemicolon, uGotoStatement und uGroupedDeclaration
// gesteckt - hier ist es seit dem Voll-Review zu, war aber unbelegt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  with L do Bar;  {'#13#10+
  '  with M do Baz;'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkWithStatement),
      'nur das echte with zaehlt, das im Kommentar nicht');
  finally F.Free; end;
end;

procedure TTestWithStatement.With_InStringWithEscapedQuote_NoFinding;
// Die ''-Escape-Zusage des Kopfs: das Literal enthaelt einen
// verdoppelten Apostroph UND danach das Wort with. Endet der
// String-Scanner am Escape zu frueh, wird das with zu Code.
// Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''don''''t with M'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkWithStatement),
      'das with im String-Literal ist kein Statement');
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkWithStatement));
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
