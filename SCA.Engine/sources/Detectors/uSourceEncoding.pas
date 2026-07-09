unit uSourceEncoding;

// Detektor-Familie "Datei-Encoding / Unicode-Sicherheit" (Welle 1 + 2).
// Prueft die GANZE Datei auf Byte-Ebene (eigener Read via AnalyzeFileEncoding -
// der Text-Cache haelt nur dekodierte Strings ohne BOM, die Encoding-Wahrheit
// steckt nur in den Rohbytes). Siehe Konzept_FileEncodingDetector.
//
//   E1 fkSourceUtf8NoBom    - UTF-8 ohne BOM + Nicht-ASCII (Compiler liest ANSI
//                             -> Mojibake). Warning/fcLow (opt-in, Kommentar-FP).
//   E2 fkSourceInvalidUtf8  - ungueltige UTF-8-Sequenz unter UTF-8-BOM. Error.
//   E3 fkSourceAnsiNonAscii - ANSI (kein BOM, kein gueltiges UTF-8) + Nicht-ASCII
//                             -> codepage-abhaengig. Warning/fcMedium.
//   E4 fkSourceUtf16        - UTF-16-Quelltext (kompiliert, ungewoehnlich). Hint.
//   E5 fkSourceControlChar  - NUL / verbotenes Steuerzeichen. Error.
//   E7 fkSourceUtf32        - UTF-32/UCS-4 -> Compiler-Fehler F2438. Error.
//   S1 fkSourceBidiOverride - bidirektionales Override-Steuerzeichen (Trojan
//                             Source, CVE-2021-42574 / CWE-1007). Error.
//
// Gruppe A (Encoding) ist gegenseitig ausschliessend: genau EIN Fund pro Datei.
// UTF-32/UTF-16 (E7/E4) sind BOM-bestimmte Ganzdatei-Verdikte (emittieren + RAUS,
// kein Bidi-Scan auf UTF-16-Bytes). Fuer den Rest: Praezedenz E5 > E2 > E1 > E3.
// Gruppe B (S1) ist orthogonal und kann ZUSAETZLICH feuern - Bidi ist auch in
// korrektem UTF-8+BOM gefaehrlich.
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
  end;

implementation

// noinspection-file MultipleExit, TooLongLine, UnsortedUses, UnusedParameter

uses
  uFileTextCache;

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

class procedure TSourceEncodingDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Info : TFileEncodingInfo;
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
    // E1 auf fcLow (KindDefaultConfidence -> opt-in): der reine Byte-Detektor
    // kann Kommentar-Nicht-ASCII (harmlos - der Compiler verwirft Kommentare)
    // nicht von String-Literal-Nicht-ASCII (echter Bug) trennen. Praezise
    // Klassifikation braucht Token-/AST-Scope = spaetere Welle.
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNonAsciiLine),
      'UTF-8 without BOM with non-ASCII content. This analyser read it as ' +
      'UTF-8, but the Delphi compiler reads BOM-less files as ANSI (GetACP, ' +
      'e.g. CP-1252) -> mojibake at runtime IF the non-ASCII is in a string ' +
      'literal (non-ASCII in comments is harmless). Fix: save as UTF-8 WITH ' +
      'BOM, or build the project with --codepage:65001.',
      fkSourceUtf8NoBom))
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
