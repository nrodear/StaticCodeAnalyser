unit uTestPointerArithmeticOnString;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPointerArithmeticOnString = class
  public
    [Test] procedure PCharPlusOffsetWithoutCheck_Reported;
    [Test] procedure PAnsiCharMinusOffsetWithoutCheck_Reported;
    [Test] procedure PCharWithEmptyCheck_NotReported;
    [Test] procedure PCharWithLengthCheck_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPointerArithmeticOnString.PCharPlusOffsetWithoutCheck_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  p := PChar(s) + 5;'#13#10 +
  '  DoStuff(p);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerArithmeticOnString) >= 1);
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PAnsiCharMinusOffsetWithoutCheck_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const a: AnsiString);'#13#10 +
  'var p: PAnsiChar;'#13#10 +
  'begin'#13#10 +
  '  p := PAnsiChar(a) - 1;'#13#10 +
  '  DoStuff(p);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerArithmeticOnString) >= 1);
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PCharWithEmptyCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if s <> '''' then'#13#10 +
  '    p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerArithmeticOnString));
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PCharWithLengthCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if Length(s) >= 6 then'#13#10 +
  '    p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerArithmeticOnString));
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  p := PChar(s) + 1;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkPointerArithmeticOnString then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkPointerArithmeticOnString finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPointerArithmeticOnString);

end.
