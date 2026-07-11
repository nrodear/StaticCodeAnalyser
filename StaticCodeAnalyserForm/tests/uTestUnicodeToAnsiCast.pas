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
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure AsciiStringLiteralCast_NotReported;
    [Test] procedure MemberTextCast_Reported;
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast));
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


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestUnicodeToAnsiCast.AsciiStringLiteralCast_NotReported;
// Real-World-FP-Audit 2026-07-10 (Alcinoe.Cipher.pas:1175):
// AnsiString('<reines ASCII base64url-Literal>') kann keinen Codepunkt >127
// verlieren -> KEIN Datenverlust, kein Bug. IsAsciiStringLiteral unterdrueckt
// den reinen ASCII-String-Literal-Operanden (Operand beginnt UND endet mit ').
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(''eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'ASCII-only string literal cast cannot drop any character - must not be flagged');
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.MemberTextCast_Reported;
// tp_examples_must_stay (Alcinoe ALNNTPClient Unit1.pas:176):
// AnsiString(Edit.Text) - TEdit.Text ist UnicodeString -> echter, verlust-
// behafteter Cast. Der Member-Zugriff ist weder ASCII-Literal noch ein
// ASCII-safe-Praefix, die neuen Guards duerfen ihn NICHT unterdruecken.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Edit: TEdit);'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(Edit.Text); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnicodeToAnsiCast) >= 1,
    'Unicode member (.Text) -> AnsiString is a genuine lossy cast - must still fire');
  finally F.Free; end;
end;
initialization
  TDUnitX.RegisterTestFixture(TTestUnicodeToAnsiCast);

end.
