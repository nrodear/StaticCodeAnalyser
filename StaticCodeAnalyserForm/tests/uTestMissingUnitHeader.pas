unit uTestMissingUnitHeader;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingUnitHeader = class
  public
    [Test] procedure NoHeader_Reported;
    [Test] procedure WithLineComment_NotReported;
    [Test] procedure WithBlockComment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // AQL Hint-Tier 03.09.: eine Kommentar-Prosazeile wurde fuer die
    // unit-Klausel gehalten (pyscripter-Kopfvorlage).
    [Test] procedure CommentLineStartingWithUnit_NotTakenAsDecl;
    [Test] procedure ReallyNoHeader_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMissingUnitHeader.NoHeader_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingUnitHeader) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.CommentLineStartingWithUnit_NotTakenAsDecl;
// Erkennerfehler (AQL Hint-Tier 03.09., 2 von 125): LineIsUnitDecl
// prueste nur das Praefix "unit " und traf damit die Prosazeile
// " Unit Name: X" der pyscripter-Kopfvorlage. Der Detektor suchte
// danach DAHINTER nach einem Kopfkommentar - der beschreibende Kopf
// steht aber DAVOR und blieb unsichtbar.
// Belege: pyscripter frmProjectExplorer.pas:2, uEditAppIntfs.pas:2.
const SRC =
  '{-------------------------------------------------------------'#13#10 +
  ' Unit Name: frmTest'#13#10 +
  ' Author:    someone'#13#10 +
  ' Purpose:   Verwaltet die Testansicht der Anwendung.'#13#10 +
  '-------------------------------------------------------------}'#13#10 +
  'unit frmTest;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingUnitHeader),
    'Kopfvorlage mit Prosazeile "Unit Name:" ist ein beschriebener Kopf');
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.ReallyNoHeader_StillReported;
// WAECHTER: ohne jeden Kopf bleibt der Fund. Die verschaerfte
// Klausel-Erkennung darf die Regel nicht stumm machen.
const SRC =
  'unit frmLeer;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingUnitHeader),
    'ohne jeden Kopfkommentar bleibt der Fund');
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.WithLineComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  '// Diese Unit macht XYZ.'#13#10 +
  ''#13#10 +
  'interface'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingUnitHeader));
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.WithBlockComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  '{ Diese Unit macht XYZ }'#13#10 +
  ''#13#10 +
  'interface'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingUnitHeader));
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.Finding_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMissingUnitHeader then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingUnitHeader finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingUnitHeader);

end.
