unit uTestFreeWithoutNil;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeWithoutNil = class
  public
    [Test] procedure FreeWithoutNil_Reported;
    [Test] procedure FreeAndNil_NotReported;
    [Test] procedure FreeAtMethodEnd_NotReported;
    [Test] procedure FreeFollowedByNilAssign_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFreeWithoutNil.FreeWithoutNil_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  WriteLn(''after free'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFreeWithoutNil) >= 1);
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAndNil_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeAtMethodEnd_NotReported;
// Free als letzte Anweisung -> kein Folge-Use moeglich -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.FreeFollowedByNilAssign_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L := nil;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkFreeWithoutNil));
  finally F.Free; end;
end;

procedure TTestFreeWithoutNil.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  WriteLn(''after'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkFreeWithoutNil then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkFreeWithoutNil finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeWithoutNil);

end.
