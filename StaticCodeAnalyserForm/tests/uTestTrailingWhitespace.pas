unit uTestTrailingWhitespace;

// Tests fuer TTrailingWhitespaceDetector (file-scan).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTrailingWhitespace = class
  public
    [Test] procedure CleanLine_NoFinding;
    [Test] procedure TrailingSpace_Reported;
    [Test] procedure TrailingTab_Reported;
    [Test] procedure TrailingMixed_Reported;
    [Test] procedure EmptyLine_NoFinding;
    [Test] procedure TrailingWs_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTrailingWhitespace.CleanLine_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTrailingWhitespace));
  finally F.Free; end;
end;

procedure TTestTrailingWhitespace.TrailingSpace_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  '  DoStuff;   '#13#10 +            // drei trailing Spaces
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTrailingWhitespace));
  finally F.Free; end;
end;

procedure TTestTrailingWhitespace.TrailingTab_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  '  DoStuff;'#9#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    // Diese Zeile hat sowohl ein internes Tab NICHT (kein fkTabulationCharacter
    // erwartet) als auch trailing-Tab (fkTrailingWhitespace = 1). Tab steht
    // hinter dem ';', also ist die Zeile auch tab-trailing.
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTrailingWhitespace));
  finally F.Free; end;
end;

procedure TTestTrailingWhitespace.TrailingMixed_Reported;
const SRC =
  'unit t;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;  '#9'  '#13#10 +       // Space-Tab-Space-Space am Ende
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTrailingWhitespace));
  finally F.Free; end;
end;

procedure TTestTrailingWhitespace.EmptyLine_NoFinding;
// Reine Leerzeilen (Length=0) sind explizit kein Treffer - sonst wuerde
// jede Trennzeile zwischen Methoden gemeldet.
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTrailingWhitespace));
  finally F.Free; end;
end;

procedure TTestTrailingWhitespace.TrailingWs_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  '  A := 1;   '#13#10;
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTrailingWhitespace then
      begin
        Assert.AreEqual<TFindingKind>(fkTrailingWhitespace, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,              Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTrailingWhitespace finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTrailingWhitespace);

end.
