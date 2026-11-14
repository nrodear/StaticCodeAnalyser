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
//   E5 fkSourceControlChar  - NUL / verbotenes Steuerzeichen. Error. Ausnahme
//                             (2026-07-31): ein einzelnes 0x1A als letztes
//                             Nicht-Whitespace-Byte = Legacy-DOS-EOF-Marker.
//   E7 fkSourceUtf32        - UTF-32/UCS-4 -> Compiler-Fehler F2438. Error.
//   S1 fkSourceBidiOverride - bidirektionales Override-Steuerzeichen (Trojan
//                             Source, CVE-2021-42574 / CWE-1007). Error.
//   S2 fkSourceInvisibleChar- unsichtbares/Zero-Width-Zeichen (U+200B-200D/2060/
//                             mid-FEFF; Unicode-Abuse, CWE-1007). Warning.
//   S3 fkSourceNonAsciiIdentifier - bekannter Homoglyph in einem Identifier
//                             (Confusable, Trojan Source, CWE-1007). Warning.
//                             Nur bei vertrauenswuerdiger Dekodierung
//                             (IsDecodingTrustworthy). Seit 2026-11-06 nur
//                             noch Zeichen der Tabelle HOMOGLYPH_CODES (sehen
//                             aus wie ein ASCII-Buchstabe); ein Umlaut oder
//                             ein anderer Buchstabe ohne lateinischen
//                             Doppelgaenger ist kein Homoglyph - seinen
//                             Werkzeugbruch meldet S4.
//   S4 fkFragileNonAsciiIdentifier - Bezeichner mit Nicht-ASCII-Buchstaben, den
//                             Werkzeuge zerlegen (SCA207, 2026-11-06). Delphi:
//                             nur in UTF-8 OHNE BOM (IDE und Formatter lesen
//                             ANSI und reissen den Namen auf), Warning. FPC:
//                             jede Datei (FPC nimmt nur ASCII-Bezeichner),
//                             Error. Ein Fund je verschiedenem Namen.
//
// Gruppe A (Encoding) ist gegenseitig ausschliessend: genau EIN Fund pro Datei.
// UTF-32/UTF-16 (E7/E4) sind BOM-bestimmte Ganzdatei-Verdikte (emittieren + RAUS,
// kein Bidi-Scan auf UTF-16-Bytes). Fuer den Rest: Praezedenz E5 > E2 > E1 > E3.
// Gruppe B (S1-S4) ist orthogonal und kann ZUSAETZLICH feuern - Bidi/Zero-Width/
// Homoglyph-Identifier sind auch in korrektem UTF-8+BOM gefaehrlich. S3 wird per
// TLexer erkannt, S4 auf einer eigenen Code-Sicht (TCodeViewWalker) - beide nur
// wenn die Datei ueberhaupt Nicht-ASCII hat (kein Aufwand fuer reine ASCII-
// Dateien).
// S4 steht VOR Gruppe A: E1 verlaesst AnalyzeUnit unter dlFpc per Exit.
//
// Scope: nur Pascal-Quelltext (.pas/.dpr/.dpk/.inc). Kommentare zaehlen hier
// BEWUSST mit - Encoding/Bidi ist datei-global, nicht code-lokal.
//
// Registrierung: EIN AddD-Eintrag unter fkSourceUtf8NoBom + Sonderfall in
// IsDetectorEnabled (laeuft sobald mind. ein Encoding-Kind aktiv ist); die
// Post-Filter-Schleife dropt einzeln deaktivierte Kinds auf Finding-Ebene.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
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
    // True wenn ein BEKANNTER HOMOGLYPH (HOMOGLYPH_CODES: kyrillische und
    // griechische Buchstaben, die wie ein ASCII-Buchstabe aussehen) in einem
    // Identifier/Code-Token (tkIdent/tkUnknown) steht = Confusable-Vektor
    // (S3). Umlaute, Akzente, andere Schriften ohne Doppelgaenger und
    // Symbole (Ellipsis, Dreiecke) zaehlen NICHT. Public fuer Tests.
    class function HasHomoglyphIdentifier(const Source: string): Boolean; static;
    // True wenn C ein Zeichen der Tabelle HOMOGLYPH_CODES ist. Public fuer
    // Tests (Paritaet zu uRdxHomoglyphFix.HOMOGLYPHS).
    class function IsKnownHomoglyph(C: Char): Boolean; static;
    // S4 (SCA207): die verschiedenen Bezeichner mit Nicht-ASCII-Zeichen im
    // Code von ALines, je Name die erste Zeile (1-basiert) in ANameLines -
    // Reihenfolge des ersten Auftretens, Vergleich ohne Gross-/
    // Kleinschreibung. ARaw: jedes Zeichen >= #$80 zaehlt als Bezeichner-
    // zeichen (ANSI-Datei unter dlFpc - die Buchstaben sind geraten);
    // sonst nur Unicode-Buchstaben (L*) und im Namen Ziffern/Mn/Mc.
    // Public fuer Tests.
    class function FragileNames(ALines: TStrings; ARaw: Boolean;
      out ANameLines: TArray<Integer>): TArray<string>; static;
  end;

implementation

// noinspection-file MultipleExit, TooLongLine, UnsortedUses, UnusedParameter

uses
  System.Character, System.IOUtils, System.StrUtils, uFileTextCache, uLexer,
  uStaticFiles,   // IsUnitLikeFile - Dialekt-Endungen (Lazarus A3)
  uLocalization,  // N_ - feste S4-Meldung (ANSI unter dlFpc) als msgid
  uCrashDiag;     // IsFatalScanException (E3)

const
  // S3: die bekannten Homoglyphen - Buchstaben, die in den ueblichen
  // Editor-Schriften nicht von einem lateinischen zu unterscheiden sind
  // (Unicode confusables). DIESELBE Liste wie uRdxHomoglyphFix.HOMOGLYPHS
  // (reDelphix, dort mit dem ASCII-Partner) - wer eine aendert, aendert
  // beide; reDelphix uTestRdxHomoglyphFix.Detector_TableParity vergleicht
  // die beiden Listen Zeichen fuer Zeichen.
  // Die Engine darf reDelphix nicht kennen, daher die Kopie.
  HOMOGLYPH_CODES: array[0..46] of Word = (
    // kyrillisch klein: a e o p c y x s i j h l d q w
    $0430, $0435, $043E, $0440, $0441, $0443, $0445, $0455, $0456, $0458,
    $04BB, $04CF, $0501, $051B, $051D,
    // kyrillisch gross: S I J A B E K M H O P C T X Y Q W
    $0405, $0406, $0408, $0410, $0412, $0415, $041A, $041C, $041D, $041E,
    $0420, $0421, $0422, $0425, $04AE, $051A, $051C,
    // griechisch gross: A B E Z H I K M N O P T Y X
    $0391, $0392, $0395, $0396, $0397, $0399, $039A, $039C, $039D, $039F,
    $03A1, $03A4, $03A5, $03A7,
    // griechisch klein: o
    $03BF);

  // Mindestlaenge der Apostroph-Folge, die einen Delphi-12-Mehrzeilen-
  // string oeffnet (''' am Zeilenende) - wie uFormatterMarker.
  MIN_MULTI_QUOTES = 3;

  // S4-Meldungen (englisch: Fingerprint). Mit Namen = Format-Meldung (der
  // Name ist Teil der Fund-Identitaet, bleibt unuebersetzt); ohne Namen
  // (ANSI unter dlFpc) ein fester Satz in N_.
  MSG_207_DELPHI = 'Identifier ''%s'' contains non-ASCII letters in a UTF-8 ' +
    'file without BOM - the Delphi IDE and code formatter read such a file ' +
    'as ANSI and split the identifier, so the unit no longer compiles ' +
    'after formatting. Save the file as UTF-8 with BOM, or use an ASCII name.';
  MSG_207_FPC = 'Identifier ''%s'' contains non-ASCII letters - Free Pascal ' +
    'accepts only ASCII identifiers (A-Z, 0-9, _) and stops with "illegal ' +
    'character". Use an ASCII name.';

function IsLegacyDosEofOnly(const FileName: string): Boolean;
// FP-Gate (Real-World-Audit 2026-07-31, FP-Klasse 'legacy-dos-eof-marker'):
// True wenn das EINZIGE Kontrollbyte der Datei ein 0x1A (SUB / Ctrl-Z) ist und
// danach nur noch Whitespace (CR/LF/Tab/FF/Space) folgt. Das ist der historische
// DOS/Turbo-Pascal-EOF-Marker am Dateiende - kein Korruptionsindiz, die Datei
// kompiliert normal (Vorbild-FP: cnwizards PascalScript uPSC_std.pas).
// Eigener Roh-Byte-Read statt Cache-Feld: TFileEncodingInfo (geteilte
// Infrastruktur) traegt nur das Ja/Nein-Verdikt HasNulCtrl. Der Read kostet
// nichts im Normalfall - er laeuft NUR wenn ueberhaupt ein Kontrollbyte
// gefunden wurde (im Real-World-Korpus eine Handvoll Dateien).
// BOM-Bytes brauchen keine Sonderbehandlung: sie sind alle >= 0x80 und damit
// nie Kontrollbytes. Die Kontrollbyte-Definition spiegelt exakt
// ComputeFileEncodingInfo (0x00 oder < 0x20 ausser Tab/LF/FF/CR).
var
  Bytes  : TBytes;
  i, Len : Integer;
  b      : Byte;
  Ctrl   : Integer;
  EofPos : Integer;
begin
  Result := False;
  try
    if not TFile.Exists(FileName) then Exit;
    Bytes := TFile.ReadAllBytes(FileName);
  except
    if IsFatalScanException(ExceptObject) then raise;   // E3: Abbruch statt 'unlesbar'
    Exit;   // unlesbar -> kein Gate, bisheriges Verhalten
  end;
  Len    := Length(Bytes);
  Ctrl   := 0;
  EofPos := -1;
  for i := 0 to Len - 1 do
  begin
    b := Bytes[i];
    if (b = 0) or ((b < $20) and (b <> 9) and (b <> 10) and (b <> 12) and (b <> 13)) then
    begin
      if b <> $1A then Exit;      // anderes Kontrollbyte -> echter Fund
      Inc(Ctrl);
      if Ctrl > 1 then Exit;      // mehr als ein SUB -> kein EOF-Marker
      EofPos := i;
    end;
  end;
  if Ctrl <> 1 then Exit;
  // Hinter dem Marker darf nur noch Whitespace stehen (typisch CRLF).
  for i := EofPos + 1 to Len - 1 do
    if not (Bytes[i] in [9, 10, 12, 13, 32]) then Exit;
  Result := True;
end;

function HasSourceExt(const FileName: string): Boolean;
var
  Ext : string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  // Lazarus A3: die Dialekt-Endungen (.pp/.lpr bei dlFpc) kommen von
  // der EINEN Endungsfrage in TStaticFiles statt als fuenfte und
  // sechste Literale hier - A2 hatte dokumentiert, dass gesammelte
  // .pp sonst keine Encoding-Funde bekommen. Bei dlDelphi ist der
  // Zusatz kalt, die Vierer-Liste verhaelt sich wie seit jeher.
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc')
    or TStaticFiles.IsUnitLikeFile(FileName);
end;

function LineOr1(L: Integer): Integer; inline;
begin
  if L > 0 then Result := L else Result := 1;
end;

function IsDecodingTrustworthy(const Info: TFileEncodingInfo): Boolean;
// FP-Gate fuer S3 (Vollzaehlung SCA193 vom 2026-08-27: 3 Funde im GANZEN
// Korpus, jeder einzeln am Quelltext geprueft - 1 TP, 2 FP; beide FPs haben
// DIESELBE Wurzel). Wirkung dieses Gates: -2 Funde (3 -> 1), der TP bleibt.
//
// WARUM: S3 ist der einzige Check dieser Unit, der ueber DEKODIERTEN Text
// urteilt (TLexer auf Lines.Text). E5/S1/S2 laufen auf den Rohbytes und sind
// vom Dekodier-Ergebnis unabhaengig; E1/E3 entscheiden ueber die Bytes und
// setzen fuer den Text-Pfad ohnehin sbkNone+StrictUtf8 voraus. Ist eine Datei
// aber BOM-los UND kein gueltiges UTF-8, dekodiert uFileTextCache.LoadFileSmart
// sie mit TEncoding.Default - der aktiven System-Codepage der Maschine, die
// den Scan faehrt (hier CP1252). Damit entstehen Buchstaben, die in der echten
// Quell-Codepage gar nicht existieren (im Korpus: GBK-Bytes werden zu ganz
// anderen Zeichen umgedeutet). S3 faellt dann ein Homoglyph-Urteil ueber
// erfundene Zeichen - exakt die 2 FPs. Kein Deckungsverlust: Gruppe A meldet
// so eine Datei ohnehin, bei den beiden Korpus-Faellen durch die ehrliche
// Regel E3 (fkSourceAnsiNonAscii, "codepage-abhaengig / nicht portabel").
//
// Vertrauenswuerdig = die Encoding-Wahl in LoadFileSmart war NICHT geraten:
//   * sbkUtf8       - BOM sagt UTF-8, LoadFileSmart nimmt UTF-8.
//   * sbkUtf16LE/BE - BOM sagt UTF-16; TEncoding.GetBufferEncoding trifft
//                     diese BOM sicher. BOM-gesteuert ist genauso zuverlaessig
//                     wie UTF-8 und gehoert deshalb dazu (Skeptiker-Nachtrag:
//                     die enge Fassung "sbkUtf8 oder (sbkNone und StrictUtf8)"
//                     haette UTF-16-Quellen grundlos ausgeschlossen).
//   * sbkNone + StrictUtf8 - kein BOM, aber der strikte RFC-3629-Walk
//                     bestaetigt UTF-8. Strikt ist eine TEILMENGE des lenienten
//                     IsValidUtf8 in LoadFileSmart -> die Datei wurde dort
//                     garantiert als UTF-8 dekodiert.
// NICHT dabei:
//   * sbkNone ohne StrictUtf8 -> TEncoding.Default = Rate-Pfad (die 2 FPs).
//   * sbkUtf32LE/BE -> LoadFileSmart kennt kein UTF-32: GetBufferEncoding
//     matcht bei FF FE 00 00 die UTF-16LE-BOM, der Rest wird Muell. UTF-32 als
//     "vertrauenswuerdig" zu fuehren waere sachlich falsch.
// Beide UTF-16/UTF-32-Zweige sind heute praktisch folgenlos: E4/E7 verlassen
// AnalyzeUnit schon VOR dem S3-Block, diese BomKinds erreichen die Funktion
// also nie. Die Liste beschreibt trotzdem die Dekodier-Wahrheit - fuer den
// Fall, dass der Frueh-Exit spaeter wandert.
//
// Bewusst konservativ: BOM-los + lenient-gueltiges, aber strikt-ungueltiges
// UTF-8 (ueberlang / Surrogat) gilt hier als nicht vertrauenswuerdig, obwohl
// LoadFileSmart dort UTF-8 nimmt. Das Gate darf ausschliesslich Funde
// ENTFERNEN, nie neue erzeugen (Monotonie) - im Zweifel also schweigen.
begin
  Result := (Info.BomKind in [sbkUtf8, sbkUtf16LE, sbkUtf16BE])
            or ((Info.BomKind = sbkNone) and Info.StrictUtf8);
end;

class function TSourceEncodingDetector.IsKnownHomoglyph(C: Char): Boolean;
var
  Code : Word;
begin
  for Code in HOMOGLYPH_CODES do
    if Ord(C) = Code then Exit(True);
  Result := False;
end;

procedure ScanNonAsciiTokens(const Source: string;
  out AnyOutside, HomoglyphInIdent: Boolean; out IdentLine: Integer);
// EIN Lex-Durchgang. Der TLexer verwirft Kommentare (//, { }, (* *), {$..}) und
// liefert nur Code-/String-/Unknown-Tokens - ein Nicht-ASCII-Zeichen im Token-
// Value steht also NICHT in einem Kommentar.
//   AnyOutside       = Nicht-ASCII in irgendeinem Token (String ODER Code) ->
//                      E1-Confidence (fcMedium statt fcLow).
//   HomoglyphInIdent = BEKANNTER HOMOGLYPH (HOMOGLYPH_CODES) in einem
//                      Identifier/Code-Token (tkIdent/tkUnknown) -> Confusable-
//                      Vektor (S3); IdentLine = dessen Zeile.
//                      Entscheid Nico 2026-11-06: bis dahin zaehlte jeder
//                      Nicht-ASCII-BUCHSTABE (Letter-only-Guard 2026-07-25) -
//                      auch ein Umlaut, der nichts vortaeuscht. Ein Umlaut-
//                      Bezeichner ist kein Homoglyph; wo er wirklich bricht,
//                      meldet ihn S4 (SCA207) mit Namen. Die Tabelle enthaelt
//                      nur Buchstaben, Symbole (U+2026, Dreiecke) bleiben
//                      draussen wie beim Letter-only-Guard.
//                      AnyOutside bleibt bewusst ungefiltert (E1-Mojibake-
//                      Risiko gilt fuer JEDES Nicht-ASCII).
// (Randfall: der Lexer dekodiert #$nnnn-Char-Literale zu echten Zeichen - fuer
// die Detektor-Nutzung irrelevant, weil beide Aufrufer rohes Nicht-ASCII per
// AnalyzeFileEncoding.HasNonAscii voraussetzen.)
var
  Lex        : TLexer;
  Tok        : TToken;
  ch         : Char;
  TokHasNA   : Boolean;
  TokHasHG   : Boolean;   // Nicht-ASCII-Zeichen ist ein bekannter Homoglyph
begin
  AnyOutside       := False;
  HomoglyphInIdent := False;
  IdentLine        := 0;
  if Source = '' then Exit;
  Lex := TLexer.Create(Source);
  try
    Tok := Lex.Next;
    while Tok.Kind <> tkEof do
    begin
      TokHasNA := False;
      TokHasHG := False;
      for ch in Tok.Value do
        if Ord(ch) >= $80 then
        begin
          TokHasNA := True;
          // Weitersuchen bis ein bekannter Homoglyph gefunden ist - erst
          // der macht das Token zum S3-Kandidaten.
          if TSourceEncodingDetector.IsKnownHomoglyph(ch) then
          begin
            TokHasHG := True;
            Break;
          end;
        end;
      if TokHasNA then
      begin
        AnyOutside := True;
        if TokHasHG and (Tok.Kind in [tkIdent, tkUnknown])
           and not HomoglyphInIdent then
        begin
          HomoglyphInIdent := True;
          IdentLine        := Tok.Line;
        end;
      end;
      if AnyOutside and HomoglyphInIdent then Break;   // beide Fakten gefunden
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

class function TSourceEncodingDetector.HasHomoglyphIdentifier(
  const Source: string): Boolean;
var Outside: Boolean; Ln: Integer;
begin
  ScanNonAsciiTokens(Source, Outside, Result, Ln);
end;

// ---- S4: Code-Sicht und Bezeichner-Laeufe (SCA207) ------------------------
//
// WARUM EINE EIGENE CODE-SICHT: der TLexer (ReadIdent) und uParser2 lesen
// nur ASCII-Bezeichner - 'Groesse' mit oe-Umlaut kommt dort als 'Gr' +
// tkUnknown + tkUnknown + 'e' an, ein Name entsteht nie. S4 braucht den
// ganzen Namen. TDetectorUtils.StripStringsAndCommentsCached liefert zwar
// die Code-Sicht, kennt aber (wie ScanCodeLine) keine Delphi-12-
// Mehrzeilenstrings: deren Textzeilen gingen als Code durch, ein Satz mit
// Umlaut im Mehrzeilenstring waere ein Schein-Bezeichner. Der Lauf unten
// folgt daher den Regeln von ScanCodeLine ('..' mit '', { } bis zum ersten
// }, (* *) bis zum ersten *), // bis Zeilenende, {$..} ist Kommentar) plus
// den Mehrzeilenstrings wie uFormatterMarker (ungerade Folge von
// mindestens drei Apostrophen, nur Leerraum dahinter; Ende an der Zeile,
// die nach Leerraum mit derselben Folge beginnt). Spaltentreu: alles, was
// nicht Code ist, wird Leerzeichen.

type
  TCodeViewWalker = record
    InBrace  : Boolean;   // { } ueber das Zeilenende offen
    InParen  : Boolean;   // (* *) ueber das Zeilenende offen
    MultiRun : Integer;   // > 0: offener Mehrzeilenstring, Laenge der Folge
    function ViewOf(const ALine: string): string;
  end;

// Laenge der Apostroph-Folge ab ALine[AIdx].
function QuoteRun(const ALine: string; AIdx: Integer): Integer;
begin
  Result := 0;
  while (AIdx + Result <= Length(ALine)) and (ALine[AIdx + Result] = '''') do
    Inc(Result);
end;

procedure BlankRange(var AView: string; AFrom, ATo: Integer);
var
  k : Integer;
begin
  if ATo > Length(AView) then ATo := Length(AView);
  for k := AFrom to ATo do
    AView[k] := ' ';
end;

// Ende des '..'-Strings, der bei AStart oeffnet ('' bleibt im String); ohne
// schliessendes Apostroph das Zeilenende.
function StringEnd(const ALine: string; AStart: Integer): Integer;
begin
  Result := AStart + 1;
  while Result <= Length(ALine) do
  begin
    if ALine[Result] = '''' then
    begin
      if (Result < Length(ALine)) and (ALine[Result + 1] = '''') then
        Inc(Result, 2)
      else
        Exit;
    end
    else
      Inc(Result);
  end;
end;

function TCodeViewWalker.ViewOf(const ALine: string): string;
var
  j, p, n, Run : Integer;
begin
  Result := ALine;
  n := Length(ALine);
  j := 1;
  if MultiRun > 0 then
  begin
    while (j <= n) and (ALine[j] <= ' ') do Inc(j);
    if QuoteRun(ALine, j) <> MultiRun then
      Exit(StringOfChar(' ', n));            // Zeile im Mehrzeilenstring
    BlankRange(Result, 1, j + MultiRun - 1);
    Inc(j, MultiRun);
    MultiRun := 0;
  end;
  while j <= n do
  begin
    if InBrace or InParen then
    begin
      if InBrace then p := PosEx('}', ALine, j) else p := PosEx('*)', ALine, j);
      if p = 0 then
      begin
        BlankRange(Result, j, n);
        Exit;
      end;
      if InParen then Inc(p);                // '*)' ist zwei Zeichen lang
      BlankRange(Result, j, p);
      InBrace := False;
      InParen := False;
      j := p + 1;
    end
    else if ALine[j] = '''' then
    begin
      Run := QuoteRun(ALine, j);
      if (Run >= MIN_MULTI_QUOTES) and Odd(Run)
         and (Trim(Copy(ALine, j + Run, MaxInt)) = '') then
      begin
        MultiRun := Run;
        BlankRange(Result, j, n);
        Exit;
      end;
      p := StringEnd(ALine, j);
      BlankRange(Result, j, p);
      j := p + 1;
    end
    else if (ALine[j] = '/') and (j < n) and (ALine[j + 1] = '/') then
    begin
      BlankRange(Result, j, n);
      Exit;
    end
    else if ALine[j] = '{' then
    begin
      InBrace := True;                       // '}' wird ab j + 1 gesucht
      BlankRange(Result, j, j);
      Inc(j);
    end
    else if (ALine[j] = '(') and (j < n) and (ALine[j + 1] = '*') then
    begin
      InParen := True;                       // '(*)' oeffnet nur
      BlankRange(Result, j, j + 1);
      Inc(j, 2);
    end
    else
      Inc(j);
  end;
end;

// Anfang eines Bezeichners: ASCII-Buchstabe, '_' oder ein Nicht-ASCII-
// Buchstabe (L*). ARaw: jedes Zeichen >= #$80 (ANSI unter dlFpc).
// Surrogate (Zeichen jenseits U+FFFF) sind keine Buchstaben - Grenze, im
// Test festgehalten.
function IsIdentStart(C: Char; ARaw: Boolean): Boolean;
begin
  if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) then Exit(True);
  if Ord(C) < $80 then Exit(False);
  Result := ARaw or C.IsLetter;
end;

// Fortsetzung eines Bezeichners: Anfangszeichen, ASCII-Ziffer, sonst (nicht
// ARaw) Nicht-ASCII-Ziffer (Nd) oder kombinierendes Zeichen (Mn/Mc).
function IsIdentPart(C: Char; ARaw: Boolean): Boolean;
begin
  if IsIdentStart(C, ARaw) or CharInSet(C, ['0'..'9']) then Exit(True);
  if (Ord(C) < $80) or ARaw then Exit(False);
  Result := C.GetUnicodeCategory in [TUnicodeCategory.ucDecimalNumber,
    TUnicodeCategory.ucNonSpacingMark, TUnicodeCategory.ucCombiningMark];
end;

function HasNonAsciiChar(const S: string): Boolean;
var
  C : Char;
begin
  for C in S do
    if Ord(C) >= $80 then Exit(True);
  Result := False;
end;

class function TSourceEncodingDetector.FragileNames(ALines: TStrings;
  ARaw: Boolean; out ANameLines: TArray<Integer>): TArray<string>;
var
  Walker : TCodeViewWalker;
  Seen   : TDictionary<string, Boolean>;
  View   : string;
  Name   : string;
  i, k   : Integer;
  Start  : Integer;
begin
  Result := nil;
  ANameLines := nil;
  Walker := Default(TCodeViewWalker);
  Seen := TDictionary<string, Boolean>.Create;
  try
    for i := 0 to ALines.Count - 1 do
    begin
      // Zeilen ohne Nicht-ASCII tragen keinen Namen, aber Zustand (offener
      // Kommentar bzw. Mehrzeilenstring) - der Lauf geht trotzdem darueber.
      View := Walker.ViewOf(ALines[i]);
      if not HasNonAsciiChar(View) then Continue;
      k := 1;
      while k <= Length(View) do
      begin
        if not IsIdentStart(View[k], ARaw) then
        begin
          Inc(k);
          Continue;
        end;
        Start := k;
        while (k <= Length(View)) and IsIdentPart(View[k], ARaw) do Inc(k);
        Name := Copy(View, Start, k - Start);
        // Ein '&' davor (Escape eines reservierten Worts) steht nicht im
        // Lauf - der Name kommt ohne.
        if HasNonAsciiChar(Name) and not Seen.ContainsKey(AnsiLowerCase(Name)) then
        begin
          Seen.Add(AnsiLowerCase(Name), True);
          Result := Result + [Name];
          ANameLines := ANameLines + [i + 1];
        end;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

procedure AddFragileIdentifiers(const FileName: string;
  const Info: TFileEncodingInfo; Lines: TStrings;
  Results: TObjectList<TLeakFinding>);
// S4 fkFragileNonAsciiIdentifier (SCA207, Nico-Entscheide 2026-11-06). Nur
// belegte Faelle:
//   dlDelphi - nur UTF-8 OHNE BOM (sbkNone + StrictUtf8): genau die Dateien,
//     die die Delphi-IDE und der Formatter (Formatter.exe, Strg+D bis
//     Delphi 12) als ANSI lesen; der Formatter haelt das zweite UTF-8-Byte
//     fuer ein Satzzeichen und setzt Leerzeichen in den Namen (Probe
//     2026-11-06). Mit BOM, UTF-16 und echtem ANSI bleibt der Name heil -
//     kein Fund. Warning, fcMedium (Kind-Default): welche Buchstaben
//     brechen, haengt an der Codepage des formatierenden Rechners.
//   dlFpc - jede Datei: FPC nimmt nur ASCII-Bezeichner ('illegal
//     character', in jedem Encoding belegt). Error, fcHigh (Baubruch, wie
//     SCA190 unter dlFpc). Ist die Dekodierung geraten (ANSI), ist der Name
//     es auch - dann zaehlt jedes Zeichen >= #$80 im Code und die Meldung
//     nennt keinen Namen.
// Ein Fund je verschiedenem Namen, an seiner ersten Zeile, ohne Deckel.
// Kommentare, Direktiven und Strings zaehlen nicht (TCodeViewWalker).
// UTF-16/UTF-32 kommen hier nie an (AnalyzeUnit verlaesst die Datei vorher).
var
  Names     : TArray<string>;
  NameLines : TArray<Integer>;
  Fpc, Raw  : Boolean;
  i         : Integer;
  F         : TLeakFinding;
begin
  Fpc := TStaticFiles.ScanDialect = dlFpc;
  if Fpc then
    Raw := not IsDecodingTrustworthy(Info)
  else
  begin
    if not ((Info.BomKind = sbkNone) and Info.StrictUtf8) then Exit;
    Raw := False;
  end;
  Names := TSourceEncodingDetector.FragileNames(Lines, Raw, NameLines);
  for i := 0 to High(Names) do
  begin
    if not Fpc then
      F := TLeakFinding.New(FileName, '', NameLines[i],
        Format(MSG_207_DELPHI, [Names[i]]), fkFragileNonAsciiIdentifier)
    else
    begin
      if Raw then
        F := TLeakFinding.New(FileName, '', NameLines[i],
          N_('Identifier with a non-ASCII character in a file that is not ' +
            'UTF-8 - Free Pascal accepts only ASCII identifiers (A-Z, 0-9, _) ' +
            'and stops with "illegal character". Use an ASCII name.'),
          fkFragileNonAsciiIdentifier)
      else
        F := TLeakFinding.New(FileName, '', NameLines[i],
          Format(MSG_207_FPC, [Names[i]]), fkFragileNonAsciiIdentifier);
      F.Severity := lsError;
      F.Confidence := fcHigh;
    end;
    Results.Add(F);
  end;
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
  // Perf P2 (Konzept_Performance25, 2026-07-19): Verdikt aus dem Text-Cache
  // (beim Load aus den Rohbytes berechnet) statt kompletter Zweit-Read;
  // ohne Cache-Eintrag identischer AnalyzeFileEncoding-Pfad wie bisher.
  Info := AcquireEncodingInfo(FileName, CtxFileTextCache(AContext));
  if not Info.Readable then Exit;   // Read-Fehler -> FileReadError deckt das ab

  // UTF-32/UTF-16-Quelltext: BOM-bestimmter Ganzdatei-Verdikt -> emittieren und
  // RAUS. Der Byte-Walk interpretiert die Bytes als UTF-8 (fuer UTF-16 unsinnig),
  // NUL-Bytes sind dort Encoding, und ein Bidi-Scan waere ebenfalls sinnlos.
  if Info.BomKind in [sbkUtf32LE, sbkUtf32BE] then
  begin
    Results.Add(TLeakFinding.New(FileName, '', 1,
      'UTF-32 / UCS-4 source file - no Pascal compiler accepts this ' +
      '(Delphi: fatal F2438 "UCS-4 text encoding not supported"). Convert ' +
      'the file to UTF-8 (with BOM) or UTF-16.',
      fkSourceUtf32));
    Exit;
  end;
  if Info.BomKind in [sbkUtf16LE, sbkUtf16BE] then
  begin
    // G2 (2026-09-19, Untersuchungs-Posten 3.5): FPC LEHNT
    // UTF-16-Quelltext AB - unter dlFpc ist die Datei nicht
    // 'unusual, but compiles', sondern baut schlicht nicht.
    // Severity dann Error und ein Text ohne das 'It compiles';
    // unter dlDelphi bleibt Meldung und Hint-Stufe unveraendert
    // (Fund-Identitaet der Delphi-Referenz unberuehrt).
    // Referenz-Bewegung: null - der Lazarus-Korpus traegt keine
    // UTF-16-Datei, der Delphi-Korpus laeuft unter dlDelphi.
    if TStaticFiles.ScanDialect = dlFpc then
    begin
      var F := TLeakFinding.New(FileName, '', 1,
        'UTF-16 source file. Free Pascal rejects UTF-16 source - the ' +
        'file does not compile under FPC. Re-encode it as UTF-8.',
        fkSourceUtf16);
      F.Severity := lsError;
      // Kind-Default ist fcLow (als Stilfrage bewusst leise, im
      // Default-Lauf unter MinConfidence=fcMedium unsichtbar). Ein
      // Baubruch ist keine Stilfrage, und der BOM-Beweis ist hart -
      // unter dlFpc muss der Fund jeden Lauf erreichen.
      F.Confidence := fcHigh;
      Results.Add(F);
    end
    else
      Results.Add(TLeakFinding.New(FileName, '', 1,
        'UTF-16 source file. It compiles, but UTF-16 source is unusual and causes ' +
        'friction with text tools (git diff, grep, external hooks). Convention is ' +
        'UTF-8 with BOM.',
        fkSourceUtf16));
    Exit;
  end;

  // ---- Gruppe B (Security), orthogonal zu allen Encoding-Gates ------------
  //
  // ABER NICHT ORTHOGONAL ZUR ENCODING-FRAGE (Chargen-Review 2026-09-14,
  // Posten 304): S1 und S2 suchen UTF-8-Sequenzen im Bytestrom. In einer
  // Datei, die dieser Detektor GERADE SELBST als ANSI eingestuft hat
  // (kein BOM, kein gueltiges UTF-8, s. E3 weiter unten), ist diese
  // Lesart unbegruendet: der Compiler liest die Bytes dort als
  // Codepage-Zeichen. Die drei Bytes E2 80 AE sind in Latin-1 schlicht
  // 'a-Zirkumflex, Euro, Registered' - kein Trojan-Source-Risiko.
  //
  // An der Exe belegt: eine Datei mit Latin-1-Umlauten (also
  // UNGUELTIGEM UTF-8) UND der Bytefolge E2 80 AE bekam sowohl
  // SourceAnsiNonAscii ALS AUCH SourceBidiOverride - zwei Verdikte, die
  // einander widersprechen.
  //
  // Korpuswirkung 0: der Referenzlauf hat weder SourceBidiOverride noch
  // SourceZeroWidth ueberhaupt einen Fund. Das Gate ist Vorsorge.
  //
  // UTF-8 OHNE BOM bleibt ausdruecklich drin: dort ist die Bytefolge
  // gueltiges UTF-8 und die Warnung berechtigt. Ausgenommen wird nur
  // der Fall 'kein BOM UND kein gueltiges UTF-8'.
  var IstAnsi := (Info.BomKind = sbkNone) and Info.HasNonAscii
                 and (not Info.StrictUtf8);
  if Info.HasBidi and (not IstAnsi) then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstBidiLine),
      'Bidirectional override control character (e.g. U+202E) - Trojan Source ' +
      'risk (CVE-2021-42574): the code can read differently than it compiles. ' +
      'Remove the control character.',
      fkSourceBidiOverride));
  if Info.HasZeroWidth and (not IstAnsi) then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstZeroWidthLine),
      'Invisible / zero-width character (e.g. U+200B) in source - hidden-text ' +
      'abuse vector (CWE-1007). Almost never legitimate; remove it (U+200D can ' +
      'appear in emoji string literals - verify before removing there).',
      fkSourceInvisibleChar));

  // Token-basierte Analyse: EIN Lex-Durchgang, aber nur wenn die Datei ueberhaupt
  // Nicht-ASCII enthaelt (reine ASCII-Dateien = kein Lex-Aufwand). Liefert Outside
  // (Nicht-ASCII in String/Code -> E1-Confidence) und Ident (bekannter Homoglyph
  // in einem Identifier -> S3). Auf denselben Zeilen laeuft S4 (SCA207).
  Outside := False; Ident := False; IdentLine := 0;
  if Info.HasNonAscii then
  begin
    Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
    if Lines <> nil then
      try
        ScanNonAsciiTokens(Lines.Text, Outside, Ident, IdentLine);
        AddFragileIdentifiers(FileName, Info, Lines, Results);
      finally
        ReleaseLines(Lines, Cached);
      end;
  end;

  // S3 (Security, orthogonal): Homoglyph-/Confusable-Identifier. Feuert auch in
  // korrektem UTF-8+BOM (ein Cyrillic-Homoglyph in einem Identifier ist dort
  // genauso gefaehrlich) - aber NUR wenn der dekodierte Text die Quelle
  // wirklich wiedergibt. Ohne dieses Gate urteilt S3 in codepage-geratenen
  // Dateien ueber erfundene Buchstaben (Vollzaehlung 2026-08-27: 2 der 3
  // Korpus-Funde waren genau das). Begruendung: IsDecodingTrustworthy.
  // Der Lex-Durchgang oben bleibt ungegatet - er liefert zusaetzlich Outside
  // fuer die E1-Confidence, und E1 feuert nur im vertrauenswuerdigen Fall
  // (sbkNone + StrictUtf8), ist von diesem Gate also unberuehrt.
  // Seit 2026-11-06 nur bekannte Homoglyphen (ScanNonAsciiTokens). Der
  // Meldetext bleibt WORTGLEICH: er ist Teil der Fund-Identitaet (SARIF-
  // Fingerprint, Baseline), und er stimmt fuer einen Homoglyph weiterhin.
  if Ident and IsDecodingTrustworthy(Info) then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(IdentLine),
      'Non-ASCII character in an identifier - homoglyph / confusable risk ' +
      '(Trojan Source, CWE-1007): a letter such as Cyrillic U+043E looks like ' +
      'Latin "o" but binds to a different symbol. Prefer ASCII identifiers; if a ' +
      'Unicode identifier is intentional, avoid mixing scripts.',
      fkSourceNonAsciiIdentifier));

  // ---- Gruppe A (Encoding): genau EIN Fund, Praezedenz E5 > E2 > E1 > E3 --
  if Info.HasNulCtrl then
  begin
    // FP-Gate 2026-07-31 (FP-Klasse 'legacy-dos-eof-marker'): ein einzelnes
    // 0x1A als letztes Nicht-Whitespace-Byte ist der DOS-EOF-Marker, keine
    // Korruption -> E5 entfaellt. Der GESAMTE Gruppe-A-Block faellt damit aus
    // (kein Durchfallen auf E2/E1/E3): das Gate darf ausschliesslich Funde
    // ENTFERNEN, nie einen anderen Fund neu erzeugen (Monotonie).
    if not IsLegacyDosEofOnly(FileName) then
      Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNulCtrlLine),
        'NUL or control byte in source file - likely a binary file or a ' +
        'mis-detected encoding (e.g. BOM-less UTF-16, where every other byte is 0x00).',
        fkSourceControlChar));
  end
  else if (Info.BomKind = sbkUtf8) and (not Info.StrictUtf8) then
    Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstInvalidLine),
      'Invalid UTF-8 sequence under a UTF-8 BOM (overlong / surrogate / ' +
      'out-of-range code point). The compiler silently substitutes ' +
      'U+FFFD -> data corruption. Re-encode the file as clean UTF-8.',
      fkSourceInvalidUtf8))
  else if (Info.BomKind = sbkNone) and Info.HasNonAscii and Info.StrictUtf8 then
  begin
    // Lazarus-Folge B1 (2026-09-19): unter dlFpc ist BOM-loses UTF-8
    // die NORM - die Lazarus-IDE speichert selbst ohne BOM, FPC liest
    // UTF-8 per Default (der Meldetext unten sagt es woertlich). E1
    // beschreibt also reines DELPHI-Compilerverhalten und waere unter
    // dlFpc strukturell 100 % FP (fpc-Lauf 19.09.: 76 Funde, alle
    // dieser Klasse). Gleiches Gate-Muster wie SCA129/SCA041. E3
    // (echtes 8-bit-ANSI, unten) bleibt bewusst AKTIV - das ist auch
    // unter FPC nicht portabel; nach E1 kann keine andere Meldung
    // dieser Kette mehr greifen (else-if, E3 verlangt not StrictUtf8),
    // das Exit erzeugt daher nie ein Durchfallen.
    if TStaticFiles.ScanDialect = dlFpc then Exit;
    // E1: Nicht-ASCII ohne BOM. Outside (oben in EINEM Lex-Durchgang ermittelt)
    // bestimmt die Confidence: String-Literal/Code = echtes Laufzeit-Mojibake
    // (fcMedium); nur Kommentar = der Compiler verwirft Kommentare (fcLow, opt-in).
    if Outside then
      Results.Add(TLeakFinding.New(FileName, '', LineOr1(Info.FirstNonAsciiLine),
        'UTF-8 without BOM: non-ASCII in a string literal or identifier. ' +
        'Delphi reads BOM-less files as ANSI (GetACP, e.g. CP-1252) -> ' +
        'mojibake at runtime; FPC defaults to UTF-8. Fix: save as UTF-8 ' +
        'WITH BOM, or build with --codepage:65001.',
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
