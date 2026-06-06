unit uTestCharToCharPointerCast;

// Tests fuer den TCharToCharPointerCastDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCharToCharPointerCast = class
  public
    [Test] procedure PCharSingleCharLiteral_Reported;
    [Test] procedure PWideCharSingleCharLiteral_Reported;
    [Test] procedure PCharCharOrdinal_Reported;
    [Test] procedure PCharHexOrdinal_Reported;
    [Test] procedure PCharChrCall_Reported;

    [Test] procedure PCharMultiCharLiteral_NoFinding;
    [Test] procedure PCharStringVariable_NoFinding;
    [Test] procedure UnrelatedCall_NoFinding;

    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCharToCharPointerCast.PCharSingleCharLiteral_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(''A''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.PWideCharSingleCharLiteral_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PWideChar;'#13#10 +
  'begin p := PWideChar(''X''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.PCharCharOrdinal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(#65); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.PCharHexOrdinal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(#$41); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.PCharChrCall_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(n: Integer);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(Chr(n)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.PCharMultiCharLiteral_NoFinding;
// 'AB' ist String-Literal, kein Char -> legitimer Cast.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(''AB''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.PCharStringVariable_NoFinding;
// PChar(variable) - ohne Typ-Info kein Finding (false-negative bewusst).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(s); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.UnrelatedCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoSomething(42); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCharToCharPointerCast));
  finally F.Free; end;
end;

procedure TTestCharToCharPointerCast.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var p: PChar;'#13#10 +
  'begin p := PChar(''A''); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCharToCharPointerCast then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkCharToCharPointerCast finding expected');
    Assert.AreEqual(fkCharToCharPointerCast, Hit.Kind);
    Assert.AreEqual(lsError,                 Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCharToCharPointerCast);

end.
