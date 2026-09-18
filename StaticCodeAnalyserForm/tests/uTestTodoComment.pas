unit uTestTodoComment;

// Tests fuer den TTodoCommentDetector (filebasiert).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- TodoComment (TTodoCommentDetector) - filebasiert ------------------------------
  [TestFixture]
  TTestTodoComment = class
  public
    [Test] procedure Todo_LineComment_ReportsHint;
    [Test] procedure Todo_FixmeMarker_ReportsHint;
    [Test] procedure Todo_HackMarker_ReportsHint;
    [Test] procedure Todo_XxxMarker_ReportsHint;
    [Test] procedure Todo_BraceComment_ReportsHint;
    [Test] procedure Todo_MultilineBraceComment_ReportsHint;
    [Test] procedure Todo_TodoInsideStringLiteral_NoFinding;
    // Voll-Review 2026-09-12 (Blocker): die Suche lief hinter einem
    // geschlossenen { } weiter und traf Strings/Code dahinter.
    [Test] procedure Todo_StringBehindClosedBrace_NoFinding;
    [Test] procedure Todo_SecondCommentOnLine_StillReported;
    [Test] procedure Todo_TodoAsIdentifier_NoFinding;
    [Test] procedure Todo_LowercaseMarker_StillReported;
    [Test] procedure Todo_NoMarker_NoFinding;
    // 'XXX' zaehlt nur in Grossschreibung (Korpus-Messung 2026-08-20:
    // 192 klein/gemischt geschriebene Funde, KEIN einziger ein Marker).
    [Test] procedure Xxx_LowercasePlaceholder_NoFinding;
    [Test] procedure Xxx_MixedCase_NoFinding;
    [Test] procedure Xxx_Uppercase_StillReported;

    // Voll-Review 2026-09-12 (Testluecken 110/111, Minor 276)
    [Test] procedure Todo_FileReferenceSuffix_NoFinding;
    [Test] procedure Todo_InSingleQuotes_NoFinding;
    [Test] procedure Todo_SlashListNotation_NoFinding;
    [Test] procedure Todo_InParens_NoFinding;
    [Test] procedure Todo_GuardsDoNotSwallowRealMarker;
    [Test] procedure Todo_StringLiteralAfterClosedBrace_NoFinding;
    [Test] procedure Todo_InParenStarComment_KnownGap;
    // Audit Fundbewegend 2026-09-15, P4: die 57er-Kuerzung darf kein
    // Surrogatpaar durchschneiden (Kanalbeweis fuer TruncateSurrogateSafe).
    [Test] procedure Todo_EmojiOnCutBoundary_NoBrokenSurrogate;
  end;

implementation

// noinspection-file GodClass
// Eine Test-Fixture je Detektor ist die Projektkonvention; die Klasse
// waechst mit jedem gepinnten Fall. Mit den sieben Faellen aus den
// Testluecken 110/111 und Minor 276 (Voll-Review 2026-09-12) hat sie
// die 20-Methoden-Schwelle ueberschritten - Aufteilen wuerde die Faelle
// desselben Detektors auseinanderreissen. Gleicher Marker und gleiche
// Begruendung wie in uTestDuplicate und uTestExportHtml.

// =============================================================================
// TodoComment-Tests (filebasiert via FindingsOfFile)
// =============================================================================

procedure TTestTodoComment.Todo_LineComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// TODO: Tabelle persistieren'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_FixmeMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// FIXME: race condition'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_HackMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// HACK: workaround fuer Bug'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_XxxMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// XXX: muss noch geklaert werden'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_BraceComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '{ TODO: refactoring noetig }'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_MultilineBraceComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '{'#13#10+
  '  FIXME: das hier muss neu gebaut werden'#13#10+
  '  weil...'#13#10+
  '}'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_TodoInsideStringLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := ''TODO marker im String''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_StringBehindClosedBrace_NoFinding;
// 'x := 1; { init } s := ''TODO: nicht vergessen'';' - der Kommentar
// endet am '}', das TODO steht in einem STRING dahinter. Vor dem Fix
// durchsuchte FindMarkerInComment die ganze Restzeile und meldete.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; x: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := 1; { init } s := ''TODO: nicht vergessen'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'ein TODO im String hinter einem geschlossenen Kommentar ist keins');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_SecondCommentOnLine_StillReported;
// Die Gegenrichtung der Segment-Schleife: nach einem geschlossenen
// { init } muss ein ECHTER Marker im ZWEITEN Kommentar derselben
// Zeile weiterhin gefunden werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  x := 1; { init } // TODO: spaeter aufraeumen'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment),
    'der Marker im zweiten Kommentar der Zeile muss melden');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_TodoAsIdentifier_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var TodoList: Integer;'#13#10+
  'begin TodoList := 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_LowercaseMarker_StillReported;
const SRC =
  'unit t; implementation'#13#10+
  '// todo: kleinschreibung'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_NoMarker_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  '// gewoehnlicher Kommentar'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Xxx_LowercasePlaceholder_NoFinding;
// Der haeufigste Fall im Korpus: 'xxx' als Platzhalter in einem
// HTML-Attribut, MIME-Typ oder Pfad - nie ein Marker.
const SRC =
  'unit t; implementation'#13#10+
  '// <span id="xxx" width="xxx"> multipart/xxx'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'kleingeschriebenes xxx ist ein Platzhalter, kein Marker');
  finally F.Free; end;
end;

procedure TTestTodoComment.Xxx_MixedCase_NoFinding;
// 'Xxx' ist ebenfalls keine Marker-Schreibweise - die Konvention ist
// durchgaengig gross.
const SRC =
  'unit t; implementation'#13#10+
  '// siehe Xxx im Beispiel'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Xxx_Uppercase_StillReported;
// Die Gegenprobe: der ECHTE Marker bleibt ein Fund. Ohne diesen Test
// koennte die Schreibweisen-Regel die Regel stillschweigend abschalten.
const SRC =
  'unit t; implementation'#13#10+
  '// XXX: das hier ist wirklich kaputt'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment),
    'grossgeschriebenes XXX muss weiterhin melden');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_FileReferenceSuffix_NoFinding;
// Testluecke 110 (Voll-Review 2026-09-12): die fuenf FP-Guards in
// FindMarkerInComment waren komplett testlos. Ohne Pin kann jeder von
// ihnen still zum Alles-Schlucker werden - dieser faengt Datei- und
// Pfad-Referenzen ('todo.md', 'todo-sonar').
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // siehe todo.md fuer Details'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'todo.md ist eine Dateireferenz, kein Marker');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_InSingleQuotes_NoFinding;
// Guard 2: der Marker steht in Anfuehrungszeichen - er wird zitiert,
// nicht gesetzt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // das Wort ''TODO'' ist hier nur zitiert'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'ein zitierter Marker ist kein Marker');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_SlashListNotation_NoFinding;
// Guard 3/4: Slash-Listen-Notation ('TODO / FIXME') - eine
// Aufzaehlung von Markernamen, kein gesetzter Marker.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // TODO / FIXME sind Listen'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'Slash-Listen-Notation ist eine Aufzaehlung');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_InParens_NoFinding;
// Guard 5: Marker direkt vor ')' - '(TODO)' ist eine Erwaehnung.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // ein Hinweis (TODO) am Rand'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'geklammerter Marker ist eine Erwaehnung');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_GuardsDoNotSwallowRealMarker;
// Die Gegenprobe, ohne die die vier Tests darueber wertlos waeren:
// ein ECHTER Marker in derselben Datei muss weiter feuern. An der
// Bestands-Exe gemessen - genau eine der vier Zeilen meldet.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  // siehe todo.md fuer Details'#13#10 +
  '  // TODO / FIXME sind Listen'#13#10 +
  '  // ein Hinweis (TODO) am Rand'#13#10 +
  '  // TO' + 'DO: echter Marker'#13#10 +   // gestueckelt: kein Selbstfund
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment),
    'die Guards duerfen den echten Marker nicht mitnehmen');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_StringLiteralAfterClosedBrace_NoFinding;
// Testluecke 111: Regressionstest zum BLOCKER. Der Kommentarbereich
// endete nicht am schliessenden '}' - alles dahinter galt als
// Kommentar, ein String-Literal mit dem Marker-Wort wurde also
// gemeldet.
// An der Bestands-Exe belegt: genau diese Zeile liefert einen Fund;
// nach dem Fix darf sie keinen mehr liefern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { alter Kommentar } DoIt(''TODO im String'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'hinter dem schliessenden } endet der Kommentar');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_InParenStarComment_KnownGap;
// DOKUMENTIERT EINE LUECKE (Minor 276): (*...*)-Kommentare werden gar
// nicht gescannt, Marker darin sind stille FNs. Der Test haelt den
// Ist-Zustand fest - wird der Scanner erweitert, wird er rot und muss
// bewusst auf 1 umgestellt werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  (* TODO: in Klammer-Stern-Kommentar *)'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTodoComment),
    'BEKANNTE LUECKE: (*..*) wird nicht gescannt');
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_EmojiOnCutBoundary_NoBrokenSurrogate;
// Snippet-Aufbau: 'TODO: ' (6 Units) + 50x 'x' (7-56) + Emoji U+1F600
// (High #$D83D auf Unit 57, Low #$DE00 auf 58) + 'yyyy' (59-62).
// Laenge 62 > 60 -> Kuerzung auf 57 traefe exakt die Paar-Mitte. Mit
// TruncateSurrogateSafe faellt das High-Surrogat mit weg: der Meldetext
// endet auf 'x...' und traegt kein halbes Zeichen. Vor der Umstellung
// (blankes Copy) stand #$D83D vor der Ellipse - dieser Test war rot.
const SRC =
  'unit t; implementation'#13#10 +
  '// TODO: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' +
  #$D83D#$DE00 + 'yyyy'#13#10 +
  'procedure Foo; begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTodoComment));
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkTodoComment then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit);
    Assert.IsTrue(Hit.MissingVar.EndsWith('x...'),
      'Kuerzung endet vor dem Emoji: ' + Hit.MissingVar);
    Assert.AreEqual<Integer>(0, Pos(#$D83D, Hit.MissingVar),
      'kein haengendes High-Surrogat im Meldetext');
  finally F.Free; end;
end;

end.
