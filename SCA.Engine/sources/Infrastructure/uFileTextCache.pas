unit uFileTextCache;

// Datei-Text-Cache fuer File-Scan-Detektoren (uTodoComment, uWithStatement,
// uReversedForRange, uLengthUnderflow, uTautologicalExpr, uDuplicateBlock,
// uCustomRuleDetector).
//
// Hintergrund (tools/perf_analyse.md Hot-Spot 🅑):
// Diese 7 Detektoren rufen jeweils Lines.LoadFromFile auf - pro .pas-Datei
// 7+ separate Disk-IO-Operationen + Encoding-Erkennung + TStringList-
// Allokationen. Mit diesem Cache wird pro Datei einmal eingelesen und
// alle Detektoren bedienen sich aus derselben TStringList.
//
// Ownership-Modell:
//   AcquireLines(FileName, out OwnedByCache) liefert eine TStringList.
//     * Wenn OwnedByCache=True (Cache-Pfad): nicht freigeben - der Cache
//       managed das Leben.
//     * Wenn OwnedByCache=False (Fallback): Caller MUSS Lines.Free
//       aufrufen wenn fertig.
//
//   Pragmatische Convenience: ReleaseLines(Lines, OwnedByCache) macht
//   genau das richtige - so kann der Caller einheitlich
//     Lines := AcquireLines(FileName, Cached); try ... finally
//       ReleaseLines(Lines, Cached); end;
//
// Lifecycle (aktualisiert 2026-07-04, Audit Global-State):
//   gFileTextCache ist EINE prozessweit stabile Instanz: beim ersten
//   Scan-Start erzeugt (uStaticAnalyzer2), bei jedem weiteren Scan-Start
//   nur GECLEART - die Objekt-Identitaet wechselt nie, haengende Referenzen
//   auf das Cache-Objekt bleiben gueltig (kein Use-after-free mehr durch
//   FreeAndNil + Re-Create). Waehrend des Scans leert der Main-Loop die
//   Eintraege nach jedem File (Memory-Peak); nach dem Scan lebt der Cache
//   absichtlich weiter (Suppression-/ContextHash-Phase fuellt ihn lazy
//   nach) und wird erst im finalization-Block freigegeben.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TFileTextCacheEntry = class
  public
    Lines : TStringList;
    MTime : TDateTime;
    Size  : Int64;
    // Perf (2026-07-05): P2-filetextcache-stat - Cache-Generation des letzten
    // Disk-Stat-Checks dieses Eintrags. Solange die Generation des Caches
    // unveraendert ist, skippt GetLines den Stat (siehe dort).
    StatGeneration : Integer;
    constructor Create(ALines: TStringList; AMTime: TDateTime; ASize: Int64;
      AStatGeneration: Integer);
    destructor Destroy; override;
  end;

  TFileTextCache = class
  private
    FCache : TObjectDictionary<string, TFileTextCacheEntry>;
    // Perf (2026-07-05): P2-filetextcache-stat - Generation-Zaehler.
    // Clear bumpt ihn; Eintraege merken sich die Generation ihres letzten
    // Stat-Checks. Innerhalb einer Generation (= innerhalb eines Scan-
    // Abschnitts) gilt der Cache als Snapshot -> kein FileAge/
    // GetFileAttributesEx pro Cache-Hit mehr (~60-80x pro Datei durch die
    // File-Scan-Detektoren + ~770k Hits ueber den Fingerprint-Pfad).
    FGeneration : Integer;
    // Perf (2026-07-05): P2-filetextcache-stat - 1-Slot-Memo fuer die
    // Key-Normalisierung (LowerCase+ExpandFileName kostet einen
    // GetFullPathName-Roundtrip pro Aufruf; dieselbe Datei wird von den
    // Detektoren aber direkt hintereinander angefragt). Nur fuer bereits
    // absolute Pfade aktiv - relative Pfade haengen vom cwd ab und werden
    // nicht memoisiert.
    FLastName : string;
    FLastKey  : string;
    function Key(const FileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Liefert TStringList fuer FileName. Cache besitzt die Liste -
    // NICHT freigeben. Nil bei Read-Fehler.
    // Staleness-Modell (Perf 2026-07-05, P2-filetextcache-stat):
    //   * Innerhalb einer Generation (zwischen zwei Clear-Aufrufen) ist der
    //     Cache ein Snapshot - KEIN Disk-Stat pro Hit. Ein Scan ist per
    //     Definition ein Snapshot des Datei-Standes.
    //   * Cross-Scan bleibt das Verhalten identisch: der Scan-Start
    //     (uStaticAnalyzer2.ParseLeaks) ruft Clear -> Generation-Bump +
    //     alle Eintraege werden zerstoert -> naechster Zugriff laedt frisch.
    //     Edit-Loops im IDE-Plugin sind damit abgedeckt (jeder Lauf geht
    //     durch ParseLeaks). Konsumenten OHNE dazwischenliegendes Clear,
    //     die Ueberschreibungen sehen muessen (Fingerprint/Baseline-Drift,
    //     direkte TBaseline.Write/Apply-Aufrufe), nutzen AForceStat=True.
    //   * Der mtime+Size-Vergleich bleibt als Belt-and-Suspenders fuer
    //     Eintraege mit aelterer Stat-Generation bestehen.
    //   * AForceStat=True erzwingt den mtime+Size-Recheck auch innerhalb
    //     der aktuellen Generation - fuer Konsumenten, die Datei-
    //     Ueberschreibungen ohne zwischenzeitliches Clear sehen MUESSEN
    //     (Fingerprint-/Baseline-Drift-Pfad, s. GetLines-Implementierung).
    function GetLines(const FileName: string;
      AForceStat: Boolean = False): TStringList;

    procedure Clear;
  end;

var
  // Optional. Wenn nil (Tests, Single-File-Pfad), faellt AcquireLines auf
  // einen frischen LoadFromFile-Roundtrip zurueck.
  // KEIN threadvar: dieses Global liegt in der Interface-Section einer
  // Package-Unit (SCA.Engine.dpk) -> ein exportierter Package-threadvar
  // loest W1032 aus und kann ueber Package-Grenzen NICHT zuverlaessig
  // genutzt werden. Thread-Safety fuer parallele Scans laeuft ueber
  // TAnalyzeContext (Ctx.FileTextCache), nicht ueber dieses Backward-Compat-
  // Global. (TD-1 threadvar-Ansatz verworfen, vgl. DetectorEnabledKinds.)
  gFileTextCache : TFileTextCache = nil;

// Bequemer Wrapper fuer File-Scan-Detektoren - liefert Lines + Ownership-
// Flag. Caller-Muster:
//   var Lines: TStringList; Cached: Boolean;
//   Lines := AcquireLines(FileName, Cached);
//   if Lines = nil then Exit;
//   try
//     // ... use Lines ...
//   finally
//     ReleaseLines(Lines, Cached);
//   end;
// ACache (optional): der per-Scan-Cache aus dem TAnalyzeContext. nil -> das
// Prozess-Global gFileTextCache (Backward-Compat / Single-File / Tests). Phase-3-
// Schritt: Detektoren reichen kuenftig AContext.FileTextCache durch, damit der
// Cache nicht mehr global geteilt wird.
// AForceStat: siehe TFileTextCache.GetLines - True nur fuer den
// Fingerprint-/Baseline-Drift-Pfad (aktueller Datei-Inhalt Pflicht).
function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean; ACache: TFileTextCache = nil;
  AForceStat: Boolean = False): TStringList;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);

// Standalone-Loader mit Encoding-Detection (Default -> UTF8 -> Unicode).
// Caller besitzt Lines. False bei Read-/Decode-Fehler.
// Wird von Code-Pfaden genutzt, die nicht ueber den Cache laufen
// (Pre-Index-Scans, Single-File-Tools). Vorher 3-fach try-fallback
// inline in uSuppression - jetzt single source of truth hier.
function TryLoadLinesWithFallback(const FileName: string;
  Lines: TStringList): Boolean;

type
  // Byte-Level-Encoding-Fakten einer Quelldatei (fuer den Encoding-Detektor,
  // Konzept_FileEncodingDetector). Auf der POST-BOM-Slice berechnet - die
  // BOM-Bytes selbst zaehlen NICHT als "Nicht-ASCII".
  TSourceBomKind = (sbkNone, sbkUtf8, sbkUtf16LE, sbkUtf16BE, sbkUtf32LE, sbkUtf32BE);
  TFileEncodingInfo = record
    Readable          : Boolean;   // Datei lesbar
    BomKind           : TSourceBomKind;
    HasNonAscii       : Boolean;   // Byte >= $80 nach der BOM
    StrictUtf8        : Boolean;   // Post-BOM = striktes RFC-3629-UTF-8 (reines ASCII = True)
    HasMultiByte3Up   : Boolean;   // >=1 Drei-/Vier-Byte-UTF-8-Sequenz (Evidenz fuer E1-High)
    MultiByteRuns     : Integer;   // Anzahl Multi-Byte-Sequenzen (Evidenz)
    HasNulCtrl        : Boolean;   // 0x00 / Ctrl<0x20 (ausser Tab/LF/FF/CR)
    HasBidi           : Boolean;   // bidirektionales Override-Steuerzeichen (Trojan Source)
    HasZeroWidth      : Boolean;   // unsichtbares / Zero-Width-Zeichen (Unicode-Abuse)
    FirstNonAsciiLine : Integer;   // 1-basiert; 0 = keine
    FirstInvalidLine  : Integer;
    FirstNulCtrlLine  : Integer;
    FirstBidiLine     : Integer;
    FirstZeroWidthLine: Integer;
  end;

// Byte-Level-Encoding-Analyse einer Datei. Eigener ReadAllBytes: der Text-
// Cache haelt nur dekodierte Strings OHNE BOM, die Encoding-Wahrheit steckt
// nur in den Rohbytes. Readable=False wenn nicht lesbar (dann greift der
// FileReadError-Pfad). (Follow-up laut Konzept: Cache-Piggyback zur Vermeidung
// des Zweit-Reads.)
function AnalyzeFileEncoding(const FileName: string): TFileEncodingInfo;
// Reiner Analyse-Kern (fuer Tests direkt mit TBytes aufrufbar).
function ComputeFileEncodingInfo(const Bytes: TBytes): TFileEncodingInfo;

implementation

// noinspection-file BooleanParam, CanBeClassMethod, CanBeStrictPrivate, CanBeUnitPrivate, ClassPerFile, CyclomaticComplexity, DeepNesting, EmptyExcept, GroupedDeclaration, NestedTry, NilComparison, PublicField, PublicMemberWithoutDoc, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows, System.Math, System.IOUtils;

function IsValidUtf8(const Bytes: TBytes): Boolean;
// Pruft ob die komplette Byte-Sequenz wohlgeformtes UTF-8 ist
// (RFC 3629, ohne ueberlange Encodings strikt zu pruefen — fuer
// Encoding-Wahl ausreichend). ASCII-only ist trivial gueltig.
var
  i, Cont, Len : Integer;
  B            : Byte;
begin
  Len := Length(Bytes);
  i := 0;
  while i < Len do
  begin
    B := Bytes[i];
    if B < $80 then
      Cont := 0                          // ASCII
    else if (B and $E0) = $C0 then
      Cont := 1                          // 110xxxxx + 1
    else if (B and $F0) = $E0 then
      Cont := 2                          // 1110xxxx + 2
    else if (B and $F8) = $F0 then
      Cont := 3                          // 11110xxx + 3
    else
      Exit(False);                       // ungueltiges Lead-Byte
    Inc(i);
    while (Cont > 0) and (i < Len) do
    begin
      if (Bytes[i] and $C0) <> $80 then Exit(False);  // kein Continuation
      Inc(i); Dec(Cont);
    end;
    if Cont > 0 then Exit(False);        // unvollstaendige Sequenz am EOF
  end;
  Result := True;
end;

function LoadFileSmart(const FileName: string; SL: TStringList): Boolean;
// Encoding-Erkennung in drei Stufen:
//   1. BOM vorhanden? → Encoding aus BOM (UTF-8/UTF-16 LE/UTF-16 BE).
//   2. Kein BOM, aber alle Bytes wohlgeformt UTF-8? → UTF-8.
//   3. Sonst → TEncoding.Default (Windows-1252/Active-CP).
//
// Fixt Mojibake bei ANSI-Dateien mit Umlauten in den ersten Zeilen
// (Unit-Header, Copyright-Kommentare) - Delphi's LoadFromFile(F, UTF-8)
// ist lenient und ersetzt invalide Bytes still durch U+FFFD, sodass
// der Aufrufer den Fehler nicht sieht. Wir detecten explizit + waehlen
// die richtige Encoding bevor wir dekodieren.
var
  Bytes  : TBytes;
  Enc    : TEncoding;
  BomLen : Integer;
  Head   : TBytes;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    Bytes := TFile.ReadAllBytes(FileName);
  except
    Exit;
  end;

  // Stufe 1: BOM-Sniff auf den ersten max. 4 Bytes.
  SetLength(Head, Min(Length(Bytes), 4));
  if Length(Head) > 0 then
    Move(Bytes[0], Head[0], Length(Head));
  Enc := nil;
  BomLen := TEncoding.GetBufferEncoding(Head, Enc, nil);
  // GetBufferEncoding setzt Enc nur bei BOM-Treffer. Ohne BOM bleibt
  // Enc=nil (weil wir ADefaultEncoding=nil uebergeben haben).

  if Enc = nil then
  begin
    // Stufe 2/3: kein BOM. UTF-8-strikt oder ANSI.
    if IsValidUtf8(Bytes) then
      Enc := TEncoding.UTF8
    else
      Enc := TEncoding.Default;
    BomLen := 0;
  end;

  try
    // BOM-Bytes ueberspringen (wenn BOM erkannt war). GetString auf den
    // Rest. SL.Text setzt automatisch Lines auf.
    SL.Text := Enc.GetString(Bytes, BomLen, Length(Bytes) - BomLen);
    Result := True;
  except
    // ANSI/Default kann nie werfen (jeder Byte-Wert ist gueltig in CP1252).
    // UTF-8 ist nach IsValidUtf8 geprueft. Hier nur als Belt-and-Suspenders.
  end;
end;

// ---------------------------------------------------------------------------
// Encoding-Analyse fuer den Datei-Encoding-Detektor (Konzept_FileEncodingDetector).
// STRIKT (RFC 3629) - anders als das lenient IsValidUtf8 oben, das ueberlange
// Formen/Surrogate/>U+10FFFF durchlaesst.
// ---------------------------------------------------------------------------

function StrictUtf8SeqLen(const Bytes: TBytes; Idx, Len: Integer): Integer;
// Laenge (2..4) einer STRIKT wohlgeformten UTF-8-Sequenz ab Idx, sonst 0.
// Erwartet Bytes[Idx] >= $80 (Lead-Byte).
var
  b, b2      : Byte;
  need, j    : Integer;
  min2, max2 : Byte;
begin
  b := Bytes[Idx];
  if (b and $E0) = $C0 then
  begin
    if (b = $C0) or (b = $C1) then Exit(0);                 // ueberlang 2-Byte
    need := 1; min2 := $80; max2 := $BF;
  end
  else if (b and $F0) = $E0 then
  begin
    need := 2;
    if b = $E0 then begin min2 := $A0; max2 := $BF; end      // E0 80-9F ueberlang
    else if b = $ED then begin min2 := $80; max2 := $9F; end // ED A0-BF Surrogat
    else begin min2 := $80; max2 := $BF; end;
  end
  else if (b and $F8) = $F0 then
  begin
    if b >= $F5 then Exit(0);                                // F5-F7 (> U+10FFFF)
    need := 3;
    if b = $F0 then begin min2 := $90; max2 := $BF; end      // F0 80-8F ueberlang
    else if b = $F4 then begin min2 := $80; max2 := $8F; end // F4 90+ > U+10FFFF
    else begin min2 := $80; max2 := $BF; end;
  end
  else
    Exit(0);                                                 // Continuation / F8-FF

  if Idx + need >= Len then Exit(0);                         // abgeschnitten
  b2 := Bytes[Idx + 1];
  if (b2 < min2) or (b2 > max2) then Exit(0);
  for j := 2 to need do
    if (Bytes[Idx + j] and $C0) <> $80 then Exit(0);
  Result := need + 1;
end;

function IsBidiOverrideSeq(const Bytes: TBytes; Idx, SeqLen: Integer): Boolean;
// True wenn die (bereits validierte) Sequenz ab Idx ein bidirektionales
// Override/Isolate-Steuerzeichen ist (Trojan Source, CWE-1007):
//   U+061C (D8 9C), U+202A..202E (E2 80 AA..AE), U+2066..2069 (E2 81 A6..A9).
begin
  if SeqLen = 2 then
    Result := (Bytes[Idx] = $D8) and (Bytes[Idx + 1] = $9C)
  else if SeqLen = 3 then
    Result := (Bytes[Idx] = $E2) and
      ( ((Bytes[Idx + 1] = $80) and (Bytes[Idx + 2] >= $AA) and (Bytes[Idx + 2] <= $AE))
        or ((Bytes[Idx + 1] = $81) and (Bytes[Idx + 2] >= $A6) and (Bytes[Idx + 2] <= $A9)) )
  else
    Result := False;
end;

function IsZeroWidthSeq(const Bytes: TBytes; Idx, SeqLen: Integer): Boolean;
// True wenn die (bereits validierte) Sequenz ab Idx ein unsichtbares /
// Zero-Width-Zeichen ist (Unicode-Abuse, CWE-1007): U+200B/200C/200D
// (E2 80 8B/8C/8D), U+2060 Word-Joiner (E2 81 A0), sowie U+FEFF ZWNBSP
// (EF BB BF) - Letzteres nur MITTEN in der Datei (der Walk startet hinter der
// BOM, jedes EF BB BF hier ist also ein mid-file ZWNBSP, keine BOM). NBSP
// (U+00A0) ist BEWUSST NICHT dabei (legitim in UI-String-Literalen).
begin
  if SeqLen <> 3 then Exit(False);
  Result :=
    ( (Bytes[Idx] = $E2) and (Bytes[Idx + 1] = $80)
      and (Bytes[Idx + 2] >= $8B) and (Bytes[Idx + 2] <= $8D) )       // U+200B..200D
    or ( (Bytes[Idx] = $E2) and (Bytes[Idx + 1] = $81) and (Bytes[Idx + 2] = $A0) ) // U+2060
    or ( (Bytes[Idx] = $EF) and (Bytes[Idx + 1] = $BB) and (Bytes[Idx + 2] = $BF) ); // mid-file U+FEFF
end;

function ComputeFileEncodingInfo(const Bytes: TBytes): TFileEncodingInfo;
var
  Len, i, BomLen, Line, SeqLen : Integer;
  b : Byte;
begin
  Result := Default(TFileEncodingInfo);
  Result.StrictUtf8 := True;   // reines ASCII / leere Datei = gueltig
  Len := Length(Bytes);

  // BOM-Sniff NUR an Offset 0. UTF-32 VOR UTF-16 pruefen (FF FE 00 00 beginnt
  // mit FF FE).
  BomLen := 0;
  if (Len >= 4) and (Bytes[0] = $FF) and (Bytes[1] = $FE)
     and (Bytes[2] = $00) and (Bytes[3] = $00) then
  begin Result.BomKind := sbkUtf32LE; BomLen := 4; end
  else if (Len >= 4) and (Bytes[0] = $00) and (Bytes[1] = $00)
     and (Bytes[2] = $FE) and (Bytes[3] = $FF) then
  begin Result.BomKind := sbkUtf32BE; BomLen := 4; end
  else if (Len >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB)
     and (Bytes[2] = $BF) then
  begin Result.BomKind := sbkUtf8; BomLen := 3; end
  else if (Len >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
  begin Result.BomKind := sbkUtf16BE; BomLen := 2; end
  else if (Len >= 2) and (Bytes[0] = $FF) and (Bytes[1] = $FE) then
  begin Result.BomKind := sbkUtf16LE; BomLen := 2; end;

  Line := 1;
  i := BomLen;
  while i < Len do
  begin
    b := Bytes[i];
    if b = $0A then begin Inc(Line); Inc(i); Continue; end;
    // NUL / verbotene Steuerzeichen (ausser Tab #9, LF #10, FF #12, CR #13)
    if (b = 0) or ((b < $20) and (b <> 9) and (b <> 12) and (b <> 13)) then
    begin
      if not Result.HasNulCtrl then
      begin Result.HasNulCtrl := True; Result.FirstNulCtrlLine := Line; end;
      Inc(i); Continue;
    end;
    if b < $80 then begin Inc(i); Continue; end;   // ASCII
    // Nicht-ASCII (>= $80)
    if not Result.HasNonAscii then
    begin Result.HasNonAscii := True; Result.FirstNonAsciiLine := Line; end;
    SeqLen := StrictUtf8SeqLen(Bytes, i, Len);
    if SeqLen = 0 then
    begin
      Result.StrictUtf8 := False;
      if Result.FirstInvalidLine = 0 then Result.FirstInvalidLine := Line;
      Inc(i);   // Resync um 1 Byte
      Continue;
    end;
    Inc(Result.MultiByteRuns);
    if SeqLen >= 3 then Result.HasMultiByte3Up := True;
    if IsBidiOverrideSeq(Bytes, i, SeqLen) and (not Result.HasBidi) then
    begin Result.HasBidi := True; Result.FirstBidiLine := Line; end;
    if IsZeroWidthSeq(Bytes, i, SeqLen) and (not Result.HasZeroWidth) then
    begin Result.HasZeroWidth := True; Result.FirstZeroWidthLine := Line; end;
    // Continuation-Bytes koennen kein $0A sein -> keine Line-Zaehlung noetig.
    Inc(i, SeqLen);
  end;
end;

function AnalyzeFileEncoding(const FileName: string): TFileEncodingInfo;
var
  Bytes : TBytes;
begin
  Result := Default(TFileEncodingInfo);
  Result.StrictUtf8 := True;
  if not FileExists(FileName) then Exit;
  try
    Bytes := TFile.ReadAllBytes(FileName);
  except
    Exit;   // Readable bleibt False
  end;
  Result := ComputeFileEncodingInfo(Bytes);
  Result.Readable := True;
end;

{ TFileTextCacheEntry }

constructor TFileTextCacheEntry.Create(ALines: TStringList; AMTime: TDateTime;
  ASize: Int64; AStatGeneration: Integer);
begin
  inherited Create;
  Lines := ALines;
  MTime := AMTime;
  Size  := ASize;
  StatGeneration := AStatGeneration;
end;

destructor TFileTextCacheEntry.Destroy;
begin
  Lines.Free;
  inherited;
end;

{ TFileTextCache }

constructor TFileTextCache.Create;
begin
  inherited;
  FCache := TObjectDictionary<string, TFileTextCacheEntry>.Create([doOwnsValues]);
end;

destructor TFileTextCache.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TFileTextCache.Key(const FileName: string): string;
begin
  // Perf (2026-07-05): P2-filetextcache-stat - 1-Slot-Memo. Die Detektoren
  // fragen dieselbe Datei 60-80x direkt hintereinander an; ExpandFileName
  // macht pro Aufruf einen GetFullPathName-Roundtrip. Exakter String-Match
  // auf den ROHEN FileName -> gleiche Eingabe ergibt garantiert denselben
  // Key (reine Funktion), also verhaltensneutral.
  if (FLastName <> '') and (FileName = FLastName) then
    Exit(FLastKey);

  Result := LowerCase(ExpandFileName(FileName));

  // Nur absolute Pfade memoisieren: bei relativen Pfaden haengt
  // ExpandFileName vom aktuellen Verzeichnis ab, das sich zwischen zwei
  // Aufrufen aendern koennte ('C:\...'-Laufwerkspfad mit Slash oder
  // UNC '\\server\...'; laufwerksrelative 'C:foo' fallen bewusst raus).
  if ((Length(FileName) >= 3) and (FileName[2] = ':')
      and CharInSet(FileName[3], ['\', '/']))
     or ((Length(FileName) >= 2) and (FileName[1] = '\')
      and (FileName[2] = '\')) then
  begin
    FLastName := FileName;
    FLastKey  := Result;
  end;
end;

procedure SafeGetFileStat(const FileName: string;
  out MTime: TDateTime; out Size: Int64);
// Liest mtime + Size oder liefert 0/0 wenn die Datei nicht (mehr) existiert.
// Beides zusammen ist robuster gegen sub-Sekunden-Re-Writes mit
// veraenderter Groesse (FileAge-Granularity ist meist 1-2 Sekunden).
var
  Info : TWin32FileAttributeData;
begin
  MTime := 0;
  Size  := 0;
  try
    if not FileAge(FileName, MTime) then
      MTime := 0;
  except
    MTime := 0;
  end;
  try
    if GetFileAttributesEx(PChar(FileName), GetFileExInfoStandard, @Info) then
      Size := (Int64(Info.nFileSizeHigh) shl 32) or Int64(Info.nFileSizeLow);
  except
    Size := 0;
  end;
end;

function TFileTextCache.GetLines(const FileName: string;
  AForceStat: Boolean): TStringList;
var
  K         : string;
  SL        : TStringList;
  Entry     : TFileTextCacheEntry;
  CurrMTime : TDateTime;
  CurrSize  : Int64;
begin
  Result := nil;
  K := Key(FileName);

  if FCache.TryGetValue(K, Entry) then
  begin
    // Perf (2026-07-05): P2-filetextcache-stat - innerhalb EINER Generation
    // ist der Cache ein Snapshot: kein FileAge/GetFileAttributesEx pro Hit.
    // Cross-Scan-Staleness ist ueber Clear am Scan-Start abgedeckt
    // (Generation-Bump + Eintraege weg -> frischer Load).
    // AForceStat=True (Fingerprint/Baseline-Drift-Pfad): Snapshot-Shortcut
    // ueberspringen - dieser Konsument MUSS Datei-Ueberschreibungen auch
    // OHNE zwischenzeitliches Clear sehen (Kontrakt: contextHash rechnet
    // auf dem aktuellen Datei-Inhalt; Regressionstest
    // Baseline_MatchesViaContextHashAfterLineDrift).
    if (Entry.StatGeneration = FGeneration) and not AForceStat then
      Exit(Entry.Lines);

    SafeGetFileStat(FileName, CurrMTime, CurrSize);
    // Cache-Hit nur wenn mtime UND Size identisch sind. Bei sub-Sekunden-
    // Re-Writes der gleichen Datei aendert sich oft nur die Size (FileAge
    // hat ~1s Granularitaet), daher beide vergleichen.
    if (CurrMTime <> 0)
       and (CurrMTime = Entry.MTime)
       and (CurrSize = Entry.Size) then
    begin
      Entry.StatGeneration := FGeneration;  // Stat fuer diese Generation erledigt
      Exit(Entry.Lines);
    end;
    // Stale - aus Cache raus, danach neu laden.
    FCache.Remove(K);
  end;

  if not FileExists(FileName) then Exit;

  SL := TStringList.Create;
  try
    if not LoadFileSmart(FileName, SL) then
      FreeAndNil(SL);
  except
    FreeAndNil(SL);
  end;

  if SL = nil then Exit;
  SafeGetFileStat(FileName, CurrMTime, CurrSize);
  // Perf (2026-07-05): P2-filetextcache-stat - der frische Eintrag traegt die
  // aktuelle Generation: der Stat ist hiermit fuer diese Generation erledigt.
  FCache.Add(K, TFileTextCacheEntry.Create(SL, CurrMTime, CurrSize, FGeneration));
  Result := SL;
end;

procedure TFileTextCache.Clear;
begin
  // Perf (2026-07-05): P2-filetextcache-stat - Generation-Bump: alle danach
  // (theoretisch) noch gesehenen Alt-Eintraege muessten neu ge-stat-et
  // werden. Praktisch zerstoert FCache.Clear ohnehin alle Eintraege; der
  // Bump haelt die Invariante "Eintrag mit fremder Generation => Stat"
  // auch fuer kuenftige partielle Invalidierungen (Remove o.ae.) korrekt.
  Inc(FGeneration);
  FCache.Clear;
end;

// --- Wrapper-Funktionen ---

function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean; ACache: TFileTextCache;
  AForceStat: Boolean): TStringList;
var
  Cache: TFileTextCache;
begin
  OwnedByCache := False;
  // Per-Scan-Cache (Context) bevorzugen; nil -> Prozess-Global.
  Cache := ACache;
  if Cache = nil then Cache := gFileTextCache;
  if Assigned(Cache) then
  begin
    Result := Cache.GetLines(FileName, AForceStat);
    if Result <> nil then
    begin
      OwnedByCache := True;
      Exit;
    end;
  end;

  // Fallback: lokaler Load
  if not FileExists(FileName) then Exit(nil);
  Result := TStringList.Create;
  try
    if not LoadFileSmart(FileName, Result) then
      FreeAndNil(Result);
  except
    FreeAndNil(Result);
  end;
end;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);
begin
  if (Lines <> nil) and not OwnedByCache then
    Lines.Free;
end;

function TryLoadLinesWithFallback(const FileName: string;
  Lines: TStringList): Boolean;
// Encoding-Detection-Pipeline: Default -> UTF8 -> Unicode. Wir nutzen
// nicht LoadFileSmart (BOM+ANSI/UTF-8-Sniff) weil dieser Pfad explizit
// fuer Caller ist, die das alte TStringList.LoadFromFile-Verhalten
// brauchen (z.B. Suppression-Marker-Lookup, der ueber Win-1252-Files
// genauso laufen muss wie ueber UTF8 ohne BOM).
begin
  Result := False;
  if (Lines = nil) or not FileExists(FileName) then Exit;
  try
    Lines.LoadFromFile(FileName);
    Result := True;
  except
    try
      Lines.LoadFromFile(FileName, TEncoding.UTF8);
      Result := True;
    except
      try
        Lines.LoadFromFile(FileName, TEncoding.Unicode);
        Result := True;
      except
        // Datei unleserlich - Caller entscheidet was zu tun ist.
      end;
    end;
  end;
end;

initialization

finalization
  if Assigned(gFileTextCache) then
    FreeAndNil(gFileTextCache);

end.
