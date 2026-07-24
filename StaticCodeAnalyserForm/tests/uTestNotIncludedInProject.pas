unit uTestNotIncludedInProject;

// Tests fuer SCA194 - TNotIncludedInProjectDetector (uNotIncludedInProject).
// Fixtures on-the-fly in ein Temp-Verzeichnis (kein Repo-Fixture-Sync).
// Getestet wird die reine Detect-Kernfunktion (Projektliste + Walk-Root ->
// Orphan-Findings); die Scope-Gating-Verdrahtung liegt in uEngineApi und ist
// nicht Teil dieses Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNotIncludedInProject = class
  private
    FDir : string;
    function W(const ARel: string): string;   // schreibt leere Datei, gibt Vollpfad
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure OrphanPas_Flagged;
    [Test] procedure IncludedPas_NotFlagged;
    [Test] procedure OrphanDfm_Flagged_WhenPasNotInProject;
    [Test] procedure CompanionDfm_NotFlagged_WhenPasInProject;
    [Test] procedure ExcludedDirs_Skipped;
    [Test] procedure SubfolderOrphan_Found;
    [Test] procedure CaseInsensitive_Match;
    [Test] procedure EmptyProject_AllDiskFilesOrphan;
    // Impl-Review 2026-07-24 (5 bestaetigte Testluecken; Cap-Verhalten bleibt
    // bewusst ungetestet - 20k-Fixtures sind Unit-Test-untauglich):
    [Test] procedure IgnoreList_FileAndDirParity;
    [Test] procedure RelativeWalkRoot_CanonicalMatch;
    [Test] procedure DfmAndPasMessages_Distinct;
    [Test] procedure Findings_SortedByPath;
    [Test] procedure CompanionDfm_OtherDirectory_StillOrphan;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts, uIgnoreList, uNotIncludedInProject;

procedure TTestNotIncludedInProject.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_orphan_' + TGUID.NewGuid.ToString.Trim(['{','}']));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestNotIncludedInProject.TearDown;
begin
  try
    if (FDir <> '') and TDirectory.Exists(FDir) then
      TDirectory.Delete(FDir, True);
  except
  end;
end;

function TTestNotIncludedInProject.W(const ARel: string): string;
begin
  Result := TPath.Combine(FDir, ARel);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, '// fixture');
end;

// --- Helfer: Detect ausfuehren, verwaiste FileNames zurueckgeben ---
function RunDetect(const AProjList: array of string; const AWalkRoot: string;
  out ACount: Integer; AIgnore: TIgnoreList = nil): TStringList;
var
  Proj : TStringList;
  Res  : TObjectList<TLeakFinding>;
  s    : string;
  i    : Integer;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Proj := TStringList.Create;
  Res  := TObjectList<TLeakFinding>.Create(True);
  try
    for s in AProjList do Proj.Add(s);
    ACount := TNotIncludedInProjectDetector.Detect(Proj, AWalkRoot, Res, AIgnore);
    for i := 0 to Res.Count - 1 do
    begin
      Assert.AreEqual(Ord(fkNotIncludedInProject), Ord(Res[i].Kind),
        'nur fkNotIncludedInProject erwartet');
      Result.Add(Res[i].FileName);
    end;
  finally
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.OrphanPas_Flagged;
var
  incl, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uMain.pas');
  orph := W('uOld.pas');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(1, cnt, 'genau ein Orphan');
    Assert.IsTrue(found.IndexOf(orph) >= 0, 'uOld.pas verwaist');
    Assert.IsTrue(found.IndexOf(incl) < 0, 'uMain.pas gehoert zum Projekt');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.IncludedPas_NotFlagged;
var
  a, b : string;
  cnt : Integer;
  found : TStringList;
begin
  a := W('uA.pas');
  b := W('uB.pas');
  found := RunDetect([a, b], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'alle im Projekt -> keine Orphans');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.OrphanDfm_Flagged_WhenPasNotInProject;
var
  incl, orphPas, orphDfm : string;
  cnt : Integer;
  found : TStringList;
begin
  incl    := W('uMain.pas');
  orphPas := W('uForm.pas');
  orphDfm := W('uForm.dfm');
  // uForm.pas NICHT im Projekt -> sowohl .pas als auch .dfm verwaist.
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(2, cnt, 'uForm.pas + uForm.dfm verwaist');
    Assert.IsTrue(found.IndexOf(orphPas) >= 0);
    Assert.IsTrue(found.IndexOf(orphDfm) >= 0);
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.CompanionDfm_NotFlagged_WhenPasInProject;
var
  incl, dfm : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uForm.pas');
  dfm  := W('uForm.dfm');
  // uForm.pas IST im Projekt -> Companion .dfm gilt als eingeschlossen.
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'Companion-DFM zur eingeschlossenen .pas ist kein Orphan');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.ExcludedDirs_Skipped;
var
  incl : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uMain.pas');
  W('__history\uMain.~pas');   // .~pas ohnehin ignoriert
  W('.git\uSomething.pas');    // in .git -> ganzer Ordner uebersprungen
  W('__recovery\uX.pas');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'Dateien in Exclude-Ordnern zaehlen nicht');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.SubfolderOrphan_Found;
var
  incl, orph : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uMain.pas');
  orph := W('sub\deep\uBuried.pas');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(1, cnt);
    Assert.IsTrue(found.IndexOf(orph) >= 0, 'Orphan in Unterordner gefunden');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.CaseInsensitive_Match;
var
  onDisk : string;
  cnt : Integer;
  found : TStringList;
begin
  onDisk := W('uMain.pas');
  // Projektliste in anderer Schreibweise -> darf NICHT als Orphan gelten.
  found := RunDetect([UpperCase(onDisk)], FDir, cnt);
  try
    Assert.AreEqual(0, cnt, 'case-insensitiver Pfad-Match');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.EmptyProject_AllDiskFilesOrphan;
var
  cnt : Integer;
  found : TStringList;
begin
  W('uA.pas');
  W('uB.pas');
  // Leere Projektliste -> beide .pas verwaist.
  found := RunDetect([], FDir, cnt);
  try
    Assert.AreEqual(2, cnt);
  finally
    found.Free;
  end;
end;

// --- Impl-Review 2026-07-24: die 5 bestaetigten Testluecken ---

procedure TTestNotIncludedInProject.IgnoreList_FileAndDirParity;
// ignore.txt-Parity war explizite Review-Anforderung des Unit-Headers,
// aber KEIN Test uebergab je eine TIgnoreList: Datei-Skip (Detect ~Z.143)
// und Verzeichnis-Skip via dummy.pas-Trick (~Z.134) waren beide ungedeckt.
var
  incl, orphReal, ignFile : string;
  Proj : TStringList;
  Res  : TObjectList<TLeakFinding>;
  Ign  : TIgnoreList;
begin
  incl     := W('uMain.pas');
  orphReal := W('uReal.pas');            // Kontroll-Orphan: bleibt gemeldet
  W('uSkipped.pas');                     // per Datei-Pattern ignoriert
  W('legacy\uOld.pas');                  // per Verzeichnis-Pattern ignoriert
  ignFile := TPath.Combine(FDir, 'ignore.txt');
  TFile.WriteAllText(ignFile, 'uSkipped.pas'#13#10 + 'legacy/'#13#10);
  Proj := TStringList.Create;
  Res  := TObjectList<TLeakFinding>.Create(True);
  Ign  := TIgnoreList.Create;
  try
    Ign.SkipTests := False;
    Ign.LoadFromFile(ignFile);
    Proj.Add(incl);
    Assert.AreEqual(1,
      TNotIncludedInProjectDetector.Detect(Proj, FDir, Res, Ign),
      'nur uReal.pas bleibt Orphan - Datei- UND Verzeichnis-Ignore greifen');
    Assert.AreEqual(orphReal, Res[0].FileName);
  finally
    Ign.Free;
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.RelativeWalkRoot_CanonicalMatch;
// NormKey-Kanonisierung (GetFullPath beidseitig): ein Walk-Root mit
// '..'-Segment liefert nicht-kanonische Walk-Pfade - ohne GetFullPath in
// NormKey matcht keine Projektdatei mehr und ALLES wird Orphan (der
// dokumentierte FP-Storm aus dem Review 2026-07-22). Alle bisherigen
// Tests nutzten bereits kanonische Pfade und haetten das nie bemerkt.
var
  incl, subPas, walkRoot : string;
  cnt : Integer;
  found : TStringList;
begin
  incl     := W('uMain.pas');
  subPas   := W('sub\uSub.pas');
  walkRoot := TPath.Combine(FDir, 'sub') + '\..';
  found := RunDetect([incl, subPas], walkRoot, cnt);
  try
    Assert.AreEqual(0, cnt,
      'nicht-kanonischer Walk-Root (..-Segment) darf keine FPs erzeugen');
  finally
    found.Free;
  end;
end;

procedure TTestNotIncludedInProject.DfmAndPasMessages_Distinct;
// Tag-Message-Kopplung: die Object-Tags (0=.pas/1=.dfm) wandern beim Sort
// mit und steuern die Message. Bisher pruefte kein Test die Messages -
// eine vertauschte Zuordnung waere unbemerkt geblieben. Diskriminator:
// 'form' kommt NUR in der .dfm-Message vor.
var
  Proj : TStringList;
  Res  : TObjectList<TLeakFinding>;
  i : Integer;
  msgLow : string;
begin
  W('uForm.pas');
  W('uForm.dfm');
  Proj := TStringList.Create;
  Res  := TObjectList<TLeakFinding>.Create(True);
  try
    Assert.AreEqual(2, TNotIncludedInProjectDetector.Detect(Proj, FDir, Res));
    for i := 0 to Res.Count - 1 do
    begin
      msgLow := Res[i].MissingVar.ToLower;
      if Res[i].FileName.ToLower.EndsWith('.dfm') then
        Assert.IsTrue(msgLow.Contains('form'),
          '.dfm-Orphan traegt die Form-Message')
      else
        Assert.IsFalse(msgLow.Contains('form file'),
          '.pas-Orphan traegt NICHT die Form-Message');
    end;
  finally
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.Findings_SortedByPath;
// Sort-Determinismus (SARIF-Byte-Stabilitaet): die Ausgabe muss exakt der
// TStringList-Sortierung (case-insensitiv) entsprechen - unabhaengig von
// der FS-abhaengigen FindFirst-Reihenfolge. Fixture so gewaehlt, dass die
// Walk-Reihenfolge (Verzeichnis 'a' vor Datei 'a!.pas') von der sortierten
// Pfad-Reihenfolge abweichen kann.
var
  Proj     : TStringList;
  Res      : TObjectList<TLeakFinding>;
  Expected : TStringList;
  i : Integer;
begin
  W('a\x.pas');
  W('a!.pas');
  W('m.pas');
  Proj     := TStringList.Create;
  Res      := TObjectList<TLeakFinding>.Create(True);
  Expected := TStringList.Create;
  Expected.CaseSensitive := False;
  try
    Assert.AreEqual(3, TNotIncludedInProjectDetector.Detect(Proj, FDir, Res));
    for i := 0 to Res.Count - 1 do
      Expected.Add(Res[i].FileName);
    Expected.Sort;
    for i := 0 to Res.Count - 1 do
      Assert.AreEqual(Expected[i], Res[i].FileName,
        'Findings exakt in sortierter Pfad-Reihenfolge (Index ' +
        IntToStr(i) + ')');
  finally
    Expected.Free;
    Res.Free;
    Proj.Free;
  end;
end;

procedure TTestNotIncludedInProject.CompanionDfm_OtherDirectory_StillOrphan;
// Companion-Match ist VOLLPFAD-basiert: eine namensgleiche .dfm in einem
// anderen Verzeichnis als die referenzierte .pas ist KEIN Companion und
// bleibt Orphan. Bisher war nur der Gleiches-Verzeichnis-Fall getestet.
var
  incl, dfm : string;
  cnt : Integer;
  found : TStringList;
begin
  incl := W('uForm.pas');
  dfm  := W('sub\uForm.dfm');
  found := RunDetect([incl], FDir, cnt);
  try
    Assert.AreEqual(1, cnt,
      'namensgleiche .dfm in anderem Verzeichnis ist kein Companion');
    Assert.IsTrue(found.IndexOf(dfm) >= 0);
  finally
    found.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNotIncludedInProject);

end.
