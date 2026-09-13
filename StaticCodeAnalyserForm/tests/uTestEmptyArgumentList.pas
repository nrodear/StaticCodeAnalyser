unit uTestEmptyArgumentList;

// Tests fuer TEmptyArgumentListDetector (file-scan: `Foo()` -> `Foo;`).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyArgumentList = class
  public
    [Test] procedure NoCall_NoFinding;
    [Test] procedure SimpleEmptyCall_Reported;
    [Test] procedure FunctionResultAssign_Reported;
    [Test] procedure NonEmptyArgs_NotReported;
    [Test] procedure EmptyParensAfterComma_NotReported;
    [Test] procedure EmptyParensInString_NotReported;
    [Test] procedure EmptyParensInComment_NotReported;
    // Voll-Review 2026-09-12 (Blocker): der Ein-Treffer-Exit liess den
    // Kommentar-Zustand der Restzeile unverfolgt und verlor
    // Zweittreffer.
    [Test] procedure CommentOpenedAfterHit_FollowingLinesNotScanned;
    [Test] procedure TwoEmptyCallsOnOneLine_BothReported;
    [Test] procedure EmptyArgumentList_KindAndSeverity;
    // Posten 198: mehrzeiliger Kommentar-Zustand
    [Test] procedure CallThenMultiLineCommentOpened_NoSecondFinding;
    [Test] procedure CallThenParenStarOpened_NoSecondFinding;
    [Test] procedure CallAfterMultiLineCommentClose_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 198: mehrzeilige Kommentare ueber die Zeilengrenze --- }
//
// EmptyParensInComment behandelt nur EINZEILIGE // und {..}. Der
// Zeilenuebertrag von InBlockComm/InParenStarComm war unbelegt - und
// genau dort sitzt in verwandten Detektoren das Zustandsleck.
//
// An der gebauten Exe geprueft: FindEmptyArgLists sammelt je Zeile
// ALLE Spalten in eine Liste und steigt am Treffer NICHT aus. Der
// Detektor ist deshalb nicht betroffen - anders als
// uSuperfluousSemicolon, uGotoStatement und uGroupedDeclaration in
// derselben Charge. Diese Tests nageln das fest.

procedure TTestEmptyArgumentList.CallThenMultiLineCommentOpened_NoSecondFinding;
// Treffer, danach ein ueber zwei Zeilen offener Kommentar mit einem
// weiteren () darin. Vor wie nach der Ergaenzung 1 Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  Bar();  {'#13#10+
  '    Baz();'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkEmptyArgumentList),
      'das () im Blockkommentar ist kein Aufruf');
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.CallThenParenStarOpened_NoSecondFinding;
// Dasselbe fuer die (* *)-Form.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  Bar();  (*'#13#10+
  '    Baz();'#13#10+
  '  *)'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkEmptyArgumentList),
      'das () im (* *)-Kommentar ist kein Aufruf');
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.CallAfterMultiLineCommentClose_StillReported;
// Gegenrichtung: hinter dem Kommentarende zaehlt wieder Code.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  Bar(1);  {'#13#10+
  '    Notiz'#13#10+
  '  }'#13#10+
  '  Baz();'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkEmptyArgumentList),
      'nach dem Kommentarende wird wieder gemeldet');
  finally F.Free; end;
end;


procedure TTestEmptyArgumentList.NoCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.SimpleEmptyCall_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff();'#13#10 +              // <-- Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.FunctionResultAssign_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  X := MyFunc();'#13#10 +          // <-- Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.NonEmptyArgs_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''hello'');'#13#10 +
  '  DoStuff(1, 2, 3);'#13#10 +
  '  X := Func(A);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyParensAfterComma_NotReported;
// `(...)` ohne vorangehenden Identifier (z.B. leeres Tupel/Set, oder
// gleich am Zeilenanfang) ist KEIN leeres Argument-List.
const SRC =
  'unit t; implementation'#13#10 +
  'const Empty: TArray<Integer> = ();'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoStuff(1, , 2); end;';   // syntaktisch komisch, aber kein `()` nach Ident
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyParensInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  WriteLn(''Call MyProc() to start'');'#13#10 +  // String -> kein Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyParensInComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  '// call MyProc() somewhere'#13#10 +
  '{ also DoStuff() in this comment }'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.CommentOpenedAfterHit_FollowingLinesNotScanned;
// 'Init();  { abgeschaltet:' - der Treffer bei Init() beendete den
// Zeilenscan, das dahinter GEOEFFNETE {-Kommentar wurde nie
// registriert, und die auskommentierte Folgezeile 'Cleanup();' wurde
// als Code gemeldet. Erwartet: genau EIN Fund (Init), keiner fuer
// die auskommentierte Zeile.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Init();  { abgeschaltet:'#13#10 +
  '  Cleanup();'#13#10 +
  '  }'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkEmptyArgumentList),
    'die auskommentierte Folgezeile darf nicht mitgemeldet werden');
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.TwoEmptyCallsOnOneLine_BothReported;
// 'Foo(); Bar();' auf einer Zeile: der alte Exit nach dem ersten
// Treffer verlor den zweiten.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  A(); B();'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(2,
    TFindingHelper.Count(F, fkEmptyArgumentList),
    'beide leeren Argumentlisten derselben Zeile muessen melden');
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyArgumentList_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff(); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyArgumentList then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyArgumentList, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,             Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyArgumentList finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyArgumentList);

end.
