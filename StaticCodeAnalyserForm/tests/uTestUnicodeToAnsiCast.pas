unit uTestUnicodeToAnsiCast;

// Tests fuer den TUnicodeToAnsiCastDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnicodeToAnsiCast = class
  public
    [Test] procedure AnsiStringCast_Reported;
    [Test] procedure UTF8StringCast_Reported;
    [Test] procedure RawByteStringCast_Reported;
    [Test] procedure ShortStringCast_Reported;
    [Test] procedure CaseInsensitive_Reported;

    [Test] procedure StringCast_NoFinding;
    [Test] procedure UnrelatedCall_NoFinding;
    [Test] procedure EmptyStringLiteralCast_NoFinding;

    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnicodeToAnsiCast.AnsiStringCast_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(u: UnicodeString);'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(u); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.UTF8StringCast_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(u: UnicodeString);'#13#10 +
  'var s: UTF8String;'#13#10 +
  'begin s := UTF8String(u); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.RawByteStringCast_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'var r: RawByteString;'#13#10 +
  'begin r := RawByteString(s); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.ShortStringCast_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(s: string);'#13#10 +
  'var sh: ShortString;'#13#10 +
  'begin sh := ShortString(s); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.CaseInsensitive_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(u: string);'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := ANSISTRING(u); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.StringCast_NoFinding;
// `string(x)` Cast ist UnicodeString in modernem Delphi - kein Datenverlust.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: TBytes);'#13#10 +
  'var s: string;'#13#10 +
  'begin s := string(b); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.UnrelatedCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoSomething(42); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.EmptyStringLiteralCast_NoFinding;
// `AnsiString('')` - kein Datenverlust moeglich, leerer String.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(''''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(u: UnicodeString);'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(u); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnicodeToAnsiCast then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkUnicodeToAnsiCast finding expected');
    Assert.AreEqual(fkUnicodeToAnsiCast, Hit.Kind);
    Assert.AreEqual(lsWarning,           Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnicodeToAnsiCast);

end.
