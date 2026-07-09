unit uSourceEncoding;

// Detektor-Familie "Datei-Encoding / Unicode-Sicherheit" (Welle 1).
// Prueft die GANZE Datei auf Byte-Ebene (eigener Read via AnalyzeFileEncoding -
// der Text-Cache haelt nur dekodierte Strings ohne BOM, die Encoding-Wahrheit
// steckt nur in den Rohbytes). Siehe Konzept_FileEncodingDetector.
//
//   E1 fkSourceUtf8NoBom    - UTF-8 ohne BOM + Nicht-ASCII (Compiler liest ANSI
//                             -> Mojibake). Warning, Confidence evidenz-abhaengig.
//   E2 fkSourceInvalidUtf8  - ungueltige UTF-8-Sequenz unter UTF-8-BOM. Error.
//   E5 fkSourceControlChar  - NUL / verbotenes Steuerzeichen. Error.
//   S1 fkSourceBidiOverride - bidirektionales Override-Steuerzeichen (Trojan
//                             Source, CVE-2021-42574 / CWE-1007). Error.
//
// Gruppe A (E1/E2/E5) ist gegenseitig ausschliessend: genau EIN Fund pro Datei,
// Praezedenz E5 > E2 > E1. Gruppe B (S1) ist orthogonal und kann ZUSAETZLICH
// feuern - Bidi ist auch in korrektem UTF-8+BOM gefaehrlich.
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

  // UTF-16/UTF-32-Quelltext ist eine spaetere Welle (E4/E7) - ganz ueberspringen:
  // der Byte-Walk interpretiert die Bytes als UTF-8, was fuer UTF-16 unsinnig ist
  // (und die NUL-Bytes sind dort Encoding, kein Fehler).
  if Info.BomKind in [sbkUtf16LE, sbkUtf16BE, sbkUtf32LE, sbkUtf32BE] then
    Exit;

  // ---- Gruppe B (Security), orthogonal zu allen Encoding-Gates ------------
  if Info.HasBidi then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstBidiLine),
      'Bidirectional override control character (e.g. U+202E) - Trojan Source ' +
      'risk (CVE-2021-42574): the code can read differently than it compiles. ' +
      'Remove the control character.',
      fkSourceBidiOverride));

  // ---- Gruppe A (Encoding): genau EIN Fund, Praezedenz E5 > E2 > E1 -------
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
      fkSourceUtf8NoBom));
end;

end.
