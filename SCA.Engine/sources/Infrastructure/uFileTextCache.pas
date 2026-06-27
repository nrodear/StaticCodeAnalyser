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
// Lifecycle:
//   gFileTextCache wird beim Start jedes Files in der Main-Loop angelegt
//   und am Ende freigegeben. Pro File-Scope = pro Cache-Instanz.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TFileTextCacheEntry = class
  public
    Lines : TStringList;
    MTime : TDateTime;
    Size  : Int64;
    constructor Create(ALines: TStringList; AMTime: TDateTime; ASize: Int64);
    destructor Destroy; override;
  end;

  TFileTextCache = class
  private
    FCache : TObjectDictionary<string, TFileTextCacheEntry>;
    function Key(const FileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Liefert TStringList fuer FileName. Cache besitzt die Liste -
    // NICHT freigeben. Nil bei Read-Fehler.
    // mtime-aware: hat sich die Datei seit dem Cache-Eintrag geaendert,
    // wird sie neu geladen. Schuetzt vor stale-cache bei Tests die
    // dieselbe Datei ueberschreiben + bei Edit-Loops im IDE-Plugin.
    function GetLines(const FileName: string): TStringList;

    procedure Clear;
  end;

var
  // Optional. Wenn nil (Tests, Single-File-Pfad), faellt AcquireLines auf
  // einen frischen LoadFromFile-Roundtrip zurueck.
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
function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean; ACache: TFileTextCache = nil): TStringList;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);

// Standalone-Loader mit Encoding-Detection (Default -> UTF8 -> Unicode).
// Caller besitzt Lines. False bei Read-/Decode-Fehler.
// Wird von Code-Pfaden genutzt, die nicht ueber den Cache laufen
// (Pre-Index-Scans, Single-File-Tools). Vorher 3-fach try-fallback
// inline in uSuppression - jetzt single source of truth hier.
function TryLoadLinesWithFallback(const FileName: string;
  Lines: TStringList): Boolean;

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

{ TFileTextCacheEntry }

constructor TFileTextCacheEntry.Create(ALines: TStringList; AMTime: TDateTime;
  ASize: Int64);
begin
  inherited Create;
  Lines := ALines;
  MTime := AMTime;
  Size  := ASize;
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
  Result := LowerCase(ExpandFileName(FileName));
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

function TFileTextCache.GetLines(const FileName: string): TStringList;
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
    SafeGetFileStat(FileName, CurrMTime, CurrSize);
    // Cache-Hit nur wenn mtime UND Size identisch sind. Bei sub-Sekunden-
    // Re-Writes der gleichen Datei aendert sich oft nur die Size (FileAge
    // hat ~1s Granularitaet), daher beide vergleichen.
    if (CurrMTime <> 0)
       and (CurrMTime = Entry.MTime)
       and (CurrSize = Entry.Size) then
      Exit(Entry.Lines);
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
  FCache.Add(K, TFileTextCacheEntry.Create(SL, CurrMTime, CurrSize));
  Result := SL;
end;

procedure TFileTextCache.Clear;
begin
  FCache.Clear;
end;

// --- Wrapper-Funktionen ---

function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean; ACache: TFileTextCache): TStringList;
var
  Cache: TFileTextCache;
begin
  OwnedByCache := False;
  // Per-Scan-Cache (Context) bevorzugen; nil -> Prozess-Global.
  Cache := ACache;
  if Cache = nil then Cache := gFileTextCache;
  if Assigned(Cache) then
  begin
    Result := Cache.GetLines(FileName);
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
