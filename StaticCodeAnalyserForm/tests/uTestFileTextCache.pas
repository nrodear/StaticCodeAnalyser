unit uTestFileTextCache;

// Direkttests fuer den Datei-Text-Cache (uFileTextCache): der
// Nutzerzaehler je Eintrag (Review Bereich C Engine-Kern, Blocker 1,
// 2026-10-14) und der Dekodierpfad von LoadFileSmart (Major 15).
//
// Anlass Blocker 1: der IDE-Massenscan leert den Cache je Datei, waehrend
// "Write baseline" auf einem anderen Thread ueber ContextHashFor gerade
// Zeilen desselben Caches liest. Vorher gab Clear die TStringList frei,
// der Leser las freigegebenen Speicher. Die Tests halten Zeilen, raeumen
// den Cache auf einem anderen Thread und lesen danach weiter.
//
// Eigene Cache-Instanz je Test (nicht gFileTextCache): der Testprozess ist
// resident, und andere Fixtures fuellen das Prozess-Global nebenher.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,   // TBytes in der Signatur von Schreibe
  uFileTextCache;

type
  [TestFixture]
  TTestFileTextCache = class
  strict private
    FDir   : string;
    FCache : TFileTextCache;
    function SchreibeBytes(const AName: string; const ABytes: TBytes): string;
    function Schreibe(const AName, AText: string): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    // ---- Nutzerzaehler ----
    [Test] procedure Clear_WhileReaderHoldsLines_LinesStayValid;
    [Test] procedure Clear_OnOtherThread_WhileReaderHoldsLines;
    [Test] procedure RemoveFile_DetachesHeldEntry_NextGetLoadsFresh;
    [Test] procedure ForceStat_StaleEntry_OldReaderKeepsOldLines;
    [Test] procedure ReleaseLines_NilAndForeignList_Harmless;
    [Test] procedure AcquireLines_WithoutCache_CallerOwnsList;

    // ---- Dekodierpfad ----
    [Test] procedure LoadFileSmart_Utf8BomWithInvalidByte_NotBlind;
    [Test] procedure LoadFileSmart_NoBomOverlongUtf8_ReadAsDefaultCodepage;
    [Test] procedure LoadFileSmart_NoBomValidUtf8_DecodedAsUtf8;

    // ---- Encoding-Verdikt ----
    [Test] procedure AcquireEncodingInfo_CacheMatchesFreshAnalysis;
    [Test] procedure AcquireEncodingInfo_MissingFile_NotReadable;
    [Test] procedure TryGetEncodingInfo_ThenClear_EntryGone;
  end;

implementation

uses
  System.Classes, System.IOUtils;

{ Helfer }

function TTestFileTextCache.SchreibeBytes(const AName: string;
  const ABytes: TBytes): string;
begin
  Result := TPath.Combine(FDir, AName);
  TFile.WriteAllBytes(Result, ABytes);
end;

function TTestFileTextCache.Schreibe(const AName, AText: string): string;
begin
  Result := SchreibeBytes(AName, TEncoding.ASCII.GetBytes(AText));
end;

procedure TTestFileTextCache.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'sca_ftc_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FDir);
  FCache := TFileTextCache.Create;
end;

procedure TTestFileTextCache.TearDown;
begin
  FreeAndNil(FCache);
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

{ ---- Nutzerzaehler ---- }

procedure TTestFileTextCache.Clear_WhileReaderHoldsLines_LinesStayValid;
var
  F      : string;
  Lines  : TStringList;
  Lines2 : TStringList;
begin
  F := Schreibe('a.pas', 'zeile 1'#13#10'zeile 2');
  Lines := FCache.GetLines(F);
  Assert.IsNotNull(Lines);
  Assert.AreEqual<Integer>(1, FCache.EntryCount);

  FCache.Clear;
  Assert.AreEqual<Integer>(0, FCache.EntryCount,
    'Clear haengt den Eintrag aus, auch wenn ihn noch jemand haelt');
  // Der Leser liest weiter: vor dem Nutzerzaehler war das freigegebener
  // Speicher.
  Assert.AreEqual<Integer>(2, Lines.Count);
  Assert.AreEqual('zeile 1', Lines[0]);

  // Ein neuer Zugriff laedt frisch - eine ANDERE Instanz, weil die alte
  // noch lebt (keine Adress-Wiederverwendung moeglich).
  Lines2 := FCache.GetLines(F);
  Assert.IsNotNull(Lines2);
  Assert.IsTrue(Lines2 <> Lines, 'nach Clear eine neue Liste');
  ReleaseLines(Lines, True);
  ReleaseLines(Lines2, True);
  Assert.AreEqual<Integer>(1, FCache.EntryCount,
    'der frische Eintrag bleibt eingehaengt');
end;

procedure TTestFileTextCache.Clear_OnOtherThread_WhileReaderHoldsLines;
// Das Szenario des Blockers: Clear auf einem Worker, der Leser auf dem
// Testthread haelt die Zeilen und liest danach.
var
  F     : string;
  Lines : TStringList;
  T     : TThread;
  Cache : TFileTextCache;
begin
  F := Schreibe('b.pas', 'unit b;'#13#10'end.');
  Cache := FCache;
  Lines := Cache.GetLines(F);
  Assert.IsNotNull(Lines);
  T := TThread.CreateAnonymousThread(
    procedure
    begin
      Cache.Clear;
      Cache.RemoveFile(F);   // zweiter Weg, derselbe Vertrag
    end);
  T.FreeOnTerminate := False;
  try
    T.Start;
    T.WaitFor;
  finally
    T.Free;
  end;
  Assert.AreEqual<Integer>(0, Cache.EntryCount);
  Assert.AreEqual('unit b;', Lines[0], 'gehaltene Zeilen bleiben lesbar');
  Assert.AreEqual('end.', Lines[1]);
  ReleaseLines(Lines, True);
end;

procedure TTestFileTextCache.RemoveFile_DetachesHeldEntry_NextGetLoadsFresh;
var
  F      : string;
  Lines  : TStringList;
  Lines2 : TStringList;
begin
  F := Schreibe('c.pas', 'c');
  Lines := FCache.GetLines(F);
  FCache.RemoveFile(F);
  Assert.AreEqual<Integer>(0, FCache.EntryCount);
  Assert.AreEqual('c', Lines[0]);
  Lines2 := FCache.GetLines(F);
  Assert.IsTrue(Lines2 <> Lines, 'RemoveFile: der naechste Zugriff laedt neu');
  ReleaseLines(Lines2, True);
  ReleaseLines(Lines, True);
  // Ohne Halter gibt RemoveFile sofort frei - sichtbar nur daran, dass
  // der Eintrag weg ist und ein neuer Zugriff wieder einen anlegt.
  FCache.RemoveFile(F);
  Assert.AreEqual<Integer>(0, FCache.EntryCount);
  Lines := FCache.GetLines(F);
  Assert.AreEqual<Integer>(1, FCache.EntryCount);
  ReleaseLines(Lines, True);
end;

procedure TTestFileTextCache.ForceStat_StaleEntry_OldReaderKeepsOldLines;
// Fingerprint-/Baseline-Pfad (AForceStat=True): die Datei wurde ohne
// Clear ueberschrieben. Der neue Leser sieht den neuen Inhalt, ein Leser
// der alten Zeilen behaelt sie - der veraltete Eintrag wird nur
// ausgehaengt. Die Groesse unterscheidet sich, damit der Stat-Vergleich
// unabhaengig von der mtime-Granularitaet anschlaegt.
var
  F      : string;
  Alt    : TStringList;
  Neu    : TStringList;
begin
  F := Schreibe('d.pas', 'alt');
  Alt := FCache.GetLines(F);
  Assert.AreEqual('alt', Alt[0]);
  Schreibe('d.pas', 'neu und laenger');
  Neu := FCache.GetLines(F, True);
  Assert.IsNotNull(Neu);
  Assert.IsTrue(Neu <> Alt, 'veralteter Eintrag -> neue Liste');
  Assert.AreEqual('neu und laenger', Neu[0]);
  Assert.AreEqual('alt', Alt[0], 'der alte Leser behaelt seine Zeilen');
  Assert.AreEqual<Integer>(1, FCache.EntryCount);
  ReleaseLines(Alt, True);
  ReleaseLines(Neu, True);
end;

procedure TTestFileTextCache.ReleaseLines_NilAndForeignList_Harmless;
// nil ist erlaubt; eine fremde TStringList mit OwnedByCache=True
// (Aufrufer-Fehler) wird ignoriert, nicht freigegeben - sonst waere das
// Free des Aufrufers darunter ein Doppel-Free. Und zwei Halter derselben
// Zeilen zaehlen getrennt: der Eintrag bleibt, bis BEIDE zurueckgeben.
var
  F      : string;
  Fremd  : TStringList;
  L1, L2 : TStringList;
begin
  ReleaseLines(nil, True);
  ReleaseLines(nil, False);
  Fremd := TStringList.Create;
  try
    Fremd.Add('fremd');
    ReleaseLines(Fremd, True);
    Assert.AreEqual('fremd', Fremd[0], 'fremde Liste unangetastet');
  finally
    Fremd.Free;
  end;
  F := Schreibe('e.pas', 'e');
  L1 := FCache.GetLines(F);
  L2 := FCache.GetLines(F);
  Assert.IsTrue(L1 = L2, 'Cache-Treffer: dieselbe Liste');
  FCache.Clear;             // ausgehaengt, zwei Halter
  ReleaseLines(L1, True);   // einer gibt zurueck - der andere liest weiter
  Assert.AreEqual('e', L2[0], 'zweiter Halter liest weiter');
  ReleaseLines(L2, True);   // jetzt frei
end;

procedure TTestFileTextCache.AcquireLines_WithoutCache_CallerOwnsList;
var
  F      : string;
  Lines  : TStringList;
  Cached : Boolean;
  AltG   : TFileTextCache;
begin
  F := Schreibe('f.pas', 'f');
  // Prozess-Global ausblenden, damit der Fallback laeuft.
  AltG := gFileTextCache;
  gFileTextCache := nil;
  try
    Lines := AcquireLines(F, Cached, nil);
    Assert.IsNotNull(Lines);
    Assert.IsFalse(Cached, 'ohne Cache gehoert die Liste dem Aufrufer');
    Assert.AreEqual('f', Lines[0]);
    ReleaseLines(Lines, Cached);   // Free - kein Leck, kein Zaehler
  finally
    gFileTextCache := AltG;
  end;
end;

{ ---- Dekodierpfad ---- }

procedure TTestFileTextCache.LoadFileSmart_Utf8BomWithInvalidByte_NotBlind;
// UTF-8-BOM, dahinter ein kaputtes Byte: TEncoding.UTF8 wirft, die Datei
// galt als unlesbar (nil fuer alle Datei-Detektoren). Jetzt: Default-
// Codepage hinter der BOM - der Text ist da, ein Zeichen ist Muell.
var
  F  : string;
  SL : TStringList;
begin
  F := SchreibeBytes('g.pas', TBytes.Create($EF, $BB, $BF) +
    TEncoding.ASCII.GetBytes('unit g;'#13#10'// ') + TBytes.Create($C0, $80) +
    TEncoding.ASCII.GetBytes(#13#10'end.'));
  SL := TStringList.Create;
  try
    Assert.IsTrue(LoadFileSmart(F, SL), 'nicht blind');
    Assert.AreEqual<Integer>(3, SL.Count);
    Assert.AreEqual('unit g;', SL[0], 'BOM abgeschnitten, Text lesbar');
    Assert.AreEqual('end.', SL[2]);
  finally
    SL.Free;
  end;
end;

procedure TTestFileTextCache.LoadFileSmart_NoBomOverlongUtf8_ReadAsDefaultCodepage;
// Ohne BOM: die laxe Vorpruefung hielt C0 80 fuer UTF-8, die strikte
// Dekodierung warf. Jetzt lehnt dieselbe strikte Pruefung die Sequenz ab
// und die Datei wird als Default-Codepage gelesen - jedes Byte ein Zeichen.
var
  F  : string;
  SL : TStringList;
begin
  F := SchreibeBytes('h.pas', TEncoding.ASCII.GetBytes('ab') +
    TBytes.Create($C0, $80) + TEncoding.ASCII.GetBytes('cd'));
  SL := TStringList.Create;
  try
    Assert.IsTrue(LoadFileSmart(F, SL), 'nicht blind');
    Assert.AreEqual<Integer>(1, SL.Count);
    Assert.AreEqual<Integer>(6, Length(SL[0]), 'sechs Bytes, sechs Zeichen');
    Assert.IsTrue(SL[0].StartsWith('ab') and SL[0].EndsWith('cd'));
  finally
    SL.Free;
  end;
end;

procedure TTestFileTextCache.LoadFileSmart_NoBomValidUtf8_DecodedAsUtf8;
var
  F  : string;
  SL : TStringList;
begin
  // 'ae' als U+00E4: C3 A4
  F := SchreibeBytes('i.pas', TEncoding.ASCII.GetBytes('x') +
    TBytes.Create($C3, $A4) + TEncoding.ASCII.GetBytes('y'));
  SL := TStringList.Create;
  try
    Assert.IsTrue(LoadFileSmart(F, SL));
    Assert.AreEqual<Integer>(3, Length(SL[0]), 'UTF-8 dekodiert: ein Zeichen');
    Assert.AreEqual<Integer>($E4, Ord(SL[0][2]));
  finally
    SL.Free;
  end;
end;

{ ---- Encoding-Verdikt ---- }

procedure TTestFileTextCache.AcquireEncodingInfo_CacheMatchesFreshAnalysis;
var
  F        : string;
  ViaCache : TFileEncodingInfo;
  Frisch   : TFileEncodingInfo;
begin
  F := SchreibeBytes('j.pas', TBytes.Create($EF, $BB, $BF) +
    TEncoding.ASCII.GetBytes('a'#13#10) + TBytes.Create($C3, $A4) +
    TEncoding.ASCII.GetBytes(#13#10) + TBytes.Create($FF));
  ViaCache := AcquireEncodingInfo(F, FCache);
  Frisch   := AnalyzeFileEncoding(F);
  Assert.IsTrue(ViaCache.Readable);
  Assert.IsTrue(Frisch.Readable);
  Assert.IsTrue(ViaCache.BomKind = sbkUtf8);
  Assert.IsTrue(ViaCache.BomKind = Frisch.BomKind);
  Assert.AreEqual(Frisch.HasNonAscii, ViaCache.HasNonAscii);
  Assert.AreEqual(Frisch.StrictUtf8, ViaCache.StrictUtf8);
  Assert.IsFalse(ViaCache.StrictUtf8, 'das FF in Zeile 3 ist kein UTF-8');
  Assert.AreEqual<Integer>(2, ViaCache.FirstNonAsciiLine);
  Assert.AreEqual<Integer>(3, ViaCache.FirstInvalidLine);
  Assert.AreEqual<Integer>(Frisch.MultiByteRuns, ViaCache.MultiByteRuns);
  Assert.AreEqual<Integer>(1, FCache.EntryCount,
    'der Piggyback-Pfad legt den Eintrag an');
end;

procedure TTestFileTextCache.AcquireEncodingInfo_MissingFile_NotReadable;
var
  Info : TFileEncodingInfo;
begin
  Info := AcquireEncodingInfo(TPath.Combine(FDir, 'gibt-es-nicht.pas'), FCache);
  Assert.IsFalse(Info.Readable);
  Assert.AreEqual<Integer>(0, FCache.EntryCount, 'kein Eintrag fuer nichts');
end;

procedure TTestFileTextCache.TryGetEncodingInfo_ThenClear_EntryGone;
// TryGetEncodingInfo haelt keinen Eintrag: nach Clear ist er weg, ein
// neuer Zugriff legt ihn wieder an (sonst bliebe er bis Prozessende).
var
  F    : string;
  Info : TFileEncodingInfo;
  L    : TStringList;
begin
  F := Schreibe('k.pas', 'k');
  Assert.IsTrue(FCache.TryGetEncodingInfo(F, Info));
  Assert.IsTrue(Info.Readable);
  Assert.AreEqual<Integer>(1, FCache.EntryCount);
  FCache.Clear;
  Assert.AreEqual<Integer>(0, FCache.EntryCount);
  L := FCache.GetLines(F);
  Assert.IsNotNull(L);
  Assert.AreEqual<Integer>(1, FCache.EntryCount);
  ReleaseLines(L, True);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileTextCache);

end.
