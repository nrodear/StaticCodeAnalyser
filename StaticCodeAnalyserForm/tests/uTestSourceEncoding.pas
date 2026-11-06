unit uTestSourceEncoding;

// Tests fuer die Encoding-/Unicode-Sicherheit-Detektor-Familie (SCA185-193
// und SCA207, uSourceEncoding + ComputeFileEncodingInfo in uFileTextCache).
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
    // ---- E5 Ausnahme: Legacy-DOS-EOF-Marker (Real-World-Audit 2026-07-31) --
    [Test] procedure Detect_LegacyDosEofMarker_NoFinding;
    [Test] procedure Detect_LegacyDosEofMarker_TrailingCrLf_NoFinding;
    [Test] procedure Detect_SubByteMidFile_StillE5;
    [Test] procedure Detect_TwoSubBytes_StillE5;
    // ---- E1 Kommentar/String-Awareness (Confidence-Tiering) ---------------
    [Test] procedure Outside_StringLiteral_True;
    [Test] procedure Outside_Identifier_True;
    [Test] procedure Outside_LineComment_False;
    [Test] procedure Outside_BraceComment_False;
    [Test] procedure Outside_ParenComment_False;
    [Test] procedure Outside_PureAscii_False;
    [Test] procedure Detect_Utf8NoBom_InString_fcMedium;
    [Test] procedure Detect_Utf8NoBom_InComment_fcLow;
    // ---- SCA185-dlFpc-Gate (Lazarus-Folge B1, 2026-09-19) -----------------
    [Test] procedure Detect_Utf8NoBom_FpcDialekt_Skipped;
    [Test] procedure Detect_Ansi_FpcDialekt_E3Bleibt;
    // ---- SCA190-dlFpc-Severity (G2, 2026-09-19) ---------------------------
    [Test] procedure Detect_Utf16_FpcDialekt_ErrorStattHint;
    [Test] procedure Detect_Utf16_DelphiDialekt_BleibtHint;
    // ---- S3 Homoglyph-Identifier (seit 2026-11-06 nur bekannte Homoglyphen)
    [Test] procedure Ident_AccentNotHomoglyph_False;
    [Test] procedure Ident_InString_False;
    [Test] procedure Ident_InComment_False;
    [Test] procedure Ident_PureAscii_False;
    [Test] procedure Detect_AccentIdentifier_NoS3_ButSca207;
    [Test] procedure Detect_Utf8Bom_HomoglyphIdent_S3_NoEncodingFinding;
    [Test] procedure Detect_Utf8Bom_UmlautIdent_NoS3;
    [Test] procedure Detect_S3_AnchorIsFirstHomoglyphLine;
    // ---- S3 Letter-only-Guard (Doku-Quickwins 2026-07-25) -----------------
    [Test] procedure Ident_NonLetterEllipsis_False;
    [Test] procedure Ident_HomoglyphGreekCapitalMu_True;
    [Test] procedure Ident_GreekSmallMuNotInTable_False;
    [Test] procedure Ident_HomoglyphCyrillic_True;
    [Test] procedure Detect_NonLetterSymbol_NoS3_ButE1;
    // ---- S3 Dekodier-Vertrauens-Gate (Vollzaehlung 2026-08-27) ------------
    [Test] procedure Detect_S3_UntrustedDecode_NoS3_ButE3;
    [Test] procedure Detect_S3_StrictUtf8NoBom_CyrillicIdent_S3;
    [Test] procedure Detect_S3_Utf8Bom_CyrillicIdent_S3;
    // Posten 304: S1/S2 nur wo die UTF-8-Lesart begruendet ist
    [Test] procedure Detect_Bidi_NotInAnsiFile;
    [Test] procedure Detect_Bidi_StillFiresInUtf8WithoutBom;
    // ---- S4 SCA207 FragileNonAsciiIdentifier (2026-11-06) ----------------
    [Test] procedure Sca207_Utf8NoBom_Delphi_NameAndLine;
    [Test] procedure Sca207_Utf8Bom_Delphi_NoFinding;
    [Test] procedure Sca207_Ansi_Delphi_NoFinding;
    [Test] procedure Sca207_UmlautOnlyInCommentAndString_NoFinding;
    [Test] procedure Sca207_SameNameTwice_OneFinding;
    [Test] procedure Sca207_TwoNames_TwoFindings;
    [Test] procedure Sca207_Fpc_Utf8Bom_Error;
    [Test] procedure Sca207_Fpc_Ansi_ErrorWithoutName;
    [Test] procedure Sca207_PureAscii_NoFinding;
    [Test] procedure Sca207_NonCodeForms_OnlyRealIdentifier;
    [Test] procedure Sca207_MultiLineString_NotCode;
    [Test] procedure Sca207_AmpersandName_WithoutAmpersand;
    [Test] procedure Sca207_SymbolInCode_NoFinding;
    [Test] procedure Sca207_IfdefBranch_Reported;
    [Test] procedure Sca207_CyrillicHomoglyph_Sca207AndSca193;
    [Test] procedure Sca207_SupplementaryLetter_Silent;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.IOUtils,
  uFileTextCache, uSourceEncoding, uMethodd12, uSCAConsts,
  uStaticFiles;   // ScanDialect (SCA185-dlFpc-Gate, Lazarus-Folge B1)

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

procedure TTestSourceEncoding.Detect_Utf8NoBom_FpcDialekt_Skipped;
// SCA185-dlFpc-Gate (Lazarus-Folge B1): unter FPC/Lazarus ist BOM-loses
// UTF-8 die Norm (die Lazarus-IDE speichert selbst ohne BOM) - E1 ist
// dort strukturell FP und wird geskippt. Dieselben Bytes wie im
// Bestandstest Detect_Utf8NoBom_E1, der die dlDefault-Gegenrichtung
// (1 Fund) weiter pinnt. Globaler View-State -> try/finally.
// Vor dem Gate: 1 Fund (dieser Test war ROT).
var
  F   : TObjectList<TLeakFinding>;
  Alt : TSourceDialect;
begin
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlFpc;
  try
    F := DetectBytes(Cat(Ascii('unit x;'), TBytes.Create($C3, $A9)));
    try
      Assert.AreEqual<Integer>(0, CountKind(F, fkSourceUtf8NoBom),
        'unter dlFpc meldet SCA185 nicht - BOM-los ist dort die Norm');
    finally F.Free; end;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestSourceEncoding.Detect_Ansi_FpcDialekt_E3Bleibt;
// Gegenprobe der Gate-Breite: der Skip trifft NUR E1. Echtes
// 8-bit-ANSI (E3/SCA189) ist auch unter FPC nicht portabel und muss
// unter dlFpc weiter gemeldet werden.
var
  F   : TObjectList<TLeakFinding>;
  Alt : TSourceDialect;
begin
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlFpc;
  try
    F := DetectBytes(Cat(Ascii('Gr'), Cat(TBytes.Create($F6), Ascii('sse'))));
    try
      Assert.AreEqual<Integer>(1, CountKind(F, fkSourceAnsiNonAscii),
        'E3 bleibt unter dlFpc aktiv - der Skip gilt nur E1');
    finally F.Free; end;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestSourceEncoding.Detect_Utf16_FpcDialekt_ErrorStattHint;
// SCA190-dlFpc-Severity (G2): FPC lehnt UTF-16-Quelltext ab - unter
// dlFpc ist E4 ein Error mit eigenem Text ('does not compile'), kein
// 'unusual, but compiles'-Hint. Dieselben Bytes wie Detect_Utf16_E4
// (der die dlDefault-Richtung pinnt). Vor G2: lsHint - dieser Test
// war ROT. Globaler View-State -> try/finally.
var
  F   : TObjectList<TLeakFinding>;
  X   : TLeakFinding;
  Alt : TSourceDialect;
begin
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlFpc;
  try
    F := DetectBytes(TBytes.Create($FF, $FE, $75, $00, $6E, $00));
    try
      Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf16),
        'die UTF-16-Datei wird auch unter dlFpc genau einmal gemeldet');
      for X in F do
        if X.Kind = fkSourceUtf16 then
        begin
          Assert.IsTrue(X.Severity = lsError,
            'unter dlFpc ist UTF-16 ein Error - FPC baut die Datei nicht');
          Assert.IsTrue(X.Confidence = fcHigh,
            'ein Baubruch traegt fcHigh - das Kind-Default fcLow '
            + 'waere im Default-Lauf unsichtbar');
          Assert.Contains(X.MissingVar, 'does not compile',
            'der fpc-Text darf nicht das Delphi-''It compiles'' tragen');
        end;
    finally F.Free; end;
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

procedure TTestSourceEncoding.Detect_Utf16_DelphiDialekt_BleibtHint;
// GEGENPROBE: unter dem Delphi-Default bleiben Stufe und Text exakt
// die alten - die Fund-Identitaet der Delphi-Referenz haengt daran.
var
  F : TObjectList<TLeakFinding>;
  X : TLeakFinding;
begin
  F := DetectBytes(TBytes.Create($FF, $FE, $75, $00, $6E, $00));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf16));
    for X in F do
      if X.Kind = fkSourceUtf16 then
      begin
        Assert.IsTrue(X.Severity = lsHint,
          'unter dlDelphi bleibt E4 ein Hint');
        Assert.Contains(X.MissingVar, 'It compiles',
          'der Delphi-Meldetext bleibt unveraendert');
      end;
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

{ --- Posten 304: S1/S2 nicht in ANSI-Dateien --------------------- }
//
// S1 und S2 suchen UTF-8-Sequenzen im Bytestrom. In einer Datei, die
// dieser Detektor GERADE SELBST als ANSI eingestuft hat (kein BOM,
// kein gueltiges UTF-8), ist diese Lesart unbegruendet - der Compiler
// liest die Bytes dort als Codepage-Zeichen. E2 80 AE ist in Latin-1
// schlicht drei harmlose Zeichen.
//
// An der Exe belegt: eine Datei mit Latin-1-Umlauten UND der
// Bytefolge E2 80 AE bekam sowohl SourceAnsiNonAscii ALS AUCH
// SourceBidiOverride - zwei einander widersprechende Verdikte.
//
// Korpuswirkung 0: der Referenzlauf hat weder S1 noch S2 ueberhaupt
// einen Fund.

procedure TTestSourceEncoding.Detect_Bidi_NotInAnsiFile;
// Latin-1-Umlaute machen die Datei zu ANSI (ungueltiges UTF-8); die
// Bidi-Bytefolge darf dann nicht mehr als U+202E gelesen werden.
// Heute: SourceAnsiNonAscii UND SourceBidiOverride. Nach dem Gate nur
// noch das erste.
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Cat(Ascii('// '), TBytes.Create($E4, $F6, $FC)),
                       TBytes.Create($E2, $80, $AE)));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceBidiOverride),
      'in einer ANSI-Datei ist E2 80 AE kein Bidi-Override');
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceAnsiNonAscii),
      'das ANSI-Verdikt selbst bleibt');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Bidi_StillFiresInUtf8WithoutBom;
// DIE ABGRENZUNG: ohne BOM, aber GUELTIGES UTF-8. Dort ist die
// Bytefolge wirklich U+202E und die Warnung berechtigt - das Gate
// darf sie nicht mitnehmen. Vor wie nach dem Fix 1.
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('// '), TBytes.Create($E2, $80, $AE)));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceBidiOverride),
      'gueltiges UTF-8 ohne BOM bleibt geprueft');
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

{ ---- E5 Ausnahme: Legacy-DOS-EOF-Marker (Real-World-Audit 2026-07-31) ----- }

procedure TTestSourceEncoding.Detect_LegacyDosEofMarker_NoFinding;
// FP-Fix 2026-07-31 (cnwizards PascalScript uPSC_std.pas): ein einzelnes 0x1A
// (SUB / Ctrl-Z) als letztes Byte einer sonst sauberen Textdatei ist der
// historische DOS-EOF-Marker, keine Korruption. Ohne das Gate meldet der
// Detektor hier E5.
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('unit t; end.'#13#10), TBytes.Create($1A)));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceControlChar),
      'einzelnes 0x1A am Dateiende ist der DOS-EOF-Marker');
    Assert.AreEqual<Integer>(0, F.Count,
      'Gruppe A faellt komplett aus - kein Ersatz-Fund (Monotonie)');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_LegacyDosEofMarker_TrailingCrLf_NoFinding;
// Variante: hinter dem Marker steht noch ein CRLF (haeufig) - weiterhin
// toleriert, weil nur Whitespace folgt.
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('unit t; end.'#13#10),
                       Cat(TBytes.Create($1A), Ascii(#13#10))));
  try Assert.AreEqual<Integer>(0, CountKind(F, fkSourceControlChar));
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_SubByteMidFile_StillE5;
// TP-Gegenprobe: 0x1A MITTEN in der Datei (danach noch echter Text) ist kein
// EOF-Marker - der Fund bleibt.
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('unit'), Cat(TBytes.Create($1A), Ascii(' t; end.'))));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceControlChar),
    '0x1A mitten im Text bleibt ein Kontrollbyte-Fund');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_TwoSubBytes_StillE5;
// TP-Gegenprobe: zwei 0x1A -> kein einzelner EOF-Marker mehr, Fund bleibt.
var F: TObjectList<TLeakFinding>;
begin
  F := DetectBytes(Cat(Ascii('unit t; end.'), TBytes.Create($1A, $1A)));
  try Assert.AreEqual<Integer>(1, CountKind(F, fkSourceControlChar),
    'zwei SUB-Bytes sind kein Legacy-EOF-Marker');
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

procedure TTestSourceEncoding.Ident_AccentNotHomoglyph_False;
begin
  // Entscheid Nico 2026-11-06: S3 meldet nur noch bekannte Homoglyphen.
  // 'var <e-acute>x' und 'Gr<o-Umlaut>sse' sind Nicht-ASCII im Identifier,
  // aber kein Zeichen sieht wie ein anderer ASCII-Buchstabe aus. Bis dahin
  // war das hier True (Bestandstest Ident_NonAscii_True).
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var ' + Chr($E9) + 'x: Integer;'), 'e-acute ist kein Homoglyph');
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var Gr' + Chr($F6) + 'sse: Integer;'), 'o-Umlaut ist kein Homoglyph');
  // Wache: derselbe Satz mit kyrillischem o IST einer.
  Assert.IsTrue(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var Gr' + Chr($043E) + 'sse: Integer;'));
end;

procedure TTestSourceEncoding.Ident_InString_False;
begin
  // Nicht-ASCII nur im String-Literal -> KEIN Identifier-Treffer
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'S := ' + Chr(39) + Chr($E9) + Chr(39) + ';'));
end;

procedure TTestSourceEncoding.Ident_InComment_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier('// ' + Chr($E9)));
end;

procedure TTestSourceEncoding.Ident_PureAscii_False;
begin
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var Login: string;'));
end;

procedure TTestSourceEncoding.Detect_AccentIdentifier_NoS3_ButSca207;
var F: TObjectList<TLeakFinding>;
begin
  // 'var <e-acute>x: Integer;' als UTF-8 ohne BOM. Bis 2026-11-06 feuerte
  // hier S3 (Bestandstest Detect_NonAsciiIdentifier_S3, 1 Fund). Nach dem
  // Entscheid ist e-acute kein Homoglyph -> kein SCA193; den belegten
  // Schaden (Formatter zerlegt den Namen in UTF-8 ohne BOM) meldet SCA207.
  F := DetectBytes(Cat(Ascii('var '),
                       Cat(TBytes.Create($C3, $A9), Ascii('x: Integer;'))));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceNonAsciiIdentifier),
      'e-acute ist kein Homoglyph');
    Assert.AreEqual<Integer>(1, CountKind(F, fkFragileNonAsciiIdentifier),
      'SCA207 meldet den Namen');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf8Bom_HomoglyphIdent_S3_NoEncodingFinding;
var F: TObjectList<TLeakFinding>;
begin
  // Korrektes UTF-8+BOM, aber Identifier mit Homoglyph -> S3 feuert, KEIN
  // Encoding-Fund (die Datei-Encoding ist korrekt). Bis 2026-11-06 stand
  // hier e-acute (C3 A9) - seit dem Entscheid kein Homoglyph mehr; jetzt das
  // kyrillische a (U+0430, D0 B0), das wirklich wie 'a' aussieht.
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF),
                       Cat(Ascii('var '),
                           Cat(TBytes.Create($D0, $B0), Ascii('x: Integer;')))));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier), 'S3 feuert auch in UTF-8+BOM');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceUtf8NoBom), 'kein E1 (hat BOM)');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceInvalidUtf8), 'kein E2');
  finally F.Free; end;
end;

{ ---- S3 Letter-only-Guard (Doku-Quickwins 2026-07-25) -------------------- }
// Nur Unicode-LETTER (Kategorie L*) in Code-Position zaehlen als Homoglyph-
// Kandidat; Symbole/Punktuation (Ellipsis U+2026, Dreiecke U+25B2/25B3) in
// Identifier-Nachbarschaft sind FPs. Homoglyphen (griech. My, Kyrillisch)
// MUESSEN weiter feuern.

procedure TTestSourceEncoding.Ident_NonLetterEllipsis_False;
begin
  // Fix-Test: Ellipsis U+2026 (Kategorie Po) in Code-Position -> KEIN S3.
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'X := A ' + Chr($2026) + ' B;'),
    'U+2026 (Punktuation) darf nicht als Identifier-Homoglyph zaehlen');
end;

procedure TTestSourceEncoding.Ident_HomoglyphGreekCapitalMu_True;
begin
  // TP-Gegenprobe: griechisches grosses My U+039C - genau das Zeichen des
  // Korpus-TPs (pyscripter dlgAboutPyScripter.pas:180). Bis 2026-11-06
  // stand hier das kleine My U+03BC; das sieht nicht wie ein ASCII-
  // Buchstabe aus und steht nicht in der Tabelle (s. naechster Test).
  Assert.IsTrue(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var ' + Chr($039C) + 'ask: Integer;'),
    'griechisches M ist ein Homoglyph -> der Korpus-TP muss erhalten bleiben');
end;

procedure TTestSourceEncoding.Ident_GreekSmallMuNotInTable_False;
begin
  // Kleines My U+03BC ist ein Buchstabe, aber kein Doppelgaenger eines
  // ASCII-Buchstabens (die reDelphix-Hilfe kennt es auch nicht).
  Assert.IsFalse(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var ' + Chr($03BC) + 'Sec: Integer;'));
  Assert.IsFalse(TSourceEncodingDetector.IsKnownHomoglyph(Chr($03BC)));
  Assert.IsTrue(TSourceEncodingDetector.IsKnownHomoglyph(Chr($039C)), 'Wache');
end;

procedure TTestSourceEncoding.Ident_HomoglyphCyrillic_True;
begin
  // TP-Gegenprobe: kyrillisches o U+043E (Kategorie Ll) im Identifier -
  // der klassische Confusable zu lateinischem "o".
  Assert.IsTrue(TSourceEncodingDetector.HasHomoglyphIdentifier(
    'var L' + Chr($043E) + 'gin: string;'),
    'kyrillisches o ist ein Letter -> Homoglyph-TP muss erhalten bleiben');
end;

procedure TTestSourceEncoding.Detect_NonLetterSymbol_NoS3_ButE1;
var F: TObjectList<TLeakFinding>;
begin
  // Detektor-Ebene: U+2026 (UTF-8: E2 80 A6) in Code-Position ohne BOM ->
  // KEIN S3 (Letter-only-Guard), aber E1 fcMedium bleibt (AnyOutside ist
  // BEWUSST ungefiltert - Mojibake-Risiko gilt fuer jedes Nicht-ASCII).
  F := DetectBytes(Cat(Ascii('X := A '),
                       Cat(TBytes.Create($E2, $80, $A6), Ascii(' B;'))));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceNonAsciiIdentifier),
      'Symbol in Code-Position darf S3 nicht ausloesen');
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf8NoBom),
      'E1 muss weiter feuern (Guard ist S3-lokal, monoton)');
  finally F.Free; end;
end;

{ ---- S3 Dekodier-Vertrauens-Gate (Vollzaehlung 2026-08-27) --------------- }
// Vollzaehlung SCA193: 3 Funde im ganzen Korpus, 1 TP / 2 FP. Beide FPs haben
// dieselbe Wurzel - die Datei ist BOM-los UND kein gueltiges UTF-8, wird von
// uFileTextCache.LoadFileSmart also mit TEncoding.Default (aktive System-
// Codepage) dekodiert. S3 urteilt danach ueber Buchstaben, die in der echten
// Quell-Codepage nicht existieren. Gate: S3 nur bei vertrauenswuerdiger
// Dekodierung (BOM-gesteuert oder strikt gueltiges UTF-8).

function CyrillicIdentLine2: TBytes;
// Gemeinsames Fixture, ANKERZEILE 2: 'var L<U+043E>gin: string;' mit
// kyrillischem o (UTF-8 D0 BE) mitten im Identifier - derselbe Confusable wie
// in Ident_HomoglyphCyrillic_True. Zeile 1 ist reines ASCII, damit der
// gemeldete Anker nicht trivial "1" ist.
begin
  Result := Cat(Ascii('unit t;'#13#10),
                Cat(Ascii('var L'),
                    Cat(TBytes.Create($D0, $BE), Ascii('gin: string;'))));
end;

procedure TTestSourceEncoding.Detect_S3_UntrustedDecode_NoS3_ButE3;
var F: TObjectList<TLeakFinding>; Fnd: TLeakFinding;
begin
  // FP-Fixture (Korpus-Wurzel, minimal nachgebaut): dasselbe Identifier-Byte-
  // paar wie im TP unten, aber Zeile 3 enthaelt ein $FF - damit ist die Datei
  // BOM-los und NICHT strikt UTF-8, also Default-dekodiert. Die Bytes D0 BE
  // sind dann keine Cyrillic-Quelle mehr, sondern zwei erfundene CP1252-
  // Zeichen -> S3 darf nicht mehr urteilen.
  // Diese Erwartung gilt codepage-UNABHAENGIG: das Gate schaltet S3 aus,
  // bevor irgendein Buchstabe geprueft wird. Der Unterschied zum TP unten
  // (gleicher Identifier, S3 = 1) beweist, dass wirklich das Gate wirkt und
  // nicht etwa der Lexer oder der Letter-Guard.
  F := DetectBytes(Cat(CyrillicIdentLine2, Cat(Ascii(#13#10'// '),
                       TBytes.Create($FF))));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceNonAsciiIdentifier),
      'S3 darf bei geratener (Default-)Dekodierung nicht feuern');
    // Monotonie: das Gate ENTFERNT nur S3. Die Datei bleibt gemeldet - durch
    // die ehrliche Regel E3 (codepage-abhaengiger Inhalt), verankert an der
    // ersten Nicht-ASCII-Zeile 2.
    Fnd := FirstKind(F, fkSourceAnsiNonAscii);
    Assert.IsNotNull(Fnd, 'E3 muss weiter feuern (Datei bleibt gemeldet)');
    Assert.AreEqual('2', Fnd.LineNumber, 'E3-Anker = erste Nicht-ASCII-Zeile');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_S3_StrictUtf8NoBom_CyrillicIdent_S3;
var F: TObjectList<TLeakFinding>; Fnd: TLeakFinding;
begin
  // TP-GEGENPROBE 1 (Gate-Zweig sbkNone + StrictUtf8): identischer Identifier,
  // aber die Datei ist strikt gueltiges UTF-8 -> LoadFileSmart dekodiert
  // garantiert als UTF-8, das kyrillische o steht wirklich im Quelltext.
  // Der TP der Vollzaehlung hat genau diese Form und MUSS erhalten bleiben.
  F := DetectBytes(CyrillicIdentLine2);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier),
      'echter Homoglyph in vertrauenswuerdiger Quelle muss weiter feuern');
    Fnd := FirstKind(F, fkSourceNonAsciiIdentifier);
    Assert.AreEqual('2', Fnd.LineNumber, 'S3-Anker = Identifier-Zeile 2');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_S3_Utf8Bom_CyrillicIdent_S3;
var F: TObjectList<TLeakFinding>;
begin
  // TP-GEGENPROBE 2 (Gate-Zweig sbkUtf8): mit BOM ist die Dekodierung
  // BOM-gesteuert und damit vertrauenswuerdig - S3 feuert, ohne dass ein
  // Encoding-Fund dazukommt (die Datei-Kodierung ist ja korrekt).
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF), CyrillicIdentLine2));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier),
      'UTF-8+BOM ist vertrauenswuerdig -> S3 bleibt');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceUtf8NoBom), 'kein E1');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceAnsiNonAscii), 'kein E3');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_Utf8Bom_UmlautIdent_NoS3;
var F: TObjectList<TLeakFinding>;
begin
  // UTF-8 MIT BOM, Bezeichner 'Gr<o-Umlaut>sse' (C3 B6): bis 2026-11-06 ein
  // SCA193-Fund, seit dem Entscheid keiner - ein Umlaut taeuscht keinen
  // ASCII-Buchstaben vor. Mit BOM bleibt der Name auch beim Formatieren heil
  // (kein SCA207), die Datei ist korrekt kodiert: gar kein Fund.
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF),
                       Cat(Ascii('var Gr'),
                           Cat(TBytes.Create($C3, $B6), Ascii('sse: Integer;')))));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceNonAsciiIdentifier),
      'Umlaut-Name ist kein Homoglyph');
    Assert.AreEqual<Integer>(0, F.Count, 'BOM-Datei mit Umlaut-Name: kein Fund');
  finally F.Free; end;
  // Wache: dieselbe Zeile mit kyrillischem o (D0 BE) meldet S3.
  F := DetectBytes(Cat(TBytes.Create($EF, $BB, $BF),
                       Cat(Ascii('var Gr'),
                           Cat(TBytes.Create($D0, $BE), Ascii('sse: Integer;')))));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier));
  finally F.Free; end;
end;

{ ---- S4 SCA207 FragileNonAsciiIdentifier (2026-11-06) --------------------- }
// Nico-Entscheide 2026-11-06: Delphi meldet Bezeichner mit Nicht-ASCII-
// Buchstaben nur in UTF-8 OHNE BOM (die IDE und der Formatter lesen ANSI und
// zerlegen den Namen), Warning/fcMedium; FPC jede Datei, Error/fcHigh, bei
// ANSI ohne Namen. Ein Fund je verschiedenem Namen an der ersten Zeile.
// Die Testquelle bleibt ASCII: Nicht-ASCII entsteht ueber #$nnnn.

const
  Q = '''';
  UML_A = #$00E4;
  UML_O = #$00F6;
  UML_CAP_O = #$00D6;
  SHARP_S = #$00DF;
  CYR_SMALL_O = #$043E;
  GROESSE = 'Gr' + UML_O + SHARP_S + 'e';
  GROESSE_UP = 'GR' + UML_CAP_O + SHARP_S + 'E';
  LAENGE = 'L' + UML_A + 'nge';
  MSG_207_ANSI = 'Identifier with a non-ASCII character in a file that is ' +
    'not UTF-8 - Free Pascal accepts only ASCII identifiers (A-Z, 0-9, _) ' +
    'and stops with "illegal character". Use an ASCII name.';

function Msg207Delphi(const AName: string): string;
begin
  Result := Format('Identifier ''%s'' contains non-ASCII letters in a UTF-8 ' +
    'file without BOM - the Delphi IDE and code formatter read such a file ' +
    'as ANSI and split the identifier, so the unit no longer compiles ' +
    'after formatting. Save the file as UTF-8 with BOM, or use an ASCII name.',
    [AName]);
end;

function Msg207Fpc(const AName: string): string;
begin
  Result := Format('Identifier ''%s'' contains non-ASCII letters - Free ' +
    'Pascal accepts only ASCII identifiers (A-Z, 0-9, _) and stops with ' +
    '"illegal character". Use an ASCII name.', [AName]);
end;

// Unit-Kopf (Zeilen 1-3) + ABody ab Zeile 4, CRLF.
function UnitText(const ABody: array of string): string;
var
  i : Integer;
begin
  Result := 'unit uF;'#13#10'interface'#13#10'implementation';
  for i := 0 to High(ABody) do
    Result := Result + #13#10 + ABody[i];
  Result := Result + #13#10'end.'#13#10;
end;

// Die Basis-Fixture des Konzepts: Deklaration Zeile 7, Nutzungen 10/11
// (AUpper = derselbe Name in Grossbuchstaben), Umlaut im Kommentar (Zeile 4)
// und im String (Zeile 12).
function FixtureF(const AName, AUpper: string): string;
begin
  Result := UnitText(['// ' + GROESSE + ' im Kommentar', 'procedure P;', 'var',
    '  ' + AName + ': Integer;', '  S: string;', 'begin',
    '  ' + AName + ' := 1;', '  ' + AUpper + ' := ' + AName + ' + 1;',
    '  S := ' + Q + 'Fl' + UML_A + 'che' + Q + ';', 'end;']);
end;

function Utf8Of(const S: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(S);
end;

function Utf8BomOf(const S: string): TBytes;
begin
  Result := Cat(TBytes.Create($EF, $BB, $BF), Utf8Of(S));
end;

function Cp1252Of(const S: string): TBytes;
var
  E : TEncoding;
begin
  E := TEncoding.GetEncoding(1252);
  try
    Result := E.GetBytes(S);
  finally
    E.Free;
  end;
end;

// DetectBytes unter dlFpc (globaler Zustand, im finally zurueck).
function DetectBytesFpc(const Bytes: TBytes): TObjectList<TLeakFinding>;
var
  Alt : TSourceDialect;
begin
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlFpc;
  try
    Result := DetectBytes(Bytes);
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
end;

// Die SCA207-Funde in Meldereihenfolge.
function Sca207Of(Findings: TObjectList<TLeakFinding>): TArray<TLeakFinding>;
var
  X : TLeakFinding;
begin
  Result := nil;
  for X in Findings do
    if X.Kind = fkFragileNonAsciiIdentifier then
      Result := Result + [X];
end;

procedure TTestSourceEncoding.Sca207_Utf8NoBom_Delphi_NameAndLine;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // T1: UTF-8 ohne BOM, Delphi. 'GROESSE' in Zeile 11 ist derselbe Name in
  // anderer Schreibweise - ein Fund, an der Deklaration (Zeile 7).
  F := DetectBytes(Utf8Of(FixtureF(GROESSE, GROESSE_UP)));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S), 'ein Name, ein Fund');
    Assert.AreEqual('7', S[0].LineNumber, 'erste Stelle = Deklaration');
    Assert.AreEqual(Msg207Delphi(GROESSE), S[0].MissingVar);
    Assert.IsTrue(S[0].Severity = lsWarning, 'Delphi-Zweig: Warning');
    Assert.IsTrue(S[0].Confidence = fcMedium, 'Delphi-Zweig: fcMedium');
    // Ueberschneidung: SCA185 meldet die Datei (Strings/Datei-Encoding)
    // weiter; SCA193 schweigt (Umlaut ist kein Homoglyph).
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf8NoBom), 'SCA185 bleibt');
    Assert.AreEqual<Integer>(0, CountKind(F, fkSourceNonAsciiIdentifier),
      'kein SCA193 fuer einen Umlaut-Namen');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_Utf8Bom_Delphi_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  // T2: dieselbe Datei MIT BOM - IDE und Formatter lesen sie richtig. Bis
  // 2026-11-06 meldete hier SCA193 (Umlaut im Identifier); jetzt kein Fund.
  F := DetectBytes(Utf8BomOf(FixtureF(GROESSE, GROESSE_UP)));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkFragileNonAsciiIdentifier));
    Assert.AreEqual<Integer>(0, F.Count, 'BOM-Datei ohne Homoglyph: kein Fund');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_Ansi_Delphi_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  // T3: echte ANSI-Datei (CP-1252) - der Formatter liest sie so, wie sie
  // geschrieben ist; der Name bleibt heil. SCA189 meldet das Encoding.
  F := DetectBytes(Cp1252Of(FixtureF(GROESSE, GROESSE_UP)));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkFragileNonAsciiIdentifier));
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceAnsiNonAscii), 'Wache: SCA189');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_UmlautOnlyInCommentAndString_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  // T4: Umlaut nur im Kommentar (Zeile 4) und im String (Zeile 12), ohne
  // BOM. Der Formatter laesst beide byte-gleich - kein SCA207, SCA185 bleibt.
  F := DetectBytes(Utf8Of(FixtureF('Groesse', 'GROESSE')));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkFragileNonAsciiIdentifier));
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf8NoBom), 'Wache: SCA185');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_SameNameTwice_OneFinding;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  F := DetectBytes(Utf8Of(UnitText(['procedure P;', 'var',
    '  ' + LAENGE + ': Integer;', 'begin', '  ' + LAENGE + ' := 1;',
    '  ' + LAENGE + ' := ' + LAENGE + ' + 1;', 'end;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S), 'vier Vorkommen, ein Name, ein Fund');
    Assert.AreEqual('6', S[0].LineNumber);
    Assert.AreEqual(Msg207Delphi(LAENGE), S[0].MissingVar);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_TwoNames_TwoFindings;
var
  F     : TObjectList<TLeakFinding>;
  S     : TArray<TLeakFinding>;
  Breit : string;
begin
  Breit := 'Breite_' + UML_A;
  F := DetectBytes(Utf8Of(UnitText(['procedure P;', 'var',
    '  ' + LAENGE + ': Integer;', '  ' + Breit + ': Integer;', 'begin',
    '  ' + Breit + ' := ' + LAENGE + ';', 'end;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(2, Length(S), 'zwei Namen, zwei Funde');
    Assert.AreEqual('6', S[0].LineNumber);
    Assert.AreEqual(Msg207Delphi(LAENGE), S[0].MissingVar);
    Assert.AreEqual('7', S[1].LineNumber);
    Assert.AreEqual(Msg207Delphi(Breit), S[1].MissingVar);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_Fpc_Utf8Bom_Error;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // T9: unter FPC bricht der Bau in JEDEM Encoding ('illegal character') -
  // auch mit BOM. Error, fcHigh, Name in der Meldung.
  F := DetectBytesFpc(Utf8BomOf(FixtureF(GROESSE, GROESSE_UP)));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S));
    Assert.AreEqual('7', S[0].LineNumber);
    Assert.AreEqual(Msg207Fpc(GROESSE), S[0].MissingVar);
    Assert.IsTrue(S[0].Severity = lsError, 'FPC-Zweig: Error');
    Assert.IsTrue(S[0].Confidence = fcHigh, 'FPC-Zweig: fcHigh');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_Fpc_Ansi_ErrorWithoutName;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // T11: ANSI unter FPC - der Name ist geraten (Systemcodepage), DASS ein
  // Byte >= $80 im Code steht, ist sicher. Meldung ohne Namen.
  F := DetectBytesFpc(Cp1252Of(FixtureF(GROESSE, GROESSE_UP)));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S), 'Kommentar und String zaehlen nicht');
    Assert.AreEqual('7', S[0].LineNumber);
    Assert.AreEqual(MSG_207_ANSI, S[0].MissingVar);
    Assert.IsTrue(S[0].Severity = lsError);
    Assert.IsTrue(S[0].Confidence = fcHigh);
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceAnsiNonAscii),
      'SCA189 bleibt unter FPC');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_PureAscii_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  // T16: reines ASCII in beiden Dialekten - kein Fund.
  F := DetectBytes(Utf8Of(UnitText(['procedure P;', 'var', '  Groesse: Integer;',
    'begin', '  Groesse := 1;', 'end;'])));
  try Assert.AreEqual<Integer>(0, F.Count, 'reines ASCII: kein Fund (Delphi)');
  finally F.Free; end;
  F := DetectBytesFpc(Utf8Of(UnitText(['procedure P;', 'var', '  Groesse: Integer;',
    'begin', '  Groesse := 1;', 'end;'])));
  try Assert.AreEqual<Integer>(0, F.Count, 'reines ASCII: kein Fund (FPC)');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_NonCodeForms_OnlyRealIdentifier;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // Direktive, { }, (* *), mehrzeiliger { }-Kommentar, String: kein Name.
  // Nur der echte Bezeichner in Zeile 11 zaehlt.
  F := DetectBytes(Utf8Of(UnitText(['{$DEFINE ' + GROESSE + '}',
    '{ ' + GROESSE + ' }', '(* ' + GROESSE + ' *)', '{ mehrzeilig',
    '  ' + GROESSE + ' }', 'const C = ' + Q + GROESSE + Q + ';',
    'const D = #$00F6;', 'var ' + LAENGE + ': Integer;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S));
    Assert.AreEqual('11', S[0].LineNumber);
    Assert.AreEqual(Msg207Delphi(LAENGE), S[0].MissingVar);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_MultiLineString_NotCode;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // Delphi-12-Mehrzeilenstring: die Textzeile 6 ist kein Code (ScanCodeLine
  // kennt die Form nicht - mit ihm kaeme hier ein Schein-Fund 'Groesse').
  // Hinter dem Abschluss (Zeile 7) ist wieder Code; Zeile 8 ist der Fund.
  F := DetectBytes(Utf8Of(UnitText(['const', '  T = ' + Q + Q + Q,
    '    ' + GROESSE + ' im Text', '    ' + Q + Q + Q + ';',
    'var ' + LAENGE + ': Integer;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S), 'nur der Bezeichner nach dem String');
    Assert.AreEqual('8', S[0].LineNumber);
    Assert.AreEqual(Msg207Delphi(LAENGE), S[0].MissingVar);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_AmpersandName_WithoutAmpersand;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  F := DetectBytes(Utf8Of(UnitText(['var &' + GROESSE + ': Integer;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S));
    Assert.AreEqual('4', S[0].LineNumber);
    Assert.AreEqual(Msg207Delphi(GROESSE), S[0].MissingVar, 'Name ohne &');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_SymbolInCode_NoFinding;
var F: TObjectList<TLeakFinding>;
begin
  // Ellipsis U+2026 im Code ist kein Buchstabe - kein Bezeichner.
  F := DetectBytes(Utf8Of(UnitText(['procedure P;', 'begin',
    '  X := Y' + #$2026 + ';', 'end;'])));
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkFragileNonAsciiIdentifier));
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceUtf8NoBom), 'Wache: SCA185');
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_IfdefBranch_Reported;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // Der Formatter formatiert auch inaktive Zweige - sie zaehlen (Grenze:
  // unter FPC meldet die Regel so auch Zweige, die FPC nie liest).
  F := DetectBytes(Utf8Of(UnitText(['{$IFDEF NIE}',
    'var ' + GROESSE + ': Integer;', '{$ENDIF}'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S));
    Assert.AreEqual('5', S[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_CyrillicHomoglyph_Sca207AndSca193;
var
  F     : TObjectList<TLeakFinding>;
  S     : TArray<TLeakFinding>;
  Login : string;
begin
  // T7: 'Login' mit kyrillischem o ohne BOM - beides ist wahr: der Formatter
  // zerlegt den Namen (SCA207), und das o taeuscht ein lateinisches vor
  // (SCA193).
  Login := 'L' + CYR_SMALL_O + 'gin';
  F := DetectBytes(Utf8Of(UnitText(['var ' + Login + ': string;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S));
    Assert.AreEqual(Msg207Delphi(Login), S[0].MissingVar);
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier));
    Assert.AreEqual('4', FirstKind(F, fkSourceNonAsciiIdentifier).LineNumber);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Sca207_SupplementaryLetter_Silent;
var
  F : TObjectList<TLeakFinding>;
  S : TArray<TLeakFinding>;
begin
  // GRENZE (festgehalten): ein Zeichen jenseits U+FFFF (hier U+1D400, als
  // Surrogatpaar) ist fuer den Lauf kein Buchstabe - der Name 'X<U+1D400>Y'
  // zerfaellt in 'X' und 'Y' (ASCII), kein Fund. Wache: Zeile 5.
  F := DetectBytes(Utf8Of(UnitText(['var X' + #$D835#$DC00 + 'Y: Integer;',
    'var ' + LAENGE + ': Integer;'])));
  try
    S := Sca207Of(F);
    Assert.AreEqual<Integer>(1, Length(S), 'nur die Wache');
    Assert.AreEqual('5', S[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestSourceEncoding.Detect_S3_AnchorIsFirstHomoglyphLine;
var
  F : TObjectList<TLeakFinding>;
  X : TLeakFinding;
begin
  // UTF-8 mit BOM: Zeile 4 traegt einen Umlaut-Namen, Zeile 5 einen
  // Homoglyph. Bis 2026-11-06 stand der S3-Anker auf Zeile 4 (erster
  // Nicht-ASCII-Buchstabe), jetzt auf Zeile 5 (erster Homoglyph) - dort
  // setzt auch die reDelphix-Hilfe an.
  F := DetectBytes(Utf8BomOf(UnitText(['var ' + GROESSE + ': Integer;',
    'var L' + CYR_SMALL_O + 'gin: string;'])));
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkSourceNonAsciiIdentifier));
    X := FirstKind(F, fkSourceNonAsciiIdentifier);
    Assert.AreEqual('5', X.LineNumber);
  finally F.Free; end;
end;

end.
