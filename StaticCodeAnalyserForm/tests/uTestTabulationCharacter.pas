unit uTestTabulationCharacter;

// Tests fuer TTabulationCharacterDetector (file-scan, ohne String/
// Kommentar-Awareness - SonarDelphi-Verhalten).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTabulationCharacter = class
  public
    [Test] procedure Tab_InIndentation_Reported;
    [Test] procedure Tab_InMiddle_Reported;
    [Test] procedure Tab_MultipleLines_OneFindingPerLine;
    [Test] procedure NoTab_Spaces_NoFinding;
    [Test] procedure Tab_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTabulationCharacter.Tab_InIndentation_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  #9'DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTabulationCharacter));
  finally F.Free; end;
end;

procedure TTestTabulationCharacter.Tab_InMiddle_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'var A'#9'B : Integer;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTabulationCharacter));
  finally F.Free; end;
end;

procedure TTestTabulationCharacter.Tab_MultipleLines_OneFindingPerLine;
// Drei Zeilen mit Tab -> drei Findings (eins pro Zeile, auch wenn pro
// Zeile mehrere Tabs vorkommen).
const SRC =
  'unit t; implementation'#13#10 +
  #9'A := 1;'#13#10 +
  #9'B := 2;'#13#10 +
  #9#9'C := 3;'#13#10;       // zwei Tabs in einer Zeile = 1 Finding
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(3, TFindingHelper.Count(F, fkTabulationCharacter));
  finally F.Free; end;
end;

procedure TTestTabulationCharacter.NoTab_Spaces_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTabulationCharacter));
  finally F.Free; end;
end;

procedure TTestTabulationCharacter.Tab_KindAndSeverity;
const SRC = 'unit t; implementation'#13#10 + #9'A := 1;'#13#10;
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkTabulationCharacter));
    for Fnd in F do
      if Fnd.Kind = fkTabulationCharacter then
      begin
        Assert.AreEqual<TFindingKind>(fkTabulationCharacter, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint, Fnd.Severity);
        Exit;
      end;
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTabulationCharacter);

end.
