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
    [Test] procedure UTF8StringCast_NotReported;
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
    // --- Waechter VOR dem B2-Umbau (2026-08-17) ---
    // Alle Tests darueber benutzen einen RHS aus GENAU EINEM Cast, der auf
    // ')' endet. Damit koennen sie nicht sehen, ob ein kuenftiger
    // Cast-Zerleger den Operanden nur dann findet, wenn der Cast den ganzen
    // Ausdruck ausmacht. Die drei hier haben Trailing-Tokens.
    [Test] procedure CastWithTrailingConcat_NotReported;
    [Test] procedure TwoCastsConcatenated_NotReported;
    [Test] procedure LiteralCastWithTrailingConcat_NotReported;
    // Zeigerfeld einer Variant-Sicht ist ein Typ-Pun (2026-09-04).
    [Test] procedure VariantPointerField_NotReported;
    [Test] procedure EchtesStringFeld_StillReported;
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

procedure TTestUnicodeToAnsiCast.UTF8StringCast_NotReported;
// FP-Audit Stufe 2 (2026-08-16): UTF8String ist 'type AnsiString(CP_UTF8)'.
// Der Compiler erzeugt fuer UTF8String(u) exakt
// System._UStrToLStr(dest, src, CP_UTF8) - denselben Code wie das von der
// Meldung geforderte UTF8Encode. Es geht kein Zeichen verloren, die
// Behauptung der Regel traf hier nie zu (9 von 26 Sample-FP; korpusweit
// 47 Funde, keiner mit 8-bit-Operand).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(u: UnicodeString);'#13#10 +
  'var s: UTF8String;'#13#10 +
  'begin s := UTF8String(u); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'UTF8String(u) ist verlustfrei - identischer Code wie UTF8Encode(u)');
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
// ============================================================
// Waechter VOR dem B2-Umbau (2026-08-17)
//
// Der Detektor laeuft ueber nkAssign.TypeRef, und TypeRef ist der GESAMTE
// rechte Ausdruck inklusive '+'-Verkettungen (uParser2.pas:2909). Der
// Bestands-Zerleger ExtractCastOperand nimmt deshalb die ERSTE '(' bis zu
// ihrem balancierten Partner und ignoriert, was dahinter steht
// (uUnicodeToAnsiCast.pas:158, :189).
//
// Ein Zerleger, der stattdessen verlangt, dass der Cast den GANZEN Ausdruck
// ausmacht ('letztes Zeichen ist )'), liefert hier einen leeren Operanden -
// und ein leerer Operand passiert weder IsAsciiStringLiteral (:204) noch
// OperandIsAsciiSafe (:221). Die Regel wuerde also FUNDE GEWINNEN.
//
// Die sieben Cast-Tests darueber koennen das nicht sehen: sie benutzen alle
// einen RHS aus genau einem Cast, der auf ')' endet. Diese drei hier sind
// der fehlende Waechter. Am gebauten Stand vom 17.08. gemessen: 0 Funde.
// ============================================================

procedure TTestUnicodeToAnsiCast.CastWithTrailingConcat_NotReported;
// Protokoll-/Logging-Idiom (Indy, Alcinoe, mORMot): Cast mit ASCII-sicherem
// Operanden, danach folgt noch etwas im Ausdruck.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(N: Integer);'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(IntToStr(N)) + '';''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'IntToStr ist ASCII-sicher - ein Trailing-Ausdruck aendert daran nichts');
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.TwoCastsConcatenated_NotReported;
// Haerter: die LETZTE ')' des Ausdrucks schliesst nicht die ERSTE '('.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B: Integer);'#13#10 +
  'var s: AnsiString;'#13#10 +
  'begin s := AnsiString(IntToStr(A)) + AnsiString(IntToStr(B)); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'beide Operanden sind ASCII-sicher - die Klammerbilanz des Gesamtausdrucks' +
    ' darf keine Rolle spielen');
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.LiteralCastWithTrailingConcat_NotReported;
// Dieselbe Falle fuer den Literal-Pfad: die Apostrophe des Operanden
// muessen erhalten bleiben, sonst faellt IsAsciiStringLiteral durch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin a := AnsiString(''literal'') + '';''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'ASCII-Literal bleibt ASCII-Literal, auch mit Trailing-Ausdruck');
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.VariantPointerField_NotReported;
// Vollzaehlung 04.09.: 11 der 482 Korpusfunde casten ein ZEIGERFELD
// einer Variant-Record-Sicht. Das Feld haelt eine bereits vorhandene
// AnsiString-Referenz; der Cast fasst deren Referenzzaehlung an und
// wandelt nichts - Codepage-Verlust ist ausgeschlossen.
// mormot.core.rtti.pas:6299 sagt es im Code selbst: "copy AnsiString
// with reference counting".
// Ohne den Fix ROT mit 2 Funden (beide Seiten der Zuweisung).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(var Dest, Source: TVarData);'#13#10 +
  'begin'#13#10 +
  '  RawByteString(Dest.VAny) := RawByteString(Source.VAny);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'Zeigerfeld-Cast wandelt nichts - kein Zeichenverlust moeglich');
  finally F.Free; end;
end;

procedure TTestUnicodeToAnsiCast.EchtesStringFeld_StillReported;
// GEGENPROBE: das Gate darf NUR die beiden gemessenen Zeigerfelder
// treffen. Ein normales Feld mit V-Praefix ist ein gewoehnlicher
// Operand und bleibt ein Fund - sonst waere aus dem Gate eine
// Namensheuristik ueber das 'V' geworden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const R: TMeinRecord);'#13#10 +
  'var a: AnsiString;'#13#10 +
  'begin'#13#10 +
  '  a := AnsiString(R.VText);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkUnicodeToAnsiCast),
    'nur .VAny und .VAnsiString sind gemessen - sonst nichts');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnicodeToAnsiCast);

end.
