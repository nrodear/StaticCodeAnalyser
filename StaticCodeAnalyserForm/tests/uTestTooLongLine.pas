unit uTestTooLongLine;

// Tests fuer TTooLongLineDetector (file-scan).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTooLongLine = class
  public
    [Test] procedure ShortLines_NoFinding;
    [Test] procedure ExactlyAtLimit_NoFinding;
    [Test] procedure OverLimit_Reported;
    [Test] procedure MultipleOverLimit_AllReported;
    [Test] procedure TooLongLine_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestTooLongLine.ShortLines_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.ExactlyAtLimit_NoFinding;
// MAX_LINE_LEN = 120 -> 120 Zeichen sind OK, 121 sind Treffer.
var
  Line : string;
  SRC  : string;
  F    : TObjectList<TLeakFinding>;
begin
  Line := 'unit t; implementation' + #13#10;
  // Genau 120 Zeichen
  Line := Line + StringOfChar('A', 120) + #13#10;
  SRC := Line;
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.OverLimit_Reported;
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  // 121 Zeichen = ueber Schwelle
  SRC := 'unit t; implementation' + #13#10 + StringOfChar('A', 121) + #13#10;
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.MultipleOverLimit_AllReported;
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
begin
  SRC := 'unit t; implementation' + #13#10 +
         StringOfChar('A', 150) + #13#10 +
         '  short'                + #13#10 +
         StringOfChar('B', 200) + #13#10;
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkTooLongLine));
  finally F.Free; end;
end;

procedure TTestTooLongLine.TooLongLine_KindAndSeverity;
var
  SRC : string;
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  SRC := 'unit t; implementation' + #13#10 + StringOfChar('X', 130) + #13#10;
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkTooLongLine then
      begin
        Assert.AreEqual<TFindingKind>(fkTooLongLine, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,       Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTooLongLine finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTooLongLine);

end.
