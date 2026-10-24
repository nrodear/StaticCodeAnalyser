unit uFileTextCache;

// Datei-Text-Cache fuer File-Scan-Detektoren (uTodoComment, uWithStatement,
// uReversedForRange, uLengthUnderflow, uTautologicalExpr, uDuplicateBlock,
// uCustomRuleDetector).
//
// Hintergrund (tools/perf_analyse.md Hot-Spot B):
// Diese 7 Detektoren rufen jeweils Lines.LoadFromFile auf - pro .pas-Datei
// 7+ separate Disk-IO-Operationen + Encoding-Erkennung + TStringList-
// Allokationen. Mit diesem Cache wird pro Datei einmal eingelesen und
// alle Detektoren bedienen sich aus derselben TStringList.
//
// Ownership-Modell:
//   AcquireLines(FileName, out OwnedByCache) liefert eine TStringList.
//     * Wenn OwnedByCache=True (Cache-Pfad): nicht freigeben - der Cache
//       managed das Leben. Die Zeilen sind GELIEHEN: der Aufrufer gibt
//       sie mit ReleaseLines zurueck, und zwar genau einmal.
//     * Wenn OwnedByCache=False (Fallback): Caller MUSS Lines.Free
//       aufrufen wenn fertig.
//
//   Pragmatische Convenience: ReleaseLines(Lines, OwnedByCache) macht
//   genau das richtige - so kann der Caller einheitlich
//     Lines := AcquireLines(FileName, Cached); try ... finally
//       ReleaseLines(Lines, Cached); end;
//
// Nutzerzaehler je Eintrag (Review Bereich C Engine-Kern, Blocker 1,
// 2026-10-14): jeder Eintrag zaehlt, wie viele Leser seine Zeilen gerade
// halten (GetLines/AcquireLines bis ReleaseLines). Clear, RemoveFile und
// das Entfernen eines veralteten Eintrags haengen einen GEHALTENEN
// Eintrag nur aus dem Woerterbuch aus; frei wird er erst, wenn der
// letzte Leser ihn zurueckgibt. Anlass: der IDE-Massenscan leert den
// Cache je Datei, waehrend "Write baseline" auf einem anderen Thread
// ueber ContextHashFor (uFindingFingerprint) gerade Zeilen desselben
// Caches liest - vorher ein Use-after-free (AV oder falscher
// contextHash). Ein Leser, der ReleaseLines vergisst, kostet seit dem
// Zaehler einen Eintrag bis zum Prozessende, nie einen Absturz.
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
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.SyncObjs;   // Perf Stufe 2 (2026-07-25): FLock fuer Parallel-Worker

type
  // Byte-Level-Encoding-Fakten einer Quelldatei (fuer den Encoding-Detektor,
  // Konzept_FileEncodingDetector). Auf der POST-BOM-Slice berechnet - die
  // BOM-Bytes selbst zaehlen NICHT als "Nicht-ASCII".
  // (Perf P2, 2026-07-19: vor TFileTextCacheEntry gezogen - der Entry
  // traegt das Verdikt jetzt als Load-Piggyback.)
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
  PFileEncodingInfo = ^TFileEncodingInfo;

  TFileTextCache = class;

  TFileTextCacheEntry = class
  private
    // Nutzerzaehler (s. Unit-Kopf). Alle drei Felder werden NUR unter
    // FOwner.FLock gelesen und geschrieben - auch von ReleaseLines, das
    // ueber den Rueckverweis der Zeilen (TCacheOwnedLines) hierher findet.
    FOwner    : TFileTextCache;
    FUsers    : Integer;    // Leser, die Lines gerade halten
    FDetached : Boolean;    // aus FCache ausgehaengt; frei, sobald FUsers = 0
  public
    Lines : TStringList;
    MTime : TDateTime;
    Size  : Int64;
    // Perf (2026-07-05): P2-filetextcache-stat - Cache-Generation des letzten
    // Disk-Stat-Checks dieses Eintrags. Solange die Generation des Caches
    // unveraendert ist, skippt GetLines den Stat (siehe dort).
    StatGeneration : Integer;
    // Perf P2 (Konzept_Performance25, 2026-07-19): Encoding-Verdikt aus den
    // Rohbytes des Load-Reads (ComputeFileEncodingInfo lief auf den Bytes,
    // BEVOR sie dekodiert/verworfen wurden) - erspart dem SourceEncoding-
    // Detektor den kompletten Zweit-Read der Datei. Beim Cache-Load immer
    // befuellt (Readable=True); der AcquireLines-Fallback ohne Cache
    // berechnet es nicht.
    EncInfo : TFileEncodingInfo;
    constructor Create(ALines: TStringList; AMTime: TDateTime; ASize: Int64;
      AStatGeneration: Integer; const AEncInfo: TFileEncodingInfo);
    destructor Destroy; override;
  end;

  // Die Zeilen eines Cache-Eintrags: eine TStringList mit Rueckverweis auf
  // ihren Eintrag. So kann ReleaseLines den Nutzerzaehler zurueckgeben,
  // ohne dass die ~100 Aufrufer ein Cache-Handle mitfuehren muessten -
  // ihr Muster (Acquire, try, finally ReleaseLines) bleibt unveraendert.
  TCacheOwnedLines = class(TStringList)
  private
    FEntry : TFileTextCacheEntry;
  end;

  TFileTextCache = class
  private
    // Kein doOwnsValues: das Leben eines Eintrags entscheidet DropEntry
    // (sofort frei oder bis zum letzten ReleaseLines ausgehaengt).
    FCache : TDictionary<string, TFileTextCacheEntry>;
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
    // Perf Stufe 2 (2026-07-25): serialisiert FCache/Key-Memo/FGeneration -
    // im Parallel-Modus greifen mehrere Worker-Threads gleichzeitig auf den
    // (weiterhin prozessweiten) Cache zu. Der Datei-Load laeuft ausserhalb
    // des Locks (paralleles I/O); seriell ist der Lock unkontent und damit
    // verhaltens- und praktisch kostenneutral. Seit 2026-10-14 schuetzt er
    // auch die Nutzerzaehler der Eintraege.
    FLock     : TCriticalSection;
    function Key(const FileName: string): string;
    // Eintrag mit Nutzerzaehler + 1 (nil bei Lesefehler) - der Kern von
    // GetLines und TryGetEncodingInfo. Jeder Treffer braucht ein ReleaseEntry.
    function AcquireEntry(const FileName: string;
      AForceStat: Boolean): TFileTextCacheEntry;
    procedure ReleaseEntry(Entry: TFileTextCacheEntry);
    // Unter FLock: Eintrag sofort freigeben oder - wenn ihn noch jemand
    // haelt - aushaengen, damit das letzte ReleaseEntry ihn freigibt.
    procedure DropEntry(Entry: TFileTextCacheEntry);
  public
    constructor Create;
    destructor Destroy; override;

    // Liefert TStringList fuer FileName. Cache besitzt die Liste -
    // NICHT freigeben, sondern mit ReleaseLines(Lines, True) zurueckgeben
    // (genau einmal; der Eintrag lebt bis dahin, auch ueber Clear/
    // RemoveFile hinweg). Nil bei Read-Fehler.
    // Staleness-Modell (Perf 2026-07-05, P2-filetextcache-stat):
    //   * Innerhalb einer Generation (zwischen zwei Clear-Aufrufen) ist der
    //     Cache ein Snapshot - KEIN Disk-Stat pro Hit. Ein Scan ist per
    //     Definition ein Snapshot des Datei-Standes.
    //   * Cross-Scan bleibt das Verhalten identisch: der Scan-Start
    //     (uStaticAnalyzer2.ParseLeaks) ruft Clear -> Generation-Bump +
    //     alle Eintraege werden ausgehaengt -> naechster Zugriff laedt frisch.
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
    //     Ein Leser, der die ALTEN Zeilen noch haelt, behaelt sie - der
    //     veraltete Eintrag wird nur ausgehaengt.
    function GetLines(const FileName: string;
      AForceStat: Boolean = False): TStringList;

    // Perf P2 (Konzept_Performance25, 2026-07-19): Encoding-Verdikt des
    // Cache-Eintrags. Laedt die Datei bei Bedarf (GetLines-Semantik inkl.
    // Snapshot-/Stat-Modell); False nur bei Read-Fehler. Haelt keinen
    // Eintrag: das Verdikt wird kopiert.
    function TryGetEncodingInfo(const FileName: string;
      out Info: TFileEncodingInfo): Boolean;

    // Haengt ALLE Eintraege aus und bumpt die Generation. Eintraege, die
    // gerade ein Leser haelt, werden erst mit dessen ReleaseLines frei;
    // EntryCount ist danach trotzdem 0.
    procedure Clear;
    /// <summary>Zahl der eingehaengten Eintraege, FLock-geschuetzt. Nur
    /// Diagnose/Test (TransientCacheCount) - Ablauflogik darf darauf
    /// nichts bauen, der Wert ist im Parallel-Modus sofort stale.
    /// Ausgehaengte, noch gehaltene Eintraege zaehlen nicht mit.</summary>
    function EntryCount: Integer;

    // Perf Stufe 2 (2026-07-25): entfernt NUR den Eintrag dieser Datei -
    // das per-File-Pendant zum seriellen Clear fuer den Parallel-Modus.
    // Ein globales Clear nahm dort frueher den Eintraegen ANDERER Worker
    // den Boden weg; seit dem Nutzerzaehler bleibt RemoveFile die
    // sparsamere Wahl (die uebrigen Eintraege bleiben warm), noetig fuer
    // die Speichersicherheit ist es nicht mehr. Kein Generation-Bump: die
    // uebrigen Eintraege bleiben Snapshot-gueltig.
    procedure RemoveFile(const FileName: string);
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

// Gibt die Zeilen aus AcquireLines zurueck: OwnedByCache=False -> Free;
// OwnedByCache=True -> Nutzerzaehler des Cache-Eintrags um eins senken
// (der Eintrag wird frei, wenn er ausgehaengt ist und niemand ihn mehr
// haelt). nil ist erlaubt. Vertrag: GENAU EINMAL je AcquireLines
// zurueckgeben - der Zaehler faellt nie unter 0, mehr Schutz gibt es
// nicht: ein doppeltes ReleaseLines nimmt bei einem zweiten Halter
// DESSEN Halt (Details s. ReleaseEntry).
procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);

// Laedt eine Datei mit der Encoding-Erkennung des Caches (BOM, dann
// wohlgeformtes UTF-8, sonst Default-Codepage) in SL - OHNE den Cache zu
// beruehren. Oeffentlich seit dem Quellstellen-Dienst (uSourcePlaces,
// 2026-10-03): der liest je Datei selbst, damit er ohne Scan-Kontext und
// Engine-Lock aus einem residenten Host heraus laufen kann, und sieht
// dabei dieselben Zeilen wie die Datei-Detektoren des Scans
// (AcquireLines). NICHT wie dessen AST-Pfad: TParser2.ParseFile liest
// eine UTF-8-Datei ohne BOM als ANSI (LoadFromFile ohne Encoding) - ein
// Ziel mit Umlaut in einer Fundmeldung kann deshalb anders aussehen als
// im Dienst (reDelphix: TRdxRecipes.TargetsComparable). Das anzugleichen
// bewegt Funde und gehoert in eine eigene, per A/B gemessene Charge
// (Review nach Bereichen 2026-10-10, Nit 7). False, wenn die Datei nicht
// lesbar ist.
function LoadFileSmart(const FileName: string; SL: TStringList;
  AEncInfo: PFileEncodingInfo = nil): Boolean;

/// <summary>Leert den prozessweiten Text-Cache (G2-5-Hook, Engine-Seite).
/// Der Aufrufer ist der CONSUMER, nicht die Engine - nur er weiss, wann
/// die letzte Nacharbeit (Suppression-Marker, ContextHash fuer Baseline/
/// SARIF) durch ist. Zu frueh gerufen kostet es nur Warmstart (der Cache
/// fuellt sich lazy nach), nie Korrektheit: Zeilen, die ein Leser gerade
/// haelt, bleiben bis zu seinem ReleaseLines gueltig (Nutzerzaehler, s.
/// Unit-Kopf) - vor 2026-10-14 galt dieser Satz nur fuer die Waerme, ein
/// Leser auf einem anderen Thread las danach freigegebenen Speicher.</summary>
/// <remarks>Anlass ist die Messreihe vom 2026-08-25: nach EINEM
/// default-Scan des Referenzkorpus im 32-Bit-BDS blieben ~1,3 GB stehen,
/// davon ~0,5 GB dieser Cache - designgemaess bis zum naechsten Scan.
/// Erfolgsmetrik ist NICHT das Task-Manager-Residuum (FastMM poolt
/// freigegebene Bloecke), sondern der PEAK des naechsten grossen Scans:
/// freigegebener Adressraum wird wiederverwendet statt neu zu wachsen.
/// Details und Zahlen: Todo_Review_G2_EngineInfra_2026-08-25 (lokal).</remarks>
procedure ReleaseTransientCaches;

/// <summary>Zahl der eingehaengten Cache-Eintraege (ausgehaengte, die
/// ein Leser noch haelt, zaehlen nicht) - fuer die Messbarkeit
/// des Hooks (Test + Diagnose), nicht fuer Ablauflogik.</summary>
function TransientCacheCount: Integer;

// Standalone-Loader mit Encoding-Detection (Default -> UTF8 -> Unicode).
// Caller besitzt Lines. False bei Read-/Decode-Fehler.
// Wird von Code-Pfaden genutzt, die nicht ueber den Cache laufen
// (Pre-Index-Scans, Single-File-Tools). Vorher 3-fach try-fallback
// inline in uSuppression - jetzt single source of truth hier.
function TryLoadLinesWithFallback(const FileName: string;
  Lines: TStringList): Boolean;

// Byte-Level-Encoding-Analyse einer Datei. Eigener ReadAllBytes: der Text-
// Cache haelt nur dekodierte Strings OHNE BOM, die Encoding-Wahrheit steckt
// nur in den Rohbytes. Readable=False wenn nicht lesbar (dann greift der
// FileReadError-Pfad).
function AnalyzeFileEncoding(const FileName: string): TFileEncodingInfo;

// Perf P2: Encoding-Analyse mit Cache-Piggyback (das Verdikt entstand beim
// Load aus denselben Rohbytes, die AnalyzeFileEncoding erneut lesen wuerde).
// ACache=nil -> gFileTextCache; ohne verfuegbaren Cache oder bei Read-
// Fehler frischer AnalyzeFileEncoding-Read wie bisher.
function AcquireEncodingInfo(const FileName: string;
  ACache: TFileTextCache = nil): TFileEncodingInfo;
// Reiner Analyse-Kern (fuer Tests direkt mit TBytes aufrufbar).
function ComputeFileEncodingInfo(const Bytes: TBytes): TFileEncodingInfo;

implementation

// noinspection-file BooleanParam, CanBeClassMethod, CanBeStrictPrivate, CanBeUnitPrivate, ClassPerFile, CyclomaticComplexity, DeepNesting, EmptyExcept, GroupedDeclaration, NestedTry, NilComparison, PublicField, PublicMemberWithoutDoc, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows, System.Math, System.IOUtils;

// ---------------------------------------------------------------------------
// Encoding-Analyse fuer den Datei-Encoding-Detektor (Konzept_FileEncodingDetector).
// STRIKT (RFC 3629). Dieselbe Pruefung entscheidet seit 2026-10-14 auch die
// Encoding-WAHL in LoadFileSmart (s. IsValidUtf8).
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

function IsValidUtf8(const Bytes: TBytes): Boolean;
// Prueft, ob die komplette Byte-Sequenz STRIKT wohlgeformtes UTF-8 ist
// (RFC 3629: keine ueberlangen Formen, keine Surrogate, nichts ueber
// U+10FFFF). ASCII-only ist trivial gueltig.
//
// Bis 2026-10-14 war die Pruefung lax (Lead-/Continuation-Muster ohne
// Wertebereiche). TEncoding.UTF8 ist aber strikt und WIRFT bei einer
// Sequenz wie C0 80 - die Datei galt dann als unlesbar und war fuer alle
// Datei-Detektoren still unsichtbar (Review Bereich C, Major 15). Jetzt
// entscheidet dieselbe Pruefung wie im Encoding-Detektor: was sie
// ablehnt, liest LoadFileSmart als Default-Codepage.
var
  i, Len, SeqLen : Integer;
begin
  Len := Length(Bytes);
  i := 0;
  while i < Len do
  begin
    if Bytes[i] < $80 then
    begin
      Inc(i);
      Continue;
    end;
    SeqLen := StrictUtf8SeqLen(Bytes, i, Len);
    if SeqLen = 0 then Exit(False);
    Inc(i, SeqLen);
  end;
  Result := True;
end;

function LoadFileSmart(const FileName: string; SL: TStringList;
  AEncInfo: PFileEncodingInfo): Boolean;
// Encoding-Erkennung in drei Stufen:
//   1. BOM vorhanden? -> Encoding aus BOM (UTF-8/UTF-16 LE/UTF-16 BE).
//   2. Kein BOM, aber alle Bytes wohlgeformt UTF-8? -> UTF-8.
//   3. Sonst -> TEncoding.Default (Windows-1252/Active-CP).
//
// AEncInfo <> nil (Perf P2): zusaetzlich das Byte-Level-Encoding-Verdikt
// aus den ohnehin gelesenen Rohbytes berechnen (identische Funktion wie
// AnalyzeFileEncoding, identische Bytes -> identisches Verdikt) - der
// Cache-Entry traegt es dann fuer den SourceEncoding-Detektor.
//
// Fixt Mojibake bei ANSI-Dateien mit Umlauten in den ersten Zeilen
// (Unit-Header, Copyright-Kommentare) - Delphi's LoadFromFile(F, UTF-8)
// ist lenient und ersetzt invalide Bytes still durch U+FFFD, sodass
// der Aufrufer den Fehler nicht sieht. Wir detecten explizit + waehlen
// die richtige Encoding bevor wir dekodieren.
//
// Nie blind (Review Bereich C, Major 15): wirft die gewaehlte Dekodierung
// trotzdem (UTF-8-BOM, dahinter ein ungueltiges Byte - TEncoding.UTF8
// ist strikt), werden die Bytes hinter der BOM als Default-Codepage
// gelesen. Eine Datei mit einem kaputten Byte verliert so ein Zeichen,
// nicht alle Funde.
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
    try
      SL.Text := Enc.GetString(Bytes, BomLen, Length(Bytes) - BomLen);
    except
      on EEncodingError do
        // Default kann nie werfen (jeder Byte-Wert ist in der Codepage
        // gueltig); hier landet nur eine BOM-Datei mit kaputtem Inhalt.
        SL.Text := TEncoding.Default.GetString(Bytes, BomLen,
          Length(Bytes) - BomLen);
    end;
    if AEncInfo <> nil then
    begin
      AEncInfo^ := ComputeFileEncodingInfo(Bytes);
      AEncInfo^.Readable := True;
    end;
    Result := True;
  except
    // Belt-and-Suspenders fuer alles ausser der Dekodierung (Speicher).
  end;
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
  ASize: Int64; AStatGeneration: Integer; const AEncInfo: TFileEncodingInfo);
// FOwner und der Rueckverweis der Zeilen werden vom Cache gesetzt
// (AcquireEntry) - der Eintrag kennt seinen Cache erst, wenn er drin ist.
begin
  inherited Create;
  Lines := ALines;
  MTime := AMTime;
  Size  := ASize;
  StatGeneration := AStatGeneration;
  EncInfo := AEncInfo;
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
  FCache := TDictionary<string, TFileTextCacheEntry>.Create;
  FLock  := TCriticalSection.Create;   // Perf Stufe 2 (2026-07-25)
end;

destructor TFileTextCache.Destroy;
var
  Entry : TFileTextCacheEntry;
begin
  // Prozess- bzw. Cache-Ende: alle eingehaengten Eintraege freigeben, auch
  // gehaltene - ein Leser, der den CACHE ueberlebt, war schon immer ein
  // Fehler des Aufrufers (gFileTextCache stirbt erst in finalization).
  if Assigned(FCache) then
    for Entry in FCache.Values do
      Entry.Free;
  FCache.Free;
  FLock.Free;
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

function LoadCacheLines(const FileName: string;
  out AEncInfo: TFileEncodingInfo): TCacheOwnedLines;
// Zeilen fuer einen neuen Eintrag; nil bei Lesefehler (LoadFileSmart
// faengt jeden selbst). Eigene Funktion: der Aufrufer uebernimmt das
// Ergebnis in den Eintrag, eine try/finally-Klammer passt dort nicht.
begin
  Result := TCacheOwnedLines.Create;
  if not LoadFileSmart(FileName, Result, @AEncInfo) then
    FreeAndNil(Result);
end;

procedure TFileTextCache.DropEntry(Entry: TFileTextCacheEntry);
// Unter FLock. Haelt noch jemand die Zeilen, bleibt der Eintrag am Leben
// und ReleaseEntry des letzten Lesers gibt ihn frei; sonst sofort weg.
// Nie zweimal fuer denselben Eintrag: der Aufrufer nimmt ihn zugleich
// aus FCache.
begin
  if Entry.FUsers > 0 then
    Entry.FDetached := True
  else
    Entry.Free;
end;

procedure TFileTextCache.ReleaseEntry(Entry: TFileTextCacheEntry);
begin
  if Entry = nil then Exit;
  FLock.Enter;
  try
    // Nie unter 0 - mehr Schutz gibt es hier nicht: ein doppeltes
    // ReleaseLines desselben Aufrufers ist nur dann folgenlos, wenn kein
    // zweiter Halter da ist. Mit zweitem Halter nimmt es DESSEN Halt; ist
    // der Eintrag dann ausgehaengt (Clear/RemoveFile), wird er unter dem
    // zweiten Leser frei. Der Vertrag bleibt "genau einmal zurueckgeben"
    // (uTestFileTextCache.DoubleRelease_WithSecondHolder_AttachedEntry-
    // Survives; Gegen-Review Welle 1, Minor 9 - der Kommentar versprach
    // vorher einen Schutz, den der Code nicht hat).
    if Entry.FUsers > 0 then
      Dec(Entry.FUsers);
    if (Entry.FUsers = 0) and Entry.FDetached then
      Entry.Free;
  finally
    FLock.Leave;
  end;
end;

function TFileTextCache.AcquireEntry(const FileName: string;
  AForceStat: Boolean): TFileTextCacheEntry;
var
  K         : string;
  SL        : TCacheOwnedLines;
  Entry     : TFileTextCacheEntry;
  CurrMTime : TDateTime;
  CurrSize  : Int64;
  EncInfo   : TFileEncodingInfo;
begin
  Result := nil;
  // Perf Stufe 2 (2026-07-25): Lookup/Stale-Check unter FLock - der Cache
  // wird im Parallel-Modus von mehreren Worker-Threads gleichzeitig benutzt
  // (Key mutiert zudem das 1-Slot-Memo). Der Datei-Load selbst laeuft
  // BEWUSST ausserhalb des Locks (paralleles I/O); da jeder Worker nur
  // seine eigene Datei anfragt, laedt praktisch nie jemand doppelt.
  FLock.Enter;
  try
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
      begin
        Inc(Entry.FUsers);
        Exit(Entry);
      end;

      SafeGetFileStat(FileName, CurrMTime, CurrSize);
      // Cache-Hit nur wenn mtime UND Size identisch sind. Bei sub-Sekunden-
      // Re-Writes der gleichen Datei aendert sich oft nur die Size (FileAge
      // hat ~1s Granularitaet), daher beide vergleichen.
      if (CurrMTime <> 0)
         and (CurrMTime = Entry.MTime)
         and (CurrSize = Entry.Size) then
      begin
        Entry.StatGeneration := FGeneration;  // Stat fuer diese Generation erledigt
        Inc(Entry.FUsers);
        Exit(Entry);
      end;
      // Stale - aushaengen (ein Leser der alten Zeilen behaelt sie),
      // danach neu laden.
      FCache.Remove(K);
      DropEntry(Entry);
    end;
  finally
    FLock.Leave;
  end;

  if not FileExists(FileName) then Exit;

  // Perf P2: Encoding-Verdikt aus den Load-Rohbytes mitnehmen. Bewusster
  // Trade-off: Post-Scan-Reloads (Suppression/ContextHash fuellen den
  // Cache nach dem per-File-Clear lazy nach) zahlen den Walk mit, obwohl
  // dort niemand das Verdikt liest - er ist aber nur EIN zusaetzlicher
  // RAM-Pass neben ReadAllBytes+IsValidUtf8+Decode, waehrend der Detektor-
  // Pfad einen KOMPLETTEN Zweit-Read pro Quelldatei spart. Falls die
  // Timings-Messung das je kippt: Phase-Flag am Cache (Walk nur waehrend
  // der Detektor-Phase) statt hier zu raten.
  SL := LoadCacheLines(FileName, EncInfo);
  if SL = nil then Exit;
  SafeGetFileStat(FileName, CurrMTime, CurrSize);
  FLock.Enter;
  try
    // Perf Stufe 2 (2026-07-25): Defensiv-Zweig - sollte ein anderer Thread
    // denselben Key inzwischen geladen haben (kommt im Per-File-Modell nicht
    // vor), gewinnt dessen Eintrag und der eigene Load wird verworfen.
    if FCache.TryGetValue(K, Entry) then
    begin
      SL.Free;
      Inc(Entry.FUsers);
      Exit(Entry);
    end;
    // Perf (2026-07-05): P2-filetextcache-stat - der frische Eintrag traegt die
    // aktuelle Generation: der Stat ist hiermit fuer diese Generation erledigt.
    Entry := TFileTextCacheEntry.Create(SL, CurrMTime, CurrSize,
      FGeneration, EncInfo);
    Entry.FOwner := Self;
    SL.FEntry := Entry;
    Entry.FUsers := 1;
    FCache.Add(K, Entry);
    Result := Entry;
  finally
    FLock.Leave;
  end;
end;

function TFileTextCache.GetLines(const FileName: string;
  AForceStat: Boolean): TStringList;
var
  Entry : TFileTextCacheEntry;
begin
  Entry := AcquireEntry(FileName, AForceStat);
  if Entry = nil then
    Result := nil
  else
    Result := Entry.Lines;
end;

function TFileTextCache.TryGetEncodingInfo(const FileName: string;
  out Info: TFileEncodingInfo): Boolean;
// Perf P2: AcquireEntry validiert/laedt den Eintrag (zentrale Snapshot-/
// Stat-Logik, kein zweiter Staleness-Pfad hier). Das Verdikt ist nach dem
// Laden unveraenderlich - Kopie ohne Lock, dann den Eintrag zurueckgeben.
var
  Entry : TFileTextCacheEntry;
begin
  Result := False;
  Entry := AcquireEntry(FileName, False);
  if Entry = nil then Exit;
  Info := Entry.EncInfo;
  ReleaseEntry(Entry);
  Result := True;
end;

function TFileTextCache.EntryCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCache.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TFileTextCache.Clear;
var
  Entry : TFileTextCacheEntry;
begin
  // Perf (2026-07-05): P2-filetextcache-stat - Generation-Bump: alle danach
  // (theoretisch) noch gesehenen Alt-Eintraege muessten neu ge-stat-et
  // werden. Praktisch haengt Clear ohnehin alle Eintraege aus; der Bump
  // haelt die Invariante "Eintrag mit fremder Generation => Stat" auch
  // fuer kuenftige partielle Invalidierungen (Remove o.ae.) korrekt.
  FLock.Enter;   // Perf Stufe 2 (2026-07-25)
  try
    Inc(FGeneration);
    for Entry in FCache.Values do
      DropEntry(Entry);
    FCache.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TFileTextCache.RemoveFile(const FileName: string);
// Perf Stufe 2 (2026-07-25): per-File-Entlastung im Parallel-Modus -
// Doku am Interface-Prototyp.
var
  K     : string;
  Entry : TFileTextCacheEntry;
begin
  FLock.Enter;
  try
    K := Key(FileName);
    if FCache.TryGetValue(K, Entry) then
    begin
      FCache.Remove(K);
      DropEntry(Entry);
    end;
  finally
    FLock.Leave;
  end;
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

procedure ReleaseTransientCaches;
begin
  // Clear ist FLock-geschuetzt und bumpt die Generation - exakt derselbe
  // Weg wie am Scan-Start. Ein parallel laufender Scan verliert dadurch
  // schlimmstenfalls Cache-Waerme, nie Daten (die Eintraege werden lazy
  // nachgeladen, gehaltene Zeilen bleiben bis zum ReleaseLines gueltig).
  if Assigned(gFileTextCache) then
    gFileTextCache.Clear;
end;

function TransientCacheCount: Integer;
begin
  Result := 0;
  if Assigned(gFileTextCache) then
    Result := gFileTextCache.EntryCount;
end;

function AcquireEncodingInfo(const FileName: string;
  ACache: TFileTextCache): TFileEncodingInfo;
// Perf P2: siehe Interface-Kommentar. Identisches Verdikt wie
// AnalyzeFileEncoding (gleiche ComputeFileEncodingInfo-Funktion, gleicher
// Datei-Snapshot); der Cache-Pfad spart nur den zweiten Disk-Read.
var
  Cache : TFileTextCache;
begin
  Cache := ACache;
  if Cache = nil then Cache := gFileTextCache;
  if (Cache <> nil) and Cache.TryGetEncodingInfo(FileName, Result) then Exit;
  Result := AnalyzeFileEncoding(FileName);
end;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);
var
  Entry : TFileTextCacheEntry;
begin
  if Lines = nil then Exit;
  if not OwnedByCache then
  begin
    Lines.Free;
    Exit;
  end;
  // Geliehene Zeilen: ueber den Rueckverweis den Zaehler des Eintrags
  // senken. Eine fremde TStringList mit OwnedByCache=True (Aufrufer-
  // Fehler) wird still ignoriert - wie vor dem Zaehler.
  if not (Lines is TCacheOwnedLines) then Exit;
  Entry := TCacheOwnedLines(Lines).FEntry;
  if (Entry <> nil) and (Entry.FOwner <> nil) then
    Entry.FOwner.ReleaseEntry(Entry);
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
