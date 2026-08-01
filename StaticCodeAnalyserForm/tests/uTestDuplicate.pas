unit uTestDuplicate;

// Tests fuer DuplicateString- und DuplicateBlock-Detektoren.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- DuplicateString (TDuplicateStringDetector) ------------------------------------
  [TestFixture]
  TTestDuplicateString = class
  public
    [Test] procedure Dup_ThreeOccurrences_ReportsHint;
    [Test] procedure Dup_TwoOccurrences_NoFinding;
    [Test] procedure Dup_TooShortString_NoFinding;
    [Test] procedure Dup_TrivialFormatSpec_NoFinding;
    [Test] procedure Dup_FourOccurrences_ReportsHint;
    [Test] procedure Dup_DifferentStrings_NoFinding;
    [Test] procedure Dup_TwoDifferentDuplicates_BothReported;
    [Test] procedure Dup_StringInAssignment_Counted;
    [Test] procedure Dup_StringInCall_Counted;
    [Test] procedure Dup_TrueFalseTrivial_NoFinding;
  end;

  // ---- DuplicateBlock (TDuplicateBlockDetector) - filebasiert -----------------------
  [TestFixture]
  TTestDuplicateBlock = class
  public
    [Test] procedure Block_TwoIdenticalBlocks_ReportsHint;
    [Test] procedure Block_NoDuplicates_NoFinding;
    [Test] procedure Block_TooShort_NoFinding;
    [Test] procedure Block_TrivialLinesIgnored_NoFinding;
    [Test] procedure Block_ThreeIdenticalBlocks_ReportsOnce;
    [Test] procedure Block_BranchingBoilerplate_NoFinding;
    [Test] procedure Block_DifferentWhitespace_StillDetected;
    [Test] procedure Block_DifferentCase_StillDetected;
    [Test] procedure Block_CommentsBetween_StillDetected;
    [Test] procedure Block_FirstLineReported_NotLast;
    // ---- Deklarations-Boilerplate (30%-Audit 2026-07-31) ------------------
    [Test] procedure Block_PropertyRedeclarationList_NotReported;
    [Test] procedure Block_ParameterListInHeader_NotReported;
    [Test] procedure Block_FieldList_StillReported;
    [Test] procedure Block_RealCodeDuplicate_StillReported;
  end;

implementation

// =============================================================================
// DuplicateString-Tests
// =============================================================================

procedure TTestDuplicateString.Dup_ThreeOccurrences_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''wichtig'';'#13#10+
  '  s := ''wichtig'';'#13#10+
  '  s := ''wichtig'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TwoOccurrences_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''wichtig'';'#13#10+
  '  s := ''wichtig'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TooShortString_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''ab'';'#13#10+
  '  s := ''ab'';'#13#10+
  '  s := ''ab'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TrivialFormatSpec_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''%s'';'#13#10+
  '  s := ''%s'';'#13#10+
  '  s := ''%s'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_FourOccurrences_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''hello world'';'#13#10+
  '  s := ''hello world'';'#13#10+
  '  s := ''hello world'';'#13#10+
  '  s := ''hello world'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_DifferentStrings_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''Eins'';'#13#10+
  '  s := ''Zwei'';'#13#10+
  '  s := ''Drei'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TwoDifferentDuplicates_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''alpha'';'#13#10+
  '  s := ''alpha'';'#13#10+
  '  s := ''alpha'';'#13#10+
  '  s := ''beta'';'#13#10+
  '  s := ''beta'';'#13#10+
  '  s := ''beta'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_StringInAssignment_Counted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''SELECT * FROM t'';'#13#10+
  '  s := ''SELECT * FROM t'';'#13#10+
  '  s := ''SELECT * FROM t'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_StringInCall_Counted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  WriteLn(''Hallo Welt'');'#13#10+
  '  WriteLn(''Hallo Welt'');'#13#10+
  '  WriteLn(''Hallo Welt'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TrueFalseTrivial_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''true'';'#13#10+
  '  s := ''true'';'#13#10+
  '  s := ''true'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

// =============================================================================
// DuplicateBlock-Tests (zeilenbasierte Block-Duplikate)
// =============================================================================

procedure TTestDuplicateBlock.Block_TwoIdenticalBlocks_ReportsHint;
// Zwei Methoden mit identischer 8-Zeilen-Logik -> ein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDuplicateBlock) >= 1,
        'Doppelter 8-Zeilen-Block soll gemeldet werden');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_NoDuplicates_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  Q := 10;'#13#10+
  '  R := 20;'#13#10+
  '  S := 30;'#13#10+
  '  T := 40;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateBlock));
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_TooShort_NoFinding;
// Nur 5 identische Zeilen - unter MIN_BLOCK_LINES (8), kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateBlock));
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_TrivialLinesIgnored_NoFinding;
// Viele 'begin'/'end'-Zeilen sind trivial und zaehlen nicht. Auch
// wenn sich die Methodenrahmen aehneln, soll kein Block-Duplikat
// gemeldet werden, solange die unterschiedlichen Inhalte nur
// 1-2 nicht-triviale Zeilen sind.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  if X then'#13#10+
  '  begin'#13#10+
  '    DoA;'#13#10+
  '  end;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  if X then'#13#10+
  '  begin'#13#10+
  '    DoB;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateBlock));
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_BranchingBoilerplate_NoFinding;
// Block besteht ueberwiegend aus if/end-Logik (Validierungskette o.ae.) -
// soll NICHT als Duplikat gemeldet werden, weil das Extrahieren in eine
// gemeinsame Methode keinen Mehrwert hat (Pro Aufrufer andere Bedingungen).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  if not Valid1 then Exit;'#13#10+
  '  if not Valid2 then Exit;'#13#10+
  '  if not Valid3 then Exit;'#13#10+
  '  if not Valid4 then Exit;'#13#10+
  '  if not Valid5 then Exit;'#13#10+
  '  if not Valid6 then Exit;'#13#10+
  '  if not Valid7 then Exit;'#13#10+
  '  if not Valid8 then Exit;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  if not Valid1 then Exit;'#13#10+
  '  if not Valid2 then Exit;'#13#10+
  '  if not Valid3 then Exit;'#13#10+
  '  if not Valid4 then Exit;'#13#10+
  '  if not Valid5 then Exit;'#13#10+
  '  if not Valid6 then Exit;'#13#10+
  '  if not Valid7 then Exit;'#13#10+
  '  if not Valid8 then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateBlock),
        'Block aus reinen if-Zeilen ist Branching-Boilerplate, soll geskippt werden');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_ThreeIdenticalBlocks_ReportsOnce;
// Block kommt 3x vor - es soll trotzdem nur EIN Befund pro Erst-Vorkommen
// kommen (nicht 3 oder uberlappende Folge-Fenster).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.C; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Block in 3 Methoden - genau 1 Befund (kein Mehrfach-Reporting)');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_DifferentWhitespace_StillDetected;
// Bloecke unterscheiden sich nur in der Einrueckung / Whitespace-Anzahl.
// NormalizeLine kollabiert Whitespace - Duplikat soll trotzdem erkannt werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '      X    :=    1;'#13#10+        // viel Whitespace
  '   Y := 2;'#13#10+
  '       Z := 3;'#13#10+
  '   W := 4;'#13#10+
  '       V := 5;'#13#10+
  '   U := 6;'#13#10+
  '       T := 7;'#13#10+
  '   S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Whitespace-Unterschiede sollen Duplikat-Erkennung nicht verhindern');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_DifferentCase_StillDetected;
// Bezeichner unterscheiden sich nur in Gross-/Kleinschreibung.
// Pascal ist case-insensitiv, NormalizeLine lowercased - Duplikat erkennen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '  x := 1;'#13#10+                // klein
  '  y := 2;'#13#10+
  '  z := 3;'#13#10+
  '  w := 4;'#13#10+
  '  v := 5;'#13#10+
  '  u := 6;'#13#10+
  '  t := 7;'#13#10+
  '  s := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Case-Unterschiede sollen Duplikat-Erkennung nicht verhindern');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_CommentsBetween_StillDetected;
// Im zweiten Block stehen Kommentare zwischen den Code-Zeilen. Da
// Kommentare als trivial gefiltert werden, soll der Block trotzdem als
// Duplikat erkannt werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '  // erster Schritt'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  // zweiter Schritt'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  // dritter Schritt'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Kommentare zwischen Code-Zeilen sollen Duplikat-Erkennung nicht verhindern');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_FirstLineReported_NotLast;
// Der gemeldete LineNumber muss das Erst-Vorkommen sein, nicht das letzte.
const SRC =
  'unit t; implementation'#13#10+      // Zeile 1
  'procedure TFoo.A; begin'#13#10+    // 2
  '  X := 1;'#13#10+                   // 3 - Erst-Vorkommen Block-Start
  '  Y := 2;'#13#10+                   // 4
  '  Z := 3;'#13#10+                   // 5
  '  W := 4;'#13#10+                   // 6
  '  V := 5;'#13#10+                   // 7
  '  U := 6;'#13#10+                   // 8
  '  T := 7;'#13#10+                   // 9
  '  S := 8;'#13#10+                   // 10
  'end;'#13#10+                        // 11
  'procedure TFoo.B; begin'#13#10+    // 12
  '  X := 1;'#13#10+                   // 13 - Zweit-Vorkommen
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var
  F: TObjectList<TLeakFinding>;
  Finding: TLeakFinding;
  FoundExpected: Boolean;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDuplicateBlock));
    FoundExpected := False;
    for Finding in F do
      if (Finding.Kind = fkDuplicateBlock) and (Finding.LineNumber = '3') then
      begin
        FoundExpected := True;
        Break;
      end;
    Assert.IsTrue(FoundExpected,
      'Befund-Zeile muss 3 (Erst-Vorkommen) sein, nicht 13 (Zweit-Vorkommen)');
  finally F.Free;
  end;
end;

procedure TTestDuplicateBlock.Block_PropertyRedeclarationList_NotReported;
// Das Wiederholen published-er Properties IST der Delphi-Mechanismus, mit
// dem eine Ableitung geerbte Properties publiziert. Es gibt nichts zu
// extrahieren. Korpus-Beleg: cnwizards StdCtrls.pas:351, jvcl JvCombos.pas:139.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TFooA = class(TEdit)'#13#10+
  '  published'#13#10+
  '    property Visible;'#13#10+
  '    property OnClick;'#13#10+
  '    property OnDblClick;'#13#10+
  '    property OnEnter;'#13#10+
  '    property OnExit;'#13#10+
  '    property OnKeyPress;'#13#10+
  '    property Spacing;'#13#10+
  '    property Default;'#13#10+
  '  end;'#13#10+
  '  TFooB = class(TEdit)'#13#10+
  '  published'#13#10+
  '    property Visible;'#13#10+
  '    property OnClick;'#13#10+
  '    property OnDblClick;'#13#10+
  '    property OnEnter;'#13#10+
  '    property OnExit;'#13#10+
  '    property OnKeyPress;'#13#10+
  '    property Spacing;'#13#10+
  '    property Default;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateBlock),
    'published-property-Redeklaration ist sprachliches Boilerplate');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_ParameterListInHeader_NotReported;
// Delphi erzwingt die Wiederholung der Parameterliste in Deklaration UND
// Implementierung. Erkennungsmerkmal ist die OFFENE KLAMMER - ohne sie
// waere es eine Feldliste, und die bleibt ein Fund (naechster Test).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TFoo = class'#13#10+
  '    constructor CreateA('#13#10+
  '                  CreateSuspended: Boolean;'#13#10+
  '                  AOwner: TWinControl;'#13#10+
  '                  ARank: Integer;'#13#10+
  '                  ASQL: AnsiString;'#13#10+
  '                  AMaxLoop: Integer;'#13#10+
  '                  ANBLoop: Integer;'#13#10+
  '                  AKey: AnsiString;'#13#10+
  '                  AFlags: AnsiString);'#13#10+
  '    constructor CreateB('#13#10+
  '                  CreateSuspended: Boolean;'#13#10+
  '                  AOwner: TWinControl;'#13#10+
  '                  ARank: Integer;'#13#10+
  '                  ASQL: AnsiString;'#13#10+
  '                  AMaxLoop: Integer;'#13#10+
  '                  ANBLoop: Integer;'#13#10+
  '                  AKey: AnsiString;'#13#10+
  '                  AFlags: AnsiString);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkDuplicateBlock),
    'Parameterliste im Routinenkopf ist sprachlich erzwungen');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_FieldList_StillReported;
// WAECHTER, und zugleich die bewusste Grenze des Gates: eine doppelte
// FELDLISTE sieht aus wie eine Parameterliste, steht aber NICHT in einer
// offenen Klammer. Zwei Klassen mit identischer Feldliste sind eine echte
// Copy-Paste-Spur; das Audit deckt sie nicht, also bleibt der Fund.
// Im Korpus sind das 744 Funde.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TFooA = class'#13#10+
  '  private'#13#10+
  '    FOn: Boolean;'#13#10+
  '    FMaxLoop: Integer;'#13#10+
  '    FErrorMsg: AnsiString;'#13#10+
  '    FRank: Integer;'#13#10+
  '    FTotalLoop: Integer;'#13#10+
  '    FOwner: TWinControl;'#13#10+
  '    FKey: AnsiString;'#13#10+
  '    FFlags: AnsiString;'#13#10+
  '  end;'#13#10+
  '  TFooB = class'#13#10+
  '  private'#13#10+
  '    FOn: Boolean;'#13#10+
  '    FMaxLoop: Integer;'#13#10+
  '    FErrorMsg: AnsiString;'#13#10+
  '    FRank: Integer;'#13#10+
  '    FTotalLoop: Integer;'#13#10+
  '    FOwner: TWinControl;'#13#10+
  '    FKey: AnsiString;'#13#10+
  '    FFlags: AnsiString;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDuplicateBlock) >= 1,
    'Doppelte Feldliste steht in KEINER offenen Klammer und bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_RealCodeDuplicate_StillReported;
// WAECHTER: der Kern der Regel bleibt unangetastet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure A;'#13#10+
  'begin'#13#10+
  '  Alpha := 1;'#13#10+
  '  Beta := 2;'#13#10+
  '  Gamma := 3;'#13#10+
  '  Delta := 4;'#13#10+
  '  Epsilon := 5;'#13#10+
  '  Zeta := 6;'#13#10+
  '  Eta := 7;'#13#10+
  '  Theta := 8;'#13#10+
  'end;'#13#10+
  'procedure B;'#13#10+
  'begin'#13#10+
  '  Alpha := 1;'#13#10+
  '  Beta := 2;'#13#10+
  '  Gamma := 3;'#13#10+
  '  Delta := 4;'#13#10+
  '  Epsilon := 5;'#13#10+
  '  Zeta := 6;'#13#10+
  '  Eta := 7;'#13#10+
  '  Theta := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDuplicateBlock) >= 1,
    'Echtes Code-Duplikat bleibt ein Fund');
  finally F.Free; end;
end;

end.