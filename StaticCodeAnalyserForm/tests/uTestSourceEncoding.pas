unit uTestSourceEncoding;

// Tests fuer die Encoding-/Unicode-Sicherheit-Detektor-Familie (SCA185-192,
// uSourceEncoding + ComputeFileEncodingInfo in uFileTextCache).
//
// Zwei Ebenen:
//   * ComputeFileEncodingInfo(TBytes) - die reine Byte-Analyse (BOM-Sniff,
//     strikter RFC-3629-UTF-8-Validator, Bidi-/Zero-Width-/NUL-Erkennung).
//     Deterministisch, ohne Datei-I/O.
//   * TSourceEncodingDetector.AnalyzeUnit(nil, TempFile, ...) - Emit + Praezedenz.
//     Der Detektor liest die ECHTE Datei (Encoding steckt in den Rohbytes),
//     daher schreiben die Detektor-Tests Byte-Fixtures in eine Temp-Datei.
//     (ssSource/FindingsViaPipeline scheidet aus - ein In-Memory-String hat
//     kein Datei-Encoding.)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSourceEncoding = class
  public
    // ---- ComputeFileEncodingInfo: BOM-Sniff -------------------------------
    [Test] procedure Compute_PureAscii_NoBom_Clean;
    [Test] procedure Compute_Utf8Bom_Detected;
    [Test] procedure Compute_Utf16LE_Bom_Detected;
    [Test] procedure Compute_Utf16BE_Bom_Detected;
    [Test] procedure Compute_Utf32LE_CheckedBeforeUtf16;
    [Test] procedure Compute_Utf32BE_Bom_Detected;
    // ---- ComputeFileEncodingInfo: Nicht-ASCII / strikter UTF-8 ------------
    [Test] procedure Compute_Utf8NoBom_NonAscii_Valid;
    [Test] procedure Compute_Utf8Bom_NonAscii_Valid_PostBomSlice;
    [Test] procedure Compute_Overlong_C0_80_Invalid;
    [Test] procedure Compute_Surrogate_ED_A0_80_Invalid;
    [Test] procedure Compute_OutOfRange_F5_Invalid;
    [Test] procedure Compute_Euro_IsMultiByte3Up;
    [Test] procedure Compute_Ansi_HighByte_NotValidUtf8;
    // ---- ComputeFileEncodingInfo: NUL / Bidi / Zero-Width -----------------
    [Test] procedure Compute_NulByte_Detected;
    [Test] procedure Compute_Bidi_RLO_Detected;
    [Test] procedure Compute_Bidi_ALM_Detected;
    [Test] procedure Compute_ZeroWidth_ZWSP_Detected;
    [Test] procedure Compute_MidFileFEFF_IsZeroWidth;
    [Test] procedure Compute_Nbsp_NotZeroWidth;

    // ---- Detektor: ein Fund pro Fall --------------------------------------
    [Test] procedure Detect_Utf8NoBom_E1;
    [Test] procedure Detect_InvalidUtf8_E2;
    [Test] procedure Detect_Ansi_E3;
    [Test] procedure Detect_Utf16_E4;
    [Test] procedure Detect_NulByte_E5;
    [Test] procedure Detect_Utf32_E7;
    [Test] procedure Detect_Bidi_S1;
    [Test] procedure Detect_ZeroWidth_S2;
    // ---- Detektor: Nicht-Funde + Praezedenz + Orthogonalitaet -------------
    [Test] procedure Detect_PureAscii_NoFinding;
    [Test] procedure Detect_Utf8Bom_NonAscii_NoFinding;
    [Test] procedure Detect_Precedence_NulBeatsE1;
    [Test] procedure Detect_BidiInUtf8Bom_S1_NoEncodingFinding;
    [Test] procedure Detect_NonPascalExt_Skipped;
    // ---- E1 Kommentar/String-Awareness (Confidence-Tiering) ---------------
    [Test] procedure Outside_StringLiteral_True;
    [Test] procedure Outside_Identifier_True;
    [Test] procedure Outside_LineComment_False;
    [Test] procedure Outside_BraceComment_False;
    [Test] procedure Outside_ParenComment_False;
    [Test] procedure Outside_PureAscii_False;
    [Test] procedure Detect_Utf8NoBom_InString_fcMedium;
    [Test] procedure Detect_Utf8NoBom_InComment_fcLow;
    // ---- S3 Homoglyph / Non-ASCII-Identifier ------------------------------
    [Test] procedure Ident_NonAscii_True;
    [Test] procedure Ident_InString_False;
    [Test] procedure Ident_InComment_False;
    [Test] procedure Ident_PureAscii_False;
    [Test] procedure Detect_NonAsciiIdentifier_S3;
    [Test] procedure Detect_Utf8Bom_NonAsciiIdent_S3_NoEncodingFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.IOUtils,
  uFileTextCache, uSourceEncoding, uMethodd12, uSCAConsts;

{ ---- Helpers ------------------------------------------------------------- }

function Ascii(const S: AnsiString): TBytes;
var i: Integer;
begin
  SetLength(Result, Length(S));
  for i := 1 to Length(S) do
    Result[i - 1] := Byte(S[i]);
end;

function Cat(const A, B: TBytes): TBytes;
begin
  SetLength(Result, Length(A) + Length(B));
  if Length(A) > 0 then Move(A[0], Result[0], Length(A));
  if Length(B) > 0 then Move(B[0], Result[Length(A)], Length(B));
end;

function WriteTempBytes(const Bytes: TBytes; const Ext: string = '.pas'): string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'sca_enc_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '') + Ext);
  TFile.WriteAllBytes(Result, Bytes);
end;

function CountKind(Findings: TObjectList<TLeakFinding>; Kind: TFindingKind): Integer;
var F: TLeakFinding;
begin
  Result := 0;
  for F in Findings do
    if F.Kind = Kind then Inc(Result);
end;

function FirstKind(Findings: TObjectList<TLeakFinding>; Kind: TFindingKind): TLeakFinding;
var F: TLeakFinding;
begin
  Result := nil;
  for F in Findings do
    if F.Kind = Kind then Exit(F);
end;

// Schreibt Bytes in eine Temp-Datei, ruft den Detektor (UnitNode wird ignoriert),
// gibt die Findings-Liste (Caller-owned) zurueck. Ext steuert die Datei-Endung
// (fuer den Extensions-Filter-Test).
function DetectBytes(const Bytes: TBytes; const Ext: string = '.pas')
  : TObjectList<TLeakFinding>;
var TempFile: string;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempFile := WriteTempBytes(Bytes, Ext);
  try
    TSourceEncodingDetector.AnalyzeUnit(nil, TempFile, Result);
  finally
    if TFile.Exists(TempFile) then TFile.Delete(TempFile);
  end;
end;

{ ---- ComputeFileEncodingInfo: BOM ---------------------------------------- }

procedure TTestSourceEncoding.Compute_PureAscii_NoBom_Clean;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(Ascii('unit t; implementation end.'));
  Assert.IsTrue(I.BomKind = sbkNone, 'BomKind');
  Assert.IsFalse(I.HasNonAscii, 'HasNonAscii');
  Assert.IsTrue(I.StrictUtf8, 'StrictUtf8 (ASCII ist gueltig)');
  Assert.IsFalse(I.HasNulCtrl, 'HasNulCtrl');
  Assert.IsFalse(I.HasBidi, 'HasBidi');
  Assert.IsFalse(I.HasZeroWidth, 'HasZeroWidth');
end;

procedure TTestSourceEncoding.Compute_Utf8Bom_Detected;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(Cat(TBytes.Create($EF, $BB, $BF), Ascii('unit t;')));
  Assert.IsTrue(I.BomKind = sbkUtf8, 'BomKind');
  Assert.IsFalse(I.HasNonAscii, 'BOM-Bytes zaehlen NICHT als Nicht-ASCII (Post-BOM-Slice)');
end;

procedure TTestSourceEncoding.Compute_Utf16LE_Bom_Detected;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(TBytes.Create($FF, $FE, $75, $00, $6E, $00));
  Assert.IsTrue(I.BomKind = sbkUtf16LE, 'BomKind');
end;

procedure TTestSourceEncoding.Compute_Utf16BE_Bom_Detected;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(TBytes.Create($FE, $FF, $00, $75, $00, $6E));
  Assert.IsTrue(I.BomKind = sbkUtf16BE, 'BomKind');
end;

procedure TTestSourceEncoding.Compute_Utf32LE_CheckedBeforeUtf16;
var I: TFileEncodingInfo;
begin
  // FF FE 00 00 beginnt mit FF FE - der UTF-32-Sniff MUSS vor dem UTF-16-Sniff
  // laufen, sonst wird es faelschlich als UTF-16 LE erkannt.
  I := ComputeFileEncodingInfo(TBytes.Create($FF, $FE, $00, $00, $41, $00, $00, $00));
  Assert.IsTrue(I.BomKind = sbkUtf32LE, 'BomKind muss UTF-32 LE sein, nicht UTF-16 LE');
end;

procedure TTestSourceEncoding.Compute_Utf32BE_Bom_Detected;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(TBytes.Create($00, $00, $FE, $FF, $00, $00, $00, $41));
  Assert.IsTrue(I.BomKind = sbkUtf32BE, 'BomKind');
end;

{ ---- ComputeFileEncodingInfo: Nicht-ASCII / strikter UTF-8 --------------- }

procedure TTestSourceEncoding.Compute_Utf8NoBom_NonAscii_Valid;
var I: TFileEncodingInfo;
begin
  // 'e-acute' = C3 A9, gueltiges 2-Byte-UTF-8, keine BOM.
  I := ComputeFileEncodingInfo(Cat(Ascii('x'), TBytes.Create($C3, $A9)));
  Assert.IsTrue(I.BomKind = sbkNone, 'BomKind');
  Assert.IsTrue(I.HasNonAscii, 'HasNonAscii');
  Assert.IsTrue(I.StrictUtf8, 'StrictUtf8');
end;

procedure TTestSourceEncoding.Compute_Utf8Bom_NonAscii_Valid_PostBomSlice;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(Cat(TBytes.Create($EF, $BB, $BF), TBytes.Create($C3, $A9)));
  Assert.IsTrue(I.BomKind = sbkUtf8, 'BomKind');
  Assert.IsTrue(I.HasNonAscii, 'HasNonAscii (C3 A9 nach der BOM)');
  Assert.IsTrue(I.StrictUtf8, 'StrictUtf8');
end;

procedure TTestSourceEncoding.Compute_Overlong_C0_80_Invalid;
var I: TFileEncodingInfo;
begin
  // C0 80 = ueberlange Kodierung von U+0000 - RFC 3629 verboten. Der lenient
  // IsValidUtf8 wuerde das durchlassen; der strikte Validator MUSS es ablehnen.
  I := ComputeFileEncodingInfo(Cat(TBytes.Create($EF, $BB, $BF), TBytes.Create($C0, $80)));
  Assert.IsTrue(I.BomKind = sbkUtf8, 'BomKind');
  Assert.IsFalse(I.StrictUtf8, 'C0 80 (ueberlang) muss ungueltig sein');
end;

procedure TTestSourceEncoding.Compute_Surrogate_ED_A0_80_Invalid;
var I: TFileEncodingInfo;
begin
  // ED A0 80 = U+D800 (Surrogat) - in UTF-8 verboten.
  I := ComputeFileEncodingInfo(TBytes.Create($ED, $A0, $80));
  Assert.IsFalse(I.StrictUtf8, 'Surrogat muss ungueltig sein');
end;

procedure TTestSourceEncoding.Compute_OutOfRange_F5_Invalid;
var I: TFileEncodingInfo;
begin
  // F5 .. = Codepoint > U+10FFFF.
  I := ComputeFileEncodingInfo(TBytes.Create($F5, $80, $80, $80));
  Assert.IsFalse(I.StrictUtf8, 'F5-Lead (>U+10FFFF) muss ungueltig sein');
end;

procedure TTestSourceEncoding.Compute_Euro_IsMultiByte3Up;
var I: TFileEncodingInfo;
begin
  // Euro = E2 82 AC, gueltige 3-Byte-Sequenz -> starke Evidenz fuer echtes UTF-8.
  I := ComputeFileEncodingInfo(TBytes.Create($E2, $82, $AC));
  Assert.IsTrue(I.StrictUtf8, 'StrictUtf8');
  Assert.IsTrue(I.HasMultiByte3Up, 'HasMultiByte3Up');
end;

procedure TTestSourceEncoding.Compute_Ansi_HighByte_NotValidUtf8;
var I: TFileEncodingInfo;
begin
  // F6 = CP1252 'oe-umlaut', als alleinstehendes Byte KEIN gueltiges UTF-8.
  I := ComputeFileEncodingInfo(Cat(Ascii('Gr'), Cat(TBytes.Create($F6), Ascii('sse'))));
  Assert.IsTrue(I.BomKind = sbkNone, 'BomKind');
  Assert.IsTrue(I.HasNonAscii, 'HasNonAscii');
  Assert.IsFalse(I.StrictUtf8, 'einzelnes F6 ist kein gueltiges UTF-8 (E3-Fall)');
end;

{ ---- ComputeFileEncodingInfo: NUL / Bidi / Zero-Width -------------------- }

procedure TTestSourceEncoding.Compute_NulByte_Detected;
var I: TFileEncodingInfo;
begin
  I := ComputeFileEncodingInfo(TBytes.Create($61, $00, $62));
  Assert.IsTrue(I.HasNulCtrl, 'HasNulCtrl');
end;

procedure TTestSourceEncoding.Compute_Bidi_RLO_Detected;
var I: TFileEncodingInfo;
begin
  // U+202E RLO = E2 80 AE.
  I := ComputeFileEncodingInfo(Cat(Ascii('a'), TBytes.Create($E2, $80, $AE)));
  Assert.IsTrue(I.HasBidi, 'HasBidi (U+202E)');
end;

procedure TTestSourceEncoding.Compute_Bidi_ALM_Detected;
var I: TFileEncodingInfo;
begin
  // U+061C ALM = D8 9C.
  I := ComputeFileEncodingInfo(TBytes.Create($D8, $9C));
  Assert.IsTrue(I.HasBidi, 'HasBidi (U+061C)');
end;

procedure TTestSourceEncoding.Compute_ZeroWidth_ZWSP_Detected;
var I: TFileEncodingInfo;
begin
  // U+200B ZWSP = E2 80 8B.
  I := ComputeFileEncodingInfo(Cat(Ascii('a'), TBytes.Create($E2, $80, $8B)));
  Assert.IsTrue(I.HasZeroWidth, 'HasZeroWidth (U+200B)');
end;

procedure TTestSourceEncoding.Compute_MidFileFEFF_IsZeroWidth;
var I: TFileEncodingInfo;
begin
  // EF BB BF am Datei-ANFANG = BOM; mitten in der Datei = U+FEFF ZWNBSP.
  I := ComputeFileEncodingInfo(Cat(Ascii('a'), TBytes.Create($EF, $BB, $BF)));
  Assert.IsTrue(I.BomKind = sbkNone, 'kein BOM (EF BB BF steht nicht am Offset 0)');
  Assert.IsTrue(I.HasZeroWidth, 'mid-file U+FEFF muss Zero-Width sein');
end;

procedure TTestSourceEncoding.Compute_Nbsp_NotZeroWidth;
var I: TFileEncodingInfo;
begin
  // NBSP U+00A0 = C2 A0 - BEWUSST NICHT als Zero-Width geflaggt (UI-String-legit).
  I := ComputeFileEncodingInfo(Cat(Ascii('a'), TBytes.Create($C2, $A0)));
  Assert.IsTrue(I.HasNonAscii, 'HasNonAscii');
  Assert.IsFalse(I.HasZeroWidth, 'NBSP darf NICHT als Zero-Width zaehlen');
end;

{ ---- Detektor: ein Fund pro Fall ----------------------------------------- }

procedure TTestSourceEncoding.Detect_Utf8NoBom_E1;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('unit x;'), TBytes.Create($C3, $A9)));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf8NoBom));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_InvalidUtf8_E2;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF), TBytes.Create($C0, $80)));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceInvalidUtf8));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Ansi_E3;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('Gr'), Cat(TBytes.Create($F6), Ascii('sse'))));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceAnsiNonAscii));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf16_E4;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(TBytes.Create($FF, $FE, $75, $00, $6E, $00));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf16));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_NulByte_E5;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(TBytes.Create($75, $6E, $00, $69, $74));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceControlChar));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf32_E7;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(TBytes.Create($FF, $FE, $00, $00, $41, $00, $00, $00));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf32));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Bidi_S1;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('// '), TBytes.Create($E2, $80, $AE)));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceBidiOverride));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_ZeroWidth_S2;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('a'), TBytes.Create($E2, $80, $8B)));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceInvisibleChar));
  finally F.Free; end;
end;

{ ---- Detektor: Nicht-Funde + Praezedenz + Orthogonalitaet ---------------- }

procedure TTestSourceEncoding.Detect_PureAscii_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Ascii('unit t; implementation end.'));
  try Assert.AreEqual<Integer>(0, F.Count, 'reines ASCII -> kein Encoding-Fund');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf8Bom_NonAscii_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  // Das Soll: UTF-8 MIT BOM + Umlaut in einem STRING-Literal -> korrekt, kein
  // Fund. (Nicht-ASCII muss in einem String stehen, nicht in Code-Position:
  // ein Umlaut im Identifier wuerde zu Recht S3/SCA193 ausloesen.)
  //   <BOM>S := 'e-acute';
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF),
                       Cat(Ascii('S := '),
                           Cat(TBytes.Create($27, $C3, $A9, $27), Ascii(';')))));
  try Assert.AreEqual<Integer>(0, F.Count, 'UTF-8+BOM + Umlaut im String ist das Soll -> kein Fund');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Precedence_NulBeatsE1;
var F: TObjectList<TLeakFinding>;
begin
  // Gueltiges UTF-8 ohne BOM (waere E1) PLUS ein NUL-Byte (E5). Praezedenz E5>E1:
  // genau EIN Gruppe-A-Fund, und zwar E5.
  F := DetectBytes(Cat(TBytes.Create($C3, $A9), TBytes.Create($00)));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceControlChar), 'E5 gewinnt');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceUtf8NoBom), 'kein E1 (Praezedenz)');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_BidiInUtf8Bom_S1_NoEncodingFinding;
var F: TObjectList<TLeakFinding>;
begin
  // Sauberes UTF-8+BOM, aber mit einem Bidi-Override: S1 feuert (orthogonal),
  // KEIN Gruppe-A-Encoding-Fund (die Datei-Encoding ist korrekt).
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF),
                       Cat(Ascii('// '), TBytes.Create($E2, $80, $AE))));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceBidiOverride), 'S1 feuert auch in UTF-8+BOM');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceUtf8NoBom), 'kein E1');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceInvalidUtf8), 'kein E2');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_NonPascalExt_Skipped;
var F: TObjectList<TLeakFinding>;
begin
  // Nicht-Pascal-Endung (.txt) -> Detektor ueberspringt, selbst mit Bidi.
  F := DetectBytes(Cat(Ascii('a'), TBytes.Create($E2, $80, $AE)), '.txt');
  try Assert.AreEqual<Integer>(0, F.Count, '.txt wird nicht gescannt');
  finally F.Free; end;
end;

{ ---- E1 Kommentar/String-Awareness (Confidence-Tiering) ------------------ }
// Chr($E9) = 'e-acute' (U+00E9), zur Laufzeit erzeugt -> Test-Source bleibt ASCII.
// Chr(39) = Apostroph (String-Quote).

procedure TTestSourceEncoding.Outside_StringLiteral_True;
begin
  // S := '(e-acute)';  -> Nicht-ASCII im String-Literal (ausserhalb Kommentar)
  Assert.IsTrue(TSourceEncodingDetector.HasNonAsciiOutsideComments(
    'S := ' + Chr(39) + Chr($E9) + Chr(39) + ';'));
end;

procedure TTestSourceEncoding.Outside_Identifier_True;
begin
  // Nicht-ASCII in Code-/Identifier-Position (ausserhalb Kommentar)
  Assert.IsTrue(TSourceEncodingDetector.HasNonAsciiOutsideComments(
    'var ' + Chr($E9) + 'x: Integer;'));
end;

procedure TTestSourceEncoding.Outside_LineComment_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiOutsideComments('// ' + Chr($E9)));
end;

procedure TTestSourceEncoding.Outside_BraceComment_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiOutsideComments('{ ' + Chr($E9) + ' }'));
end;

procedure TTestSourceEncoding.Outside_ParenComment_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiOutsideComments('(* ' + Chr($E9) + ' *)'));
end;

procedure TTestSourceEncoding.Outside_PureAscii_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiOutsideComments(
    'unit t; implementation end.'));
end;

procedure TTestSourceEncoding.Detect_Utf8NoBom_InString_fcMedium;
var F: TObjectList<TLeakFinding>; Fnd: TLeakFinding;
begin
  // S := '(e-acute)';  als UTF-8 ohne BOM -> E1 fcMedium (Nicht-ASCII im String-Literal)
  F := DetectBytes(Cat(Ascii('S := '),
                       Cat(TBytes.Create($27, $C3, $A9, $27), Ascii(';'))));
  try
    Fnd := FirstKind(F, fkSourceUtf8NoBom);
    Assert.IsNotNull(Fnd, 'E1 muss feuern');
    Assert.IsTrue(Fnd.Confidence = fcMedium, 'Nicht-ASCII im String -> fcMedium');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf8NoBom_InComment_fcLow;
var F: TObjectList<TLeakFinding>; Fnd: TLeakFinding;
begin
  // "// (e-acute)"  als UTF-8 ohne BOM -> E1 fcLow (Nicht-ASCII nur im Kommentar)
  F := DetectBytes(Cat(Ascii('// '), TBytes.Create($C3, $A9)));
  try
    Fnd := FirstKind(F, fkSourceUtf8NoBom);
    Assert.IsNotNull(Fnd, 'E1 muss feuern');
    Assert.IsTrue(Fnd.Confidence = fcLow, 'Nicht-ASCII nur im Kommentar -> fcLow');
  finally F.Free; end;
end;

{ ---- S3 Homoglyph / Non-ASCII-Identifier -------------------------------- }

procedure TTestSourceEncoding.Ident_NonAscii_True;
begin
  // 'var <e-acute>x: Integer;' -> Nicht-ASCII in Identifier-/Code-Position
  Assert.IsTrue(TSourceEncodingDetector.HasNonAsciiIdentifier(
    'var ' + Chr($E9) + 'x: Integer;'));
end;

procedure TTestSourceEncoding.Ident_InString_False;
begin
  // Nicht-ASCII nur im String-Literal -> KEIN Identifier-Treffer
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiIdentifier(
    'S := ' + Chr(39) + Chr($E9) + Chr(39) + ';'));
end;

procedure TTestSourceEncoding.Ident_InComment_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiIdentifier('// ' + Chr($E9)));
end;

procedure TTestSourceEncoding.Ident_PureAscii_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasNonAsciiIdentifier(
    'var Login: string;'));
end;

procedure TTestSourceEncoding.Detect_NonAsciiIdentifier_S3;
var F: TObjectList<TLeakFinding>;
begin
  // 'var <e-acute>x: Integer;' als UTF-8 ohne BOM -> S3 feuert (Identifier).
  F := DetectBytes(Cat(Ascii('var '),
                       Cat(TBytes.Create($C3, $A9), Ascii('x: Integer;'))));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf8Bom_NonAsciiIdent_S3_NoEncodingFinding;
var F: TObjectList<TLeakFinding>;
begin
  // Korrektes UTF-8+BOM, aber Identifier mit Homoglyph -> S3 feuert, KEIN
  // Encoding-Fund (die Datei-Encoding ist korrekt).
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF),
                       Cat(Ascii('var '),
                           Cat(TBytes.Create($C3, $A9), Ascii('x: Integer;')))));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier), 'S3 feuert auch in UTF-8+BOM');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceUtf8NoBom), 'kein E1 (hat BOM)');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceInvalidUtf8), 'kein E2');
  finally F.Free; end;
end;

end.
