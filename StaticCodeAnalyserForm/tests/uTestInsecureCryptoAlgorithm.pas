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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkInsecureCryptoAlgorithm) >= 1);
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm),
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
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
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkInsecureCryptoAlgorithm));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInsecureCryptoAlgorithm);

end.
