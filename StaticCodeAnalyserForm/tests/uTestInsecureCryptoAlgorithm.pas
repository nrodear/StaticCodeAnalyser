unit uTestInsecureCryptoAlgorithm;

// Tests fuer TInsecureCryptoAlgorithmDetector (SCA162).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInsecureCryptoAlgorithm = class
  public
    // ---- Positive: Algorithmus-Token als Stringliteral -------------------
    [Test] procedure InsecureCrypto_MD5Literal_Reported;
    [Test] procedure InsecureCrypto_SHA1Literal_Reported;
    [Test] procedure InsecureCrypto_DESLiteral_Reported;
    [Test] procedure InsecureCrypto_RC4Literal_Reported;
    [Test] procedure InsecureCrypto_TLS10Literal_Reported;
    [Test] procedure InsecureCrypto_SSLv3Literal_Reported;

    // ---- Positive: Klassen-Wrapper ---------------------------------------
    [Test] procedure InsecureCrypto_THashMD5Call_Reported;
    [Test] procedure InsecureCrypto_TIdHashSHA1Call_Reported;

    // ---- Negative: starke Algorithmen -----------------------------------
    [Test] procedure InsecureCrypto_SHA256Literal_NoFinding;
    [Test] procedure InsecureCrypto_AESLiteral_NoFinding;
    [Test] procedure InsecureCrypto_TLS13Literal_NoFinding;

    // ---- Negative: Wortgrenz-FP-Schutz -----------------------------------
    [Test] procedure InsecureCrypto_MD5HashIdentifier_NoFinding;
    [Test] procedure InsecureCrypto_SHA1024Identifier_NoFinding;
    // ---- Negative: Natur-Sprach-Kontext (FP-Regression) -----------------
    [Test] procedure InsecureCrypto_DesInGermanSentence_NoFinding;
    [Test] procedure InsecureCrypto_DesInLongerString_NoFinding;
    // ---- Negative: Bindestrich-Verbund (Real-World-FP-Audit 2026-07-12,
    //      FP-Klasse 'hyphen-compound-word-boundary') --------------------
    [Test] procedure InsecureCrypto_ContentMD5Header_NoFinding;
    [Test] procedure InsecureCrypto_CramMD5Mechanism_NoFinding;
    [Test] procedure InsecureCrypto_CramSHA1Mechanism_NoFinding;
    // ---- Positive-Gegenprobe: Suffix-Bindestrich bleibt Treffer ----------
    [Test] procedure InsecureCrypto_DesCbcSuffix_Reported;
    [Test] procedure InsecureCrypto_MD5Standalone_StillReported;

    // ---- Finding-Inhalt --------------------------------------------------
    [Test] procedure InsecureCrypto_Finding_KindAndSeverity;
    [Test] procedure InsecureCrypto_Dedup_OneFindingPerLine;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_MD5Literal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''MD5''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''MD5'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_SHA1Literal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''SHA1''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''SHA1'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_DESLiteral_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''DES''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''DES'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_RC4Literal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''RC4''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''RC4'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_TLS10Literal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: string;'#13#10 +
  'begin v := ''TLS1.0''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''TLS1.0'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_SSLv3Literal_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: string;'#13#10 +
  'begin v := ''SSLv3''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''SSLv3'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_THashMD5Call_Reported;
// THashMD5.GetHashString -> Klassen-Wrapper-Match
const SRC =
  'unit t; implementation'#13#10 +
  'uses System.Hash;'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin s := THashMD5.GetHashString(''hello''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'THashMD5.GetHashString'),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_TIdHashSHA1Call_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var h: TIdHashSHA1;'#13#10 +
  'begin h := TIdHashSHA1.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      'genau 1 InsecureCrypto-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'TIdHashSHA1.Create'),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_SHA256Literal_NoFinding;
// SHA256 ist nicht in der Liste - kein Hit.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''SHA256''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_AESLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''AES-256-CBC''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_TLS13Literal_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var v: string;'#13#10 +
  'begin v := ''TLS1.3''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_MD5HashIdentifier_NoFinding;
// 'MD5Hash' als Variable: Right-Boundary 'H' -> kein Wortgrenz-Match.
// (Klassennamen wie THashMD5 sind separate Liste mit Substring-Match.)
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var MD5Hash: string;'#13#10 +
  'begin MD5Hash := ''hello''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_SHA1024Identifier_NoFinding;
// 'SHA1024' enthaelt 'sha1' aber Right-Boundary = '0' (digit, ident-char) ->
// kein Hit.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var SHA1024: Integer;'#13#10 +
  'begin SHA1024 := 1; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_DesInGermanSentence_NoFinding;
// FP-Regression aus Real-World-Code (uLocalization.pas Z.155):
//   GDeMap.Add('Free is outside the protecting finally block',
//              'Free liegt außerhalb des schützenden finally-Blocks');
// Das Wort 'des' (deutsch) zwischen zwei Spaces darf nicht als
// Krypto-Algorithmus DES geflagged werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure SetupMap;'#13#10 +
  'begin'#13#10 +
  '  Map.Add(''Free is outside the protecting finally block'','#13#10 +
  '          ''Free liegt au'#$DF'erhalb des sch'#$FC'tzenden finally-Blocks'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
        'Deutsches ''des'' in Satz-Mitte darf nicht als DES-Krypto geflagged sein');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_DesInLongerString_NoFinding;
// Englischer Satz mit ' des ' (z.B. franzoesischer Lehn-Begriff oder
// abkuerzung). Trotzdem natuersprachlich, nicht Krypto.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  msg := ''The handling des operations was deprecated'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_ContentMD5Header_NoFinding;
// FP-Regression (Real-World-FP-Audit 2026-07-12, 'hyphen-compound-word-
// boundary'): Alcinoe.HTTP.pas Z.829 / .HttpSys.pas Z.309:
//   Result := 'Content-MD5';
// 'Content-MD5' ist ein HTTP-Header-Name, kein Krypto-Use. Das 'MD5' steht
// als Ende eines Bindestrich-Verbundtokens - der Bindestrich davor darf
// nicht als gueltige Wortgrenze zaehlen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var h: string;'#13#10 +
  'begin h := ''Content-MD5''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
        '''Content-MD5''-Header darf nicht als MD5-Krypto geflagged sein');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_CramMD5Mechanism_NoFinding;
// FP-Regression (Real-World-FP-Audit 2026-07-12): IdSASL_CRAM_MD5.pas Z.108:
//   result := 'CRAM-MD5';
// SASL-Mechanismus-Name (Bindestrich vor 'MD5') - kein Krypto-Use.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var m: string;'#13#10 +
  'begin m := ''CRAM-MD5''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
        '''CRAM-MD5''-SASL-Mechanismus darf nicht als MD5-Krypto geflagged sein');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_CramSHA1Mechanism_NoFinding;
// FP-Regression (Real-World-FP-Audit 2026-07-12): IdSASL_CRAM_SHA1.pas Z.100:
//   result := 'CRAM-SHA1';
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var m: string;'#13#10 +
  'begin m := ''CRAM-SHA1''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
        '''CRAM-SHA1''-SASL-Mechanismus darf nicht als SHA1-Krypto geflagged sein');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_DesCbcSuffix_Reported;
// TP-Gegenprobe: nur die PRAEFIX-Richtung ('wort-ALGO') wird unterdrueckt.
// Ein Bindestrich NACH dem Namen ('ALGO-wort') bleibt bewusst ein Treffer -
// 'DES-CBC' ist eine echte Cipher-Suite-/Modus-Angabe (Weak-Crypto).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''DES-CBC''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
      '''DES-CBC'' (Suffix-Bindestrich) muss weiterhin als DES-Krypto gefunden werden');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, '''DES-CBC'''),
      TFindingHelper.FirstOf(F, fkInsecureCryptoAlgorithm).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_MD5Standalone_StillReported;
// TP-Gegenprobe: ein freistehendes 'MD5' (kein Bindestrich-Verbund) bleibt
// unveraendert ein Treffer - der Fix schliesst NUR die Bindestrich-Klasse.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''MD5''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
        'freistehendes ''MD5'' muss weiterhin gefunden werden');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var algo: string;'#13#10 +
  'begin algo := ''MD5''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkInsecureCryptoAlgorithm then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.AreEqual(fkInsecureCryptoAlgorithm, Hit.Kind);
    Assert.AreEqual(lsWarning, Hit.Severity);
    Assert.Contains(LowerCase(Hit.MissingVar), 'md5');
  finally F.Free; end;
end;

procedure TTestInsecureCryptoAlgorithm.InsecureCrypto_Dedup_OneFindingPerLine;
// 'Hash := THashMD5.Create' triggert sowohl nkAssign.TypeRef-Match
// (Klassen-Wrapper) als auch nkCall.Name-Match (.Create-Call). Dedup soll
// trotzdem nur einen Finding pro Zeile/Hit liefern.
const SRC =
  'unit t; implementation'#13#10 +
  'uses System.Hash;'#13#10 +
  'procedure Foo;'#13#10 +
  'var Hash: THashMD5;'#13#10 +
  'begin Hash := THashMD5.Create; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInsecureCryptoAlgorithm);

end.
