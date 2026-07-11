unit uTestMultipleExit;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMultipleExit = class
  public
    [Test] procedure SevenExits_Reported;
    // Schwelle 2026-07-11 von 3 auf 6 angehoben: 4-6 Exits sind idiomatische
    // Guard-Ketten (kein Smell), erst > 6 wird gemeldet.
    [Test] procedure SixExits_NotReported;
    [Test] procedure ThreeExits_NotReported;
    [Test] procedure NoExits_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMultipleExit.SevenExits_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  '  if D then Exit;'#13#10 +
  '  if E then Exit;'#13#10 +
  '  if F then Exit;'#13#10 +
  '  if G then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMultipleExit) >= 1,
    '7 Exits (> Schwelle 6) muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMultipleExit.SixExits_NotReported;
// Grenzfall der 2026-07-11-Schwelle: 6 Exits sind noch idiomatische Guard-Kette,
// KEIN Smell. Gegenstueck zu SevenExits_Reported.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  '  if D then Exit;'#13#10 +
  '  if E then Exit;'#13#10 +
  '  if F then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMultipleExit),
    '6 Exits sind eine idiomatische Guard-Kette, kein Smell');
  finally F.Free; end;
end;

procedure TTestMultipleExit.ThreeExits_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMultipleExit));
  finally F.Free; end;
end;

procedure TTestMultipleExit.NoExits_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMultipleExit));
  finally F.Free; end;
end;

procedure TTestMultipleExit.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  if A then Exit;'#13#10 +
  '  if B then Exit;'#13#10 +
  '  if C then Exit;'#13#10 +
  '  if D then Exit;'#13#10 +
  '  if E then Exit;'#13#10 +
  '  if F then Exit;'#13#10 +
  '  if G then Exit;'#13#10 +
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
      if Fnd.Kind = fkMultipleExit then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMultipleExit finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMultipleExit);

end.
