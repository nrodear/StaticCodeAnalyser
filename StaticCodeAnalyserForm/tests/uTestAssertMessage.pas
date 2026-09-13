unit uTestAssertMessage;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAssertMessage = class
  public
    [Test] procedure AssertWithMessage_NoFinding;
    [Test] procedure AssertWithoutMessage_Reported;
    [Test] procedure NestedFunctionCall_NoFinding;
    [Test] procedure NotACallToAssert_NoFinding;
    [Test] procedure AssertMessage_KindAndSeverity;
    // Minor 227: Kommas in Kommentaren sind keine Argumenttrenner
    [Test] procedure CommaInsideBlockComment_StillReported;
    [Test] procedure CommaInsideParenStarComment_StillReported;
    [Test] procedure BraceInsideStringLiteral_RealCommaStillCounts;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAssertMessage.AssertWithMessage_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Assert(Count > 0, ''Items must not be empty'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.AssertWithoutMessage_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Assert(Count > 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.NestedFunctionCall_NoFinding;
// Verschachtelter Aufruf: das innere Komma in Max(A, B) gehoert nicht
// zur Assert-Argumentliste auf Top-Level. Trotzdem soll der Assert
// gemeldet werden, falls nur ein Arg vorhanden. Hier ist 2-Arg-Assert
// also kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Assert(Count > 0, Format(''bad: %d'', [Count]));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.NotACallToAssert_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var AssertX: Integer;'#13#10 +
  '  AssertX := 1;'#13#10 +
  '  MyAssert(X);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAssertMessage));
  finally F.Free; end;
end;

procedure TTestAssertMessage.AssertMessage_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; Assert(X); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkAssertMessage then
      begin
        Assert.AreEqual<TFindingKind>(fkAssertMessage, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,         Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkAssertMessage finding');
  finally F.Free; end;
end;

{ --- Minor 227: Kommentare im Klammer-Inhalt ---------------------- }
//
// Der AEUSSERE Scanner kennt //, { } und (* *) laengst. Der Scan des
// Klammer-Inhalts kannte nur String-Literale - ein Komma in einem
// Kommentar galt als Argumenttrenner, der Detektor hielt eine Meldung
// fuer vorhanden und schwieg.
//
// Korpuswirkung: KEINE. Die einzige Fundstelle, die mein Suchmuster
// zunaechst lieferte (issrc Shared.CommonFunc.Test), hat die Kommas in
// STRING-Literalen, nicht in einem Kommentar - dort greift die
// Aenderung nicht. Die Haertung wirkt vorbeugend.
// Alle drei am gebauten Stand verprobt.

procedure TTestAssertMessage.CommaInsideBlockComment_StillReported;
// Am gebauten Stand nachgemessen: vor dem Fix 0 Funde, danach 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  Assert(X > 0 { a, b });'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAssertMessage),
    'das Komma steht im Kommentar - es gibt keine Meldung');
  finally F.Free; end;
end;

procedure TTestAssertMessage.CommaInsideParenStarComment_StillReported;
// Die zweite Kommentarform. Sie ist der heiklere Fall: '(*' beginnt
// mit '(' und wurde vom Klammer-Zaehler als geoeffnete Klammer
// gezaehlt - der Kommentar-Zweig MUSS deshalb vor dem Klammer-Zweig
// stehen, sonst geht die Tiefe verloren.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  Assert(X > 0 (* a, b *));'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkAssertMessage),
    'auch (* *) ist ein Kommentar, keine Klammer');
  finally F.Free; end;
end;

procedure TTestAssertMessage.BraceInsideStringLiteral_RealCommaStillCounts;
// DER WAECHTER GEGEN MEINEN EIGENEN FIX: eine geschweifte Klammer in
// einem STRING-Literal ist kein Kommentaranfang. Wuerde der neue
// Kommentar-Zweig sie dafuer halten, uebersprunge er bis zur
// schliessenden Klammer - und das ECHTE Komma dahinter, das die
// Meldung einleitet, ginge verloren. Dann meldete der Detektor einen
// Assert ohne Meldung, der eine hat.
//
// Die Form stammt aus dem Korpus (issrc Shared.CommonFunc.Test:128),
// um eine Meldung ergaenzt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure P;'#13#10 +
  'begin'#13#10 +
  '  Assert(ConstPos('','', ''{a,b}'') = 0, ''muss null sein'');'#13#10 +
  'end;'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkAssertMessage),
    'die Meldung hinter dem String-Literal zaehlt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAssertMessage);

end.
