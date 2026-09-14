unit uTestSuperfluousSemicolon;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSuperfluousSemicolon = class
  public
    [Test] procedure NormalCode_NoFinding;
    [Test] procedure DoubleSemi_Reported;
    [Test] procedure SemiSpaceSemi_Reported;
    [Test] procedure SemiInString_NotReported;
    [Test] procedure SuperfluousSemicolon_KindAndSeverity;
    // Posten 209: Zustandsleck am Treffer
    [Test] procedure CommentOpenedAfterHit_NoSecondFinding;
    [Test] procedure ParenStarOpenedAfterHit_NoSecondFinding;
    [Test] procedure SemiInMultiLineComment_NoFinding;
    [Test] procedure HitAfterCommentClose_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 209: der Kommentar-Zustand ueber Zeilengrenzen -------- }
//
// FindDoubleSemi stieg am Treffer per Exit aus und liess ein dahinter
// GEOEFFNETES '{' oder '(*' unverfolgt. Der Caller hielt die
// Folgezeilen fuer Code und meldete das auskommentierte ";;" mit.
//
// An der gebauten Exe gemessen: die erste Fixture unten ergab 2 Funde
// statt 1; dieselbe Datei ohne Treffer vor dem "{" ergab richtig 0.
// Gleiche Fehlerklasse wie in uWithStatement und uReversedForRange.

procedure TTestSuperfluousSemicolon.CommentOpenedAfterHit_NoSecondFinding;
// DER NACHWEIS. Heute 2 Funde, nach dem Fix 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y: Integer;'#13#10+
  'begin'#13#10+
  '  x := 1;;  {'#13#10+
  '    y := 2;;'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkSuperfluousSemicolon),
      'das ;; im Blockkommentar ist kein Code');
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.ParenStarOpenedAfterHit_NoSecondFinding;
// Dasselbe fuer die (* *)-Form - eigener Zustand, eigener Pfad.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y: Integer;'#13#10+
  'begin'#13#10+
  '  x := 1;;  (*'#13#10+
  '    y := 2;;'#13#10+
  '  *)'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkSuperfluousSemicolon),
      'das ;; im (* *)-Kommentar ist kein Code');
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SemiInMultiLineComment_NoFinding;
// Kein Treffer vor dem Kommentar: heute schon richtig 0, muss 0
// bleiben. Zeigt, dass der Fehler am TREFFER hing, nicht am
// Kommentar-Scanner selbst.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y: Integer;'#13#10+
  'begin'#13#10+
  '  x := 1;  {'#13#10+
  '    y := 2;;'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkSuperfluousSemicolon),
      'ohne vorangehenden Treffer war der Kommentar schon immer dicht');
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.HitAfterCommentClose_StillReported;
// Die Gegenrichtung: nach dem Kommentarende zaehlt wieder Code.
// Wird rot, wenn jemand den Scanner zu frueh stillstellt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y: Integer;'#13#10+
  'begin'#13#10+
  '  x := 1;  {Notiz}'#13#10+
  '  y := 2;;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkSuperfluousSemicolon),
      'hinter dem geschlossenen Kommentar zaehlt der Code wieder');
  finally F.Free; end;
end;


procedure TTestSuperfluousSemicolon.NormalCode_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.DoubleSemi_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff;; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SemiSpaceSemi_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff;  ;  end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SemiInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; WriteLn('';;''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSuperfluousSemicolon));
  finally F.Free; end;
end;

procedure TTestSuperfluousSemicolon.SuperfluousSemicolon_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; DoStuff;; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkSuperfluousSemicolon then
      begin
        Assert.AreEqual<TFindingKind>(fkSuperfluousSemicolon, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkSuperfluousSemicolon finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSuperfluousSemicolon);

end.
