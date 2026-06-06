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
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

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

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyBlock);

end.
