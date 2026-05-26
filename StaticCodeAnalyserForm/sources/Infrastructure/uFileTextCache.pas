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
  TFileTextCache = class
  private
    FCache : TObjectDictionary<string, TStringList>;
    function Key(const FileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Liefert TStringList fuer FileName. Cache besitzt die Liste -
    // NICHT freigeben. Nil bei Read-Fehler.
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
function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean): TStringList;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);

implementation

uses
  System.Math, System.IOUtils;

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

constructor TFileTextCache.Create;
begin
  inherited;
  FCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
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

function TFileTextCache.GetLines(const FileName: string): TStringList;
var
  K  : string;
  SL : TStringList;
begin
  Result := nil;
  K := Key(FileName);
  if FCache.TryGetValue(K, Result) then Exit;
  if not FileExists(FileName) then Exit;

  SL := TStringList.Create;
  try
    if not LoadFileSmart(FileName, SL) then
      FreeAndNil(SL);
  except
    FreeAndNil(SL);
  end;

  if SL = nil then Exit;
  FCache.Add(K, SL);
  Result := SL;
end;

procedure TFileTextCache.Clear;
begin
  FCache.Clear;
end;

// --- Wrapper-Funktionen ---

function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean): TStringList;
begin
  OwnedByCache := False;
  if Assigned(gFileTextCache) then
  begin
    Result := gFileTextCache.GetLines(FileName);
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

initialization

finalization
  if Assigned(gFileTextCache) then
    FreeAndNil(gFileTextCache);

end.
