unit uSourceEncoding;

// Detektor-Familie "Datei-Encoding / Unicode-Sicherheit" (Welle 1 + 2).
// Prueft die GANZE Datei auf Byte-Ebene (eigener Read via AnalyzeFileEncoding -
// der Text-Cache haelt nur dekodierte Strings ohne BOM, die Encoding-Wahrheit
// steckt nur in den Rohbytes). Siehe Konzept_FileEncodingDetector.
//
//   E1 fkSourceUtf8NoBom    - UTF-8 ohne BOM + Nicht-ASCII (Compiler liest ANSI
//                             -> Mojibake). Confidence via TLexer: non-ASCII in
//                             String/Code = fcMedium, nur in Kommentaren = fcLow.
//   E2 fkSourceInvalidUtf8  - ungueltige UTF-8-Sequenz unter UTF-8-BOM. Error.
//   E3 fkSourceAnsiNonAscii - ANSI (kein BOM, kein gueltiges UTF-8) + Nicht-ASCII
//                             -> codepage-abhaengig. Warning/fcMedium.
//   E4 fkSourceUtf16        - UTF-16-Quelltext (kompiliert, ungewoehnlich). Hint.
//   E5 fkSourceControlChar  - NUL / verbotenes Steuerzeichen. Error.
//   E7 fkSourceUtf32        - UTF-32/UCS-4 -> Compiler-Fehler F2438. Error.
//   S1 fkSourceBidiOverride - bidirektionales Override-Steuerzeichen (Trojan
//                             Source, CVE-2021-42574 / CWE-1007). Error.
//   S2 fkSourceInvisibleChar- unsichtbares/Zero-Width-Zeichen (U+200B-200D/2060/
//                             mid-FEFF; Unicode-Abuse, CWE-1007). Warning.
//   S3 fkSourceNonAsciiIdentifier - Nicht-ASCII in einem Identifier (Homoglyph/
//                             Confusable, Trojan Source, CWE-1007). Warning.
//
// Gruppe A (Encoding) ist gegenseitig ausschliessend: genau EIN Fund pro Datei.
// UTF-32/UTF-16 (E7/E4) sind BOM-bestimmte Ganzdatei-Verdikte (emittieren + RAUS,
// kein Bidi-Scan auf UTF-16-Bytes). Fuer den Rest: Praezedenz E5 > E2 > E1 > E3.
// Gruppe B (S1/S2/S3) ist orthogonal und kann ZUSAETZLICH feuern - Bidi/Zero-Width/
// Homoglyph-Identifier sind auch in korrektem UTF-8+BOM gefaehrlich. S3 wird per
// TLexer erkannt (nur wenn die Datei ueberhaupt Nicht-ASCII hat -> kein Lex-
// Aufwand fuer reine ASCII-Dateien).
//
// Scope: nur Pascal-Quelltext (.pas/.dpr/.dpk/.inc). Kommentare zaehlen hier
// BEWUSST mit - Encoding/Bidi ist datei-global, nicht code-lokal.
//
// Registrierung: EIN AddD-Eintrag unter fkSourceUtf8NoBom + Sonderfall in
// IsDetectorEnabled (laeuft sobald mind. ein Encoding-Kind aktiv ist); die
// Post-Filter-Schleife dropt einzeln deaktivierte Kinds auf Finding-Ebene.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TSourceEncodingDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
    // True wenn ein Nicht-ASCII-Zeichen AUSSERHALB von Kommentaren steht
    // (String-Literal oder Code/Identifier). Via TLexer, der Kommentare
    // verwirft - non-ASCII ueberlebt nur in String-/Unknown-Tokens. Bestimmt
    // die E1-Confidence (String/Code = echtes Mojibake-Risiko = fcMedium; nur
    // Kommentar = vom Compiler verworfen = fcLow). Public fuer Tests.
    class function HasNonAsciiOutsideComments(const Source: string): Boolean; static;
    // True wenn ein Nicht-ASCII-Zeichen in einem Identifier/Code-Token
    // (tkIdent/tkUnknown) steht = Homoglyph-/Confusable-Vektor (S3). Public
    // fuer Tests.
    class function HasNonAsciiIdentifier(const Source: string): Boolean; static;
  end;

implementation

// noinspection-file MultipleExit, TooLongLine, UnsortedUses, UnusedParameter

uses
  System.Classes, uFileTextCache, uLexer;

function HasSourceExt(const FileName: string): Boolean;
var
  Ext : string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc');
end;

function LineOr1(L: Integer): Integer; inline;
begin
  if L > 0 then Result := L else Result := 1;
end;

procedure ScanNonAsciiTokens(const Source: string;
  out AnyOutside, InIdentifier: Boolean; out IdentLine: Integer);
// EIN Lex-Durchgang. Der TLexer verwirft Kommentare (//, { }, (* *), {$..}) und
// liefert nur Code-/String-/Unknown-Tokens - ein Nicht-ASCII-Zeichen im Token-
// Value steht also NICHT in einem Kommentar.
//   AnyOutside   = Nicht-ASCII in irgendeinem Token (String ODER Code) -> E1-
//                  Confidence (fcMedium statt fcLow).
//   InIdentifier = Nicht-ASCII in einem Identifier/Code-Token (tkIdent/tkUnknown)
//                  -> Homoglyph-/Confusable-Vektor (S3); IdentLine = dessen Zeile.
// (Randfall: der Lexer dekodiert #$nnnn-Char-Literale zu echten Zeichen - fuer
// die Detektor-Nutzung irrelevant, weil beide Aufrufer rohes Nicht-ASCII per
// AnalyzeFileEncoding.HasNonAscii voraussetzen.)
var
  Lex      : TLexer;
  Tok      : TToken;
  ch       : Char;
  TokHasNA : Boolean;
begin
  AnyOutside   := False;
  InIdentifier := False;
  IdentLine    := 0;
  if Source = '' then Exit;
  Lex := TLexer.Create(Source);
  try
    Tok := Lex.Next;
    while Tok.Kind <> tkEof do
    begin
      TokHasNA := False;
      for ch in Tok.Value do
        if Ord(ch) >= $80 then begin TokHasNA := True; Break; end;
      if TokHasNA then
      begin
        AnyOutside := True;
        if (Tok.Kind in [tkIdent, tkUnknown]) and not InIdentifier then
        begin
          InIdentifier := True;
          IdentLine    := Tok.Line;
        end;
      end;
      if AnyOutside and InIdentifier then Break;   // beide Fakten gefunden
      Tok := Lex.Next;
    end;
  finally
    Lex.Free;
  end;
end;

class function TSourceEncodingDetector.HasNonAsciiOutsideComments(
  const Source: string): Boolean;
var Ident: Boolean; Ln: Integer;
begin
  ScanNonAsciiTokens(Source, Result, Ident, Ln);
end;

class function TSourceEncodingDetector.HasNonAsciiIdentifier(
  const Source: string): Boolean;
var Outside: Boolean; Ln: Integer;
begin
  ScanNonAsciiTokens(Source, Outside, Result, Ln);
end;

class procedure TSourceEncodingDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Info      : TFileEncodingInfo;
  Lines     : TStringList;
  Cached    : Boolean;
  Outside   : Boolean;
  Ident     : Boolean;
  IdentLine : Integer;
begin
  if not HasSourceExt(FileName) then Exit;
  Info := AnalyzeFileEncoding(FileName);
  if not Info.Readable then Exit;   // Read-Fehler -> FileReadError deckt das ab

  // UTF-32/UTF-16-Quelltext: BOM-bestimmter Ganzdatei-Verdikt -> emittieren und
  // RAUS. Der Byte-Walk interpretiert die Bytes als UTF-8 (fuer UTF-16 unsinnig),
  // NUL-Bytes sind dort Encoding, und ein Bidi-Scan waere ebenfalls sinnlos.
  if Info.BomKind in [sbkUtf32LE, sbkUtf32BE] then
  begin
    Results.Add(TLeakFinding.New(FileName, '', 1,
      'UTF-32 / UCS-4 source file - the Delphi compiler rejects this with fatal ' +
      'error F2438 ("UCS-4 text encoding not supported"). Convert the file to ' +
      'UTF-8 (with BOM) or UTF-16.',
      fkSourceUtf32));
    Exit;
  end;
  if Info.BomKind in [sbkUtf16LE, sbkUtf16BE] then
  begin
    Results.Add(TLeakFinding.New(FileName, '', 1,
      'UTF-16 source file. It compiles, but UTF-16 source is unusual and causes ' +
      'friction with text tools (git diff, grep, external hooks). Convention is ' +
      'UTF-8 with BOM.',
      fkSourceUtf16));
    Exit;
  end;

  // ---- Gruppe B (Security), orthogonal zu allen Encoding-Gates ------------
  if Info.HasBidi then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstBidiLine),
      'Bidirectional override control character (e.g. U+202E) - Trojan Source ' +
      'risk (CVE-2021-42574): the code can read differently than it compiles. ' +
      'Remove the control character.',
      fkSourceBidiOverride));
  if Info.HasZeroWidth then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstZeroWidthLine),
      'Invisible / zero-width character (e.g. U+200B) in source - hidden-text ' +
      'abuse vector (CWE-1007). Almost never legitimate; remove it (U+200D can ' +
      'appear in emoji string literals - verify before removing there).',
      fkSourceInvisibleChar));

  // Token-basierte Analyse: EIN Lex-Durchgang, aber nur wenn die Datei ueberhaupt
  // Nicht-ASCII enthaelt (reine ASCII-Dateien = kein Lex-Aufwand). Liefert Outside
  // (Nicht-ASCII in String/Code -> E1-Confidence) und Ident (Nicht-ASCII in einem
  // Identifier -> S3).
  Outside := False; Ident := False; IdentLine := 0;
  if Info.HasNonAscii then
  begin
    Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
    if Lines <> nil then
      try
        ScanNonAsciiTokens(Lines.Text, Outside, Ident, IdentLine);
      finally
        ReleaseLines(Lines, Cached);
      end;
  end;

  // S3 (Security, orthogonal): Homoglyph-/Confusable-Identifier. Feuert auch in
  // korrektem UTF-8+BOM (ein Cyrillic-Homoglyph in einem Identifier ist dort
  // genauso gefaehrlich).
  if Ident then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(IdentLine),
      'Non-ASCII character in an identifier - homoglyph / confusable risk ' +
      '(Trojan Source, CWE-1007): a letter such as Cyrillic U+043E looks like ' +
      'Latin "o" but binds to a different symbol. Prefer ASCII identifiers; if a ' +
      'Unicode identifier is intentional, avoid mixing scripts.',
      fkSourceNonAsciiIdentifier));

  // ---- Gruppe A (Encoding): genau EIN Fund, Praezedenz E5 > E2 > E1 > E3 --
  if Info.HasNulCtrl then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNulCtrlLine),
      'NUL or control byte in source file - likely a binary file or a ' +
      'mis-detected encoding (e.g. BOM-less UTF-16, where every other byte is 0x00).',
      fkSourceControlChar))
  else if (Info.BomKind = sbkUtf8) and (not Info.StrictUtf8) then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstInvalidLine),
      'Invalid UTF-8 sequence under a UTF-8 BOM (overlong / surrogate / ' +
      'out-of-range code point). The Delphi compiler silently substitutes ' +
      'U+FFFD -> data corruption. Re-encode the file as clean UTF-8.',
      fkSourceInvalidUtf8))
  else if (Info.BomKind = sbkNone) and Info.HasNonAscii and Info.StrictUtf8 then
  begin
    // E1: Nicht-ASCII ohne BOM. Outside (oben in EINEM Lex-Durchgang ermittelt)
    // bestimmt die Confidence: String-Literal/Code = echtes Laufzeit-Mojibake
    // (fcMedium); nur Kommentar = der Compiler verwirft Kommentare (fcLow, opt-in).
    if Outside then
      Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNonAsciiLine),
        'UTF-8 without BOM: non-ASCII in a string literal or identifier. The ' +
        'Delphi compiler reads BOM-less files as ANSI (GetACP, e.g. CP-1252) -> ' +
        'mojibake at runtime. Fix: save as UTF-8 WITH BOM, or build with ' +
        '--codepage:65001.',
        fkSourceUtf8NoBom, fcMedium))
    else
      Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNonAsciiLine),
        'UTF-8 without BOM: non-ASCII only in comments (the compiler discards ' +
        'comments, so no runtime effect), but the file still lacks a BOM. Save ' +
        'as UTF-8 WITH BOM for consistency, or build with --codepage:65001.',
        fkSourceUtf8NoBom, fcLow));
  end
  else if (Info.BomKind = sbkNone) and Info.HasNonAscii and (not Info.StrictUtf8) then
    // E3: kein BOM, Nicht-ASCII, aber KEIN gueltiges UTF-8 -> echt 8-bit (ANSI).
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNonAsciiLine),
      'ANSI (8-bit) source file: non-ASCII content, no BOM, and not valid UTF-8. ' +
      'The compiler reads it in the system code page (GetACP), so the characters ' +
      'are code-page-dependent and non-portable across machines/locales. Save as ' +
      'UTF-8 with BOM.',
      fkSourceAnsiNonAscii));
end;

end.
