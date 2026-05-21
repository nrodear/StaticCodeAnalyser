unit uTestMissingFinally;

// Tests fuer TMissingFinallyDetector. Pattern: Object .Create + try/except
// ABER kein try/finally rund um den Free.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingFinally = class
  public
    [Test] procedure CreateWithoutTryFinally_Reported;
    [Test] procedure CreateWithTryFinally_NotReported;
    [Test] procedure NoCreate_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingFinally.CreateWithoutTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''x'');'#13#10 +
  '  except'#13#10 +
  '    Log(''oops'');'#13#10 +
  '  end;'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingFinally.CreateWithTryFinally_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    L.Add(''x'');'#13#10 +
  '  finally'#13#10 +
  '    L.Free;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinally.NoCreate_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''nothing to clean up'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinally.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  try L.Add(''x''); except Log(''oops''); end;'#13#10 +
  '  L.Free;'#13#10 +
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
      if Fnd.Kind = fkMissingFinally then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingFinally finding expected');
    Assert.AreEqual(fkMissingFinally, Hit.Kind);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingFinally);

end.
