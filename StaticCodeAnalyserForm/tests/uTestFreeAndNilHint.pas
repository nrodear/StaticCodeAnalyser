unit uTestFreeAndNilHint;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeAndNilHint = class
  public
    [Test] procedure FreeAlone_NoFinding;
    [Test] procedure FreeAndNilOnNextLine_Reported;
    [Test] procedure DifferentReceiver_NoFinding;
    // Voll-Review 2026-09-12 (Blocker): kein Blockkommentar-Tracking.
    [Test] procedure PatternInsideBlockComment_NoFinding;
    [Test] procedure FreeAndNilHint_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFreeAndNilHint.FreeAlone_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnNextLine_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.DifferentReceiver_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  A.Free;'#13#10 +
  '  B := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.PatternInsideBlockComment_NoFinding;
// Mehrzeilig auskommentierter Alt-Code lieferte vor dem Fix einen
// Fund - der Roh-Scan kannte keinen Blockkommentar-Zustand
// (Projekt-Invariante: Kommentare zaehlen NIE als Code-Use).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { Alte Version:'#13#10 +
  '  FConn.Free;'#13#10 +
  '  FConn := nil;'#13#10 +
  '  }'#13#10 +
  '  DoNew;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkFreeAndNilHint),
    'auskommentierter Alt-Code darf keinen FreeAndNil-Hinweis melden');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilHint_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkFreeAndNilHint then
      begin
        Assert.AreEqual<TFindingKind>(fkFreeAndNilHint, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFreeAndNilHint finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeAndNilHint);

end.
